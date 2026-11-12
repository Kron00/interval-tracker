import Foundation
import IntervalCore
import Testing

let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

func ms(_ date: Date) -> Int {
    Int((date.timeIntervalSince(t0) * 1000).rounded())
}

func session(_ definition: TimerDefinition = .norwegian4x4,
             cues: CuePreferences = CuePreferences()) -> Session {
    Session(definition, cues: cues, startingAt: t0)
}

struct UnexpectedlyFinished: Error {}

func progress(_ session: Session, at offset: TimeInterval) throws -> RunProgress {
    guard case .active(let progress) = session.snapshot(at: t0 + offset) else {
        throw UnexpectedlyFinished()
    }
    return progress
}

func timer(warmUp: Int? = nil, work: Int, rest: Int? = nil, rounds: Int = 1, coolDown: Int? = nil,
           restAfterLastRound: Bool = true) throws -> TimerDefinition {
    func span(_ seconds: Int?) throws -> Span? {
        try seconds.map { try #require(Span(seconds: $0)) }
    }
    return TimerDefinition(
        name: "Test", warmUp: try span(warmUp), work: try #require(Span(seconds: work)),
        rest: try span(rest), rounds: try #require(RoundCount(rounds)), coolDown: try span(coolDown),
        restAfterLastRound: restAfterLastRound)
}

func describe(_ phase: Phase?) -> String {
    switch phase {
    case .warmUp: "warmUp"
    case .work(let round): "work \(round.number)/\(round.total)"
    case .rest(let round): "rest \(round.number)/\(round.total)"
    case .coolDown: "coolDown"
    case nil: "none"
    }
}

struct Step: Equatable, CustomStringConvertible {
    let phase: String
    let start: Int
    let duration: Int

    init(_ phase: String, start: Int, duration: Int) {
        self.phase = phase; self.start = start; self.duration = duration
    }

    var description: String { "\(phase) @\(start) for \(duration)" }
}

func steps(of definition: TimerDefinition) -> [Step] {
    let run = session(definition)
    var steps: [Step] = []
    var offset: TimeInterval = 0
    while case .active(let progress) = run.snapshot(at: t0 + offset), steps.count < 1000 {
        steps.append(Step(describe(progress.phase), start: Int(offset), duration: Int(progress.phaseRemaining)))
        offset += progress.phaseRemaining
    }
    return steps
}

struct Cue: Equatable, CustomStringConvertible {
    let ms: Int
    let sound: Sound

    init(_ ms: Int, _ sound: Sound) {
        self.ms = ms; self.sound = sound
    }

    var description: String { "\(sound) @\(ms)ms" }
}

func cues(_ window: DuckWindow) -> [Cue] {
    window.sounds.map { Cue(ms($0.at), $0.sound) }
}

func cues(_ schedule: CueSchedule) -> [Cue] {
    schedule.windows.flatMap { cues($0) }
}
