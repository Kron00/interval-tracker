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

public enum Phrase: Hashable, Sendable {
    case warmUp, round(Int), lastRound, rest, coolDown, done

    init(announcing phase: Phase) {
        self = switch phase {
        case .warmUp: .warmUp
        case .work(let round): round.isLast && round.total > 1 ? .lastRound : .round(round.number)
        case .rest: .rest
        case .coolDown: .coolDown
        }
    }

    public var spokenText: String {
        switch self {
        case .warmUp: return "Warm up"
        case .round(let number):
            let formatter = NumberFormatter()
            formatter.numberStyle = .spellOut
            formatter.locale = Locale(identifier: "en_US")
            return "Round " + (formatter.string(from: number as NSNumber) ?? String(number))
        case .lastRound: return "Last round"
        case .rest: return "Rest"
        case .coolDown: return "Cool down"
        case .done: return "Workout complete"
        }
    }
}

public enum Sound: Hashable, Sendable {
    case tick
    case phaseChange
    case finish
    case voice(Phrase)

    /// The longest this sound may last. The schedule reserves exactly this much time for it, and the
    /// app's SoundBank must deliver a buffer no longer than this.
    public var slot: TimeInterval {
        switch self {
        case .tick: 0.12
        case .phaseChange: 0.40
        case .finish: 0.90
        case .voice: 1.50
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

public struct CueSchedule: Equatable, Sendable {
    /// Sorted and disjoint, with at least `mergeGap` between neighbours.
    public let windows: [DuckWindow]

    init(_ timeline: Timeline, _ preferences: CuePreferences, zeroAt: Date) {
        var cues: [(offset: TimeInterval, sound: Sound)] = []
        for segment in timeline.segments {
            cues.append((segment.start, .phaseChange))
            let voice = Sound.voice(Phrase(announcing: segment.phase))
            // A phrase that cannot finish inside its phase would talk over the next tone.
            if preferences.voice, CueTiming.voiceDelay + voice.slot <= segment.duration {
                cues.append((segment.start + CueTiming.voiceDelay, voice))
            }
            for secondsBefore in stride(from: preferences.countdown.rawValue, through: 1, by: -1) {
                let offset = segment.end - TimeInterval(secondsBefore)
                if offset >= segment.start + CueTiming.quietHead { cues.append((offset, .tick)) }
            }
        }
        cues.append((timeline.total, .finish))
        if preferences.voice {
            cues.append((timeline.total + CueTiming.finishVoiceDelay, .voice(.done)))
        }

        var windows: [DuckWindow] = []
        for (offset, sound) in cues {
            let start = zeroAt + max(0, offset - CueTiming.duckLead)
            let end = zeroAt + (offset + sound.slot + CueTiming.duckRelease)
            let timed = TimedSound(at: zeroAt + offset, sound: sound)
            if let open = windows.last, start.timeIntervalSince(open.end) < CueTiming.mergeGap {
                windows[windows.count - 1] = DuckWindow(
                    start: open.start, end: max(open.end, end), sounds: open.sounds + [timed])
            } else {
                windows.append(DuckWindow(start: start, end: end, sounds: [timed]))
            }
        }
        self.windows = windows
    }

    public var isEmpty: Bool { windows.isEmpty }

    public var end: Date? { windows.last?.end }

    public var vocabulary: Set<Sound> { Set(windows.flatMap(\.sounds).map(\.sound)) }

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
