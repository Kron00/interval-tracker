import Foundation

public enum Countdown: Int, Hashable, Sendable, Codable, CaseIterable {
    case off = 0, three = 3, five = 5
}

/// How long before work begins an interval timer says to get ready.
public enum HeadsUp: Int, Hashable, Sendable, Codable, CaseIterable {
    case off = 0, ten = 10, thirty = 30

    var lead: TimeInterval? {
        self == .off ? nil : TimeInterval(rawValue)
    }

    var words: Utterance? {
        switch self {
        case .off: nil
        case .ten: Utterance("Get ready. Ten seconds.")
        case .thirty: Utterance("Get ready. Thirty seconds.")
        }
    }
}

public struct CuePreferences: Hashable, Sendable, Codable {
    public var countdown: Countdown
    public var voice: Bool
    public var headsUp: HeadsUp

    public init(countdown: Countdown = .three, voice: Bool = true, headsUp: HeadsUp = .thirty) {
        self.countdown = countdown; self.voice = voice; self.headsUp = headsUp
    }

    /// Released versions wrote no `headsUp`, so a file without it reads as the default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        countdown = try container.decode(Countdown.self, forKey: .countdown)
        voice = try container.decode(Bool.self, forKey: .voice)
        headsUp = try container.decodeIfPresent(HeadsUp.self, forKey: .headsUp) ?? CuePreferences().headsUp
    }
}

public struct Utterance: Hashable, Sendable {
    public let text: String

    public init(_ text: String) { self.text = text }

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
    /// How long after a skip by hand the place it landed on is announced. Each skip replaces the
    /// schedule, so a run of quick skips is silent and only the last landing is announced.
    static let settle: TimeInterval = 1.0
    /// A phase gets a heads-up only when it has run at least this long by then, so the heads-up
    /// never follows right after the phase's own announcement.
    static let headsUpMargin: TimeInterval = 15
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

/// Where the run was last moved by hand, in elapsed time.
enum Arrival: Equatable, Sendable {
    /// A skip landed here. The place is announced `CueTiming.settle` after the skip.
    case landing(TimeInterval)
    /// Restart went back to here. The place is announced at once.
    case restart(TimeInterval)
}

/// The cues a run plays without help: up to the gate it will wait at, or up to the finish.
public struct CueSchedule: Equatable, Sendable {
    /// Sorted and disjoint, with at least `mergeGap` between neighbours.
    public let windows: [DuckWindow]

    private struct Cue {
        let offset: TimeInterval
        let sound: Sound
        /// When the music goes down for this sound.
        var duckFrom: TimeInterval

        init(_ offset: TimeInterval, _ sound: Sound) {
            self.offset = offset
            self.sound = sound
            duckFrom = max(0, offset - CueTiming.duckLead)
        }
    }

    /// `arrival` is where the run was last moved by hand. After a skip, the phase it landed on, or
    /// the finish, is announced `CueTiming.settle` later, and the music goes down at the skip.
    init(_ timeline: Timeline, _ preferences: CuePreferences, zeroAt: Date, released: Int, arrival: Arrival?) {
        var cues = Self.cues(in: timeline.leg(after: released), of: timeline, preferences, arrival: arrival)
        let landing: TimeInterval? = if case .landing(let point) = arrival { point } else { nil }
        if timeline.gate(after: released) == nil { cues += Self.finish(of: timeline, preferences, landing: landing) }

        let spans = cues.map {
            (start: $0.duckFrom, end: $0.offset + $0.sound.slot + CueTiming.duckRelease)
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
        return (cues(in: timeline.segments[...], of: timeline, preferences, arrival: nil)
            + finish(of: timeline, preferences, landing: nil))
            .map(\.sound).filter { seen.insert($0).inserted }
    }

    /// In time order.
    private static func cues(in segments: ArraySlice<Segment>, of timeline: Timeline,
                             _ preferences: CuePreferences, arrival: Arrival?) -> [Cue] {
        var cues: [Cue] = []
        for segment in segments {
            if segment.phase.isCountIn {
                // A count-in is all countdown: a tick on each of its seconds, and the hold follows.
                if preferences.countdown != .off {
                    cues += stride(from: segment.start, to: segment.end, by: 1).map { Cue($0, .tick) }
                }
                continue
            }
            let landed = arrival == .landing(segment.start)
            let delay = landed ? CueTiming.settle : 0
            let announced = segment.start + delay
            var quietUntil = announced + CueTiming.quietHead
            // The tone says a phase ran out. Nothing starts with one: not the workout, not a hold after
            // its count-in or straight after Start, and not a place the run was moved to by hand. A
            // gate never runs out: Start or Next ends it.
            let previous = segment.id.index > 0 ? timeline.segments[segment.id.index - 1] : nil
            if let previous, !previous.isGate, !previous.phase.isCountIn,
               !landed, arrival != .restart(segment.start) {
                cues.append(Cue(segment.start, .phaseChange))
            }
            // A phrase that cannot finish inside its phase would talk over the next tone. A gate holds
            // the run, so nothing follows its phrase.
            if preferences.voice, let words = segment.phase.announcement,
               segment.isGate || delay + CueTiming.voiceDelay + words.slot <= segment.duration {
                var name = Cue(announced + CueTiming.voiceDelay, .voice(words))
                // The music goes down at the skip, so a locked phone answers the tap and a run of taps
                // keeps it down. A landing with nothing to announce makes no sound, so it has no dip.
                if landed { name.duckFrom = segment.start }
                cues.append(name)
                quietUntil = max(quietUntil, name.offset + words.slot)
            }
            if preferences.voice, let offset = timeline.headsUp(in: segment, preferences.headsUp),
               let words = preferences.headsUp.words {
                cues.append(Cue(offset, .voice(words)))
                quietUntil = max(quietUntil, offset + words.slot)
            }
            for secondsBefore in stride(from: preferences.countdown.rawValue, through: 1, by: -1) {
                let offset = segment.end - TimeInterval(secondsBefore)
                if offset >= quietUntil { cues.append(Cue(offset, .tick)) }
            }
        }
        return cues
    }

    private static func finish(of timeline: Timeline, _ preferences: CuePreferences, landing: TimeInterval?) -> [Cue] {
        let landed = timeline.total == landing
        let tone = timeline.total + (landed ? CueTiming.settle : 0)
        var finish = Cue(tone, .finish)
        if landed { finish.duckFrom = timeline.total }
        return preferences.voice ? [finish, Cue(tone + CueTiming.finishVoiceDelay, .voice(.workoutComplete))] : [finish]
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
