import Foundation
import IntervalCore
import Testing

let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

func ms(_ date: Date) -> Int {
    Int((date.timeIntervalSince(t0) * 1000).rounded())
}

func session(_ workout: Workout = .norwegian4x4,
             cues: CuePreferences = CuePreferences()) -> Session {
    Session(workout, cues: cues, startingAt: t0)
}

struct UnexpectedlyFinished: Error {}

func progress(_ session: Session, at offset: TimeInterval) throws -> RunProgress {
    guard case .active(let progress) = session.snapshot(at: t0 + offset) else {
        throw UnexpectedlyFinished()
    }
    return progress
}

func span(_ seconds: Int) throws -> Span {
    try #require(Span(seconds: seconds))
}

func count(_ value: Int) throws -> Count {
    try #require(Count(value))
}

func timer(warmUp: Int? = nil, work: Int, rest: Int? = nil, rounds: Int = 1, coolDown: Int? = nil,
           restAfterLastRound: Bool = true) throws -> Workout {
    Workout(name: "Test", plan: .intervals(Intervals(
        warmUp: try warmUp.map(span), work: try span(work), rest: try rest.map(span),
        rounds: try count(rounds), coolDown: try coolDown.map(span),
        restAfterLastRound: restAfterLastRound)))
}

struct NotAnIntervalTimer: Error {}

func editing(_ workout: Workout, _ edit: (inout Intervals) throws -> Void) throws -> Workout {
    guard case .intervals(var intervals) = workout.plan else { throw NotAnIntervalTimer() }
    try edit(&intervals)
    var edited = workout
    edited.plan = .intervals(intervals)
    return edited
}

func hold(_ seconds: Int) throws -> Amount {
    .hold(try span(seconds))
}

func reps(_ number: Int, every seconds: Int) throws -> Amount {
    .reps(try count(number), every: try span(seconds))
}

func stretch(_ name: String, _ amount: Amount, _ sides: Sides = .once, howTo: String? = nil) throws -> Stretch {
    let link = try howTo.map { try #require(URL(string: $0)) }
    return try #require(Stretch(name: name, amount: amount, sides: sides, howTo: link))
}

func routine(getReady: Int = 10, switchSides: Int = 5, _ stretches: [Stretch]) throws -> Workout {
    let routine = Routine(getReady: try span(getReady), switchSides: try span(switchSides), stretches: stretches)
    return Workout(name: "Test", plan: .routine(try #require(routine)))
}

func describe(_ phase: Phase?) -> String {
    func describe(_ pose: Pose) -> String {
        let side = switch pose.side {
        case .left: " left"
        case .right: " right"
        case nil: ""
        }
        return "\(pose.stretch.name)\(side) \(pose.position.number)/\(pose.position.total)"
    }
    return switch phase {
    case .warmUp: "warmUp"
    case .work(let round): "work \(round.number)/\(round.total)"
    case .rest(let round): "rest \(round.number)/\(round.total)"
    case .coolDown: "coolDown"
    case .getReady(let pose): "getReady \(describe(pose))"
    case .hold(let pose): "hold \(describe(pose))"
    case .switchSides(let pose): "switchSides to \(describe(pose))"
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

func steps(of workout: Workout) -> [Step] {
    let run = session(workout)
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

func voice(_ text: String) -> Sound {
    .voice(Utterance(text))
}

func cues(_ window: DuckWindow) -> [Cue] {
    window.sounds.map { Cue(ms($0.at), $0.sound) }
}

func cues(_ schedule: CueSchedule) -> [Cue] {
    schedule.windows.flatMap { cues($0) }
}

func spoken(_ schedule: CueSchedule) -> [String] {
    cues(schedule).compactMap { cue in
        if case .voice(let utterance) = cue.sound { utterance.text } else { nil }
    }
}

func schedule(_ workout: Workout = .norwegian4x4,
              countdown: Countdown = .three, voice: Bool = true) throws -> CueSchedule {
    try #require(session(workout, cues: CuePreferences(countdown: countdown, voice: voice)).cueSchedule)
}

func bounds(_ window: DuckWindow) -> [Int] {
    [ms(window.start), ms(window.end)]
}
