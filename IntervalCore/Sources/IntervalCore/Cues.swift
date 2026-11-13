import Foundation

public enum Countdown: Int, Hashable, Sendable, Codable, CaseIterable {
    case off = 0, three = 3, five = 5
}

public struct CuePreferences: Hashable, Sendable, Codable {
    public var countdown: Countdown
    public var voice: Bool

    public init(countdown: Countdown = .three, voice: Bool = true) {
        self.countdown = countdown; self.voice = voice
    }
}

public struct Utterance: Hashable, Sendable {
    public let text: String

    public init(_ text: String) { self.text = text }

    public static let switchSides = Utterance("Switch sides")
    public static let workoutComplete = Utterance("Workout complete")

    /// The time the schedule reserves for these words: 0.4 s plus 0.06 s a character, rounded up to a
    /// tenth and kept within 1.5...4.0 s. It depends on the text alone, so the schedule needs no speech
    /// engine to be worked out.
    public var slot: TimeInterval {
        // Counted in whole hundredths, so rounding up to a tenth never depends on floating-point error.
        let hundredths = CueTiming.voiceBaseHundredths + CueTiming.voiceHundredthsPerCharacter * text.count
        let limits = CueTiming.voiceSlotTenths
        return TimeInterval(min(max((hundredths + 9) / 10, limits.lowerBound), limits.upperBound)) / 10
    }
}

public enum Sound: Hashable, Sendable {
    case tick
    /// Starts a phase, and ends a timed hold that the run then waits at.
    case phaseChange
    case finish
    case voice(Utterance)

    /// The longest this sound may last. The schedule reserves exactly this much time for it, and the
    /// app's SoundBank must deliver a buffer no longer than this.
    public var slot: TimeInterval {
        switch self {
        case .tick: 0.12
        case .phaseChange: 0.40
        case .finish: 0.90
        case .voice(let utterance): utterance.slot
        }
    }
}

enum CueTiming {
    static let duckLead: TimeInterval = 0.5
    static let voiceDelay: TimeInterval = 0.5
    static let finishVoiceDelay: TimeInterval = 1.0
    static let duckRelease: TimeInterval = 0.2
    static let mergeGap: TimeInterval = 1.5
    static let quietHead: TimeInterval = 2.0
    static let lateGrace: TimeInterval = 0.25
    static let voiceBaseHundredths = 40
    static let voiceHundredthsPerCharacter = 6
    static let voiceSlotTenths = 15...40
}

public struct TimedSound: Equatable, Sendable {
    public let at: Date
    public let sound: Sound
}

public struct DuckWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date
    /// Sorted by `at`.
    public let sounds: [TimedSound]
}

/// The cues a run plays without help: up to the gate it will wait at, or up to the finish.
public struct CueSchedule: Equatable, Sendable {
    /// Sorted and disjoint, with at least `mergeGap` between neighbours.
    public let windows: [DuckWindow]

    private typealias Cue = (offset: TimeInterval, sound: Sound)

    init(_ timeline: Timeline, _ preferences: CuePreferences, zeroAt: Date, released: Int) {
        var cues = Self.cues(in: timeline.leg(after: released), preferences)
        if let gate = timeline.gate(after: released) {
            // A gate of no length ends where it starts, and its start already has this tone.
            if gate.duration > 0 { cues.append((gate.end, .phaseChange)) }
        } else {
            cues += Self.finish(of: timeline, preferences)
        }

        let spans = cues.map {
            (start: max(0, $0.offset - CueTiming.duckLead), end: $0.offset + $0.sound.slot + CueTiming.duckRelease)
        }
        var merged: [(start: TimeInterval, end: TimeInterval)] = []
        for span in spans.sorted(by: { $0.start < $1.start }) {
            if let open = merged.last, span.start - open.end < CueTiming.mergeGap {
                merged[merged.count - 1].end = max(open.end, span.end)
            } else {
                merged.append(span)
            }
        }

        // `cues` was built in time order, so each window takes the next run of them.
        var unplaced = cues[...]
        windows = merged.map { span in
            let inside = unplaced.prefix { $0.offset <= span.end }
            unplaced = unplaced.dropFirst(inside.count)
            return DuckWindow(start: zeroAt + span.start, end: zeroAt + span.end,
                              sounds: inside.map { TimedSound(at: zeroAt + $0.offset, sound: $0.sound) })
        }
    }

    static func vocabulary(of timeline: Timeline, _ preferences: CuePreferences) -> [Sound] {
        var seen: Set<Sound> = []
        return (cues(in: timeline.segments[...], preferences) + finish(of: timeline, preferences))
            .map(\.sound).filter { seen.insert($0).inserted }
    }

    /// In time order.
    private static func cues(in segments: ArraySlice<Segment>, _ preferences: CuePreferences) -> [Cue] {
        var cues: [Cue] = []
        for segment in segments {
            cues.append((segment.start, .phaseChange))
            var quietUntil = segment.start + CueTiming.quietHead
            // A phrase that cannot finish inside its phase would talk over the next tone.
            if preferences.voice, let words = segment.phase.announcement,
               CueTiming.voiceDelay + words.slot <= segment.duration {
                let offset = segment.start + CueTiming.voiceDelay
                cues.append((offset, .voice(words)))
                quietUntil = max(quietUntil, offset + words.slot)
            }
            for secondsBefore in stride(from: preferences.countdown.rawValue, through: 1, by: -1) {
                let offset = segment.end - TimeInterval(secondsBefore)
                if offset >= quietUntil { cues.append((offset, .tick)) }
            }
        }
        return cues
    }

    private static func finish(of timeline: Timeline, _ preferences: CuePreferences) -> [Cue] {
        let voice: [Cue] = preferences.voice
            ? [(timeline.total + CueTiming.finishVoiceDelay, .voice(.workoutComplete))] : []
        return [(timeline.total, .finish)] + voice
    }

    public var isEmpty: Bool { windows.isEmpty }

    public var end: Date? { windows.last?.end }

    /// Every distinct sound, in order of first use.
    public var vocabulary: [Sound] {
        var seen: Set<Sound> = []
        return windows.flatMap(\.sounds).map(\.sound).filter { seen.insert($0).inserted }
    }

    /// What is still to do at `now`: drops windows that have closed and sounds more than `lateGrace` old,
    /// and clamps a window in progress to start at `now`. A sound within the grace keeps its (past) time;
    /// the caller plays it immediately.
    public func remaining(after now: Date) -> CueSchedule {
        let oldestPlayable = now - CueTiming.lateGrace
        return CueSchedule(windows: windows.compactMap { window in
            if window.end <= now { return nil }
            if window.start >= now { return window }
            return DuckWindow(start: now, end: window.end,
                              sounds: window.sounds.filter { $0.at >= oldestPlayable })
        })
    }

    public func isDucked(at now: Date) -> Bool {
        windows.contains { $0.start <= now && now < $0.end }
    }

    /// The next instant after `now` at which `isDucked` changes.
    public func nextEdge(after now: Date) -> Date? {
        windows.lazy.flatMap { [$0.start, $0.end] }.first { $0 > now }
    }

    private init(windows: [DuckWindow]) { self.windows = windows }
}
