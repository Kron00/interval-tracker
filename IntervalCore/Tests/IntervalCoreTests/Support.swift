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

func reps(_ number: Int) throws -> Amount {
    .reps(try count(number))
}

func stretch(_ name: String, _ amount: Amount, _ sides: Sides = .once, howTo: String? = nil) throws -> Stretch {
    let link = try howTo.map { try #require(URL(string: $0)) }
    return try #require(Stretch(name: name, amount: amount, sides: sides, howTo: link))
}

func routine(countIn: Int? = 3, _ stretches: [Stretch]) throws -> Workout {
    let routine = Routine(countIn: try countIn.map(span), stretches: stretches)
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
    case .ready(let pose): "ready \(describe(pose))"
    case .getReady(let pose): "getReady \(describe(pose))"
    case .hold(let pose): "hold \(describe(pose))"
    case nil: "none"
    }
}

struct Visit {
    /// The phase as it first appeared.
    let progress: RunProgress
    /// Whether the run stopped in the phase until Start or Next was pressed.
    var waited = false
}

struct NeverFinished: Error {}

/// Runs `workout` from start to finish the way its user would: every phase runs out, and Start or
/// Next is pressed only where the run waits.
func walk(_ workout: Workout) throws -> [Visit] {
    var run = session(workout)
    var visits: [Visit] = []
    var offset: TimeInterval = 0
    for _ in 0..<1000 {
        guard case .active(let progress) = run.snapshot(at: t0 + offset) else { return visits }
        if visits.last?.progress.segment != progress.segment { visits.append(Visit(progress: progress)) }
        if progress.isWaiting {
            visits[visits.count - 1].waited = true
            run.perform(.next, at: t0 + offset)
        } else {
            offset += progress.phaseRemaining
        }
    }
    throw NeverFinished()
}

struct Step: Equatable, CustomStringConvertible {
    let phase: String
    let start: Int
    let duration: Int
    let waits: Bool

    init(_ phase: String, start: Int, duration: Int, waits: Bool = false) {
        self.phase = phase; self.start = start; self.duration = duration; self.waits = waits
    }

    var description: String { "\(phase) @\(start) for \(duration)\(waits ? ", then waits" : "")" }
}

/// `start` is on the workout's own clock, which stands still during a wait.
func steps(of workout: Workout) throws -> [Step] {
    try walk(workout).map {
        Step(describe($0.progress.phase), start: Int($0.progress.elapsed), duration: Int($0.progress.phaseDuration),
             waits: $0.waited)
    }
}

struct NoSuchPhase: Error {}

/// A run of `workout` that enters `phase` at `t0`, so its offsets count from the start of that phase.
/// It got there the way `walk` does, with every wait ended the instant it began.
func session(_ workout: Workout, in phase: String, cues: CuePreferences = CuePreferences()) throws -> Session {
    func reach(from start: Date) throws -> (run: Session, took: TimeInterval) {
        var run = Session(workout, cues: cues, startingAt: start)
        var took: TimeInterval = 0
        for _ in 0..<1000 {
            guard case .active(let progress) = run.snapshot(at: start + took) else { break }
            if describe(progress.phase) == phase { return (run, took) }
            if progress.isWaiting {
                run.perform(.next, at: start + took)
            } else {
                took += progress.phaseRemaining
            }
        }
        throw NoSuchPhase()
    }
    return try reach(from: t0 - (try reach(from: t0).took)).run
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

/// The heads-up is off unless a test asks for it, so a test of a phase change reads only the cues
/// of that change.
func schedule(_ workout: Workout = .norwegian4x4, countdown: Countdown = .three, voice: Bool = true,
              headsUp: HeadsUp = .off) throws -> CueSchedule {
    try #require(session(workout, cues: CuePreferences(countdown: countdown, voice: voice, headsUp: headsUp)).cueSchedule)
}

/// The schedule of each leg of a run in which Start or Next is pressed the instant every wait begins.
/// Pressed then, a leg starts where the one before it stopped, so every cue reads on the workout's own clock.
func legs(_ workout: Workout, countdown: Countdown = .three, voice: Bool = true,
          headsUp: HeadsUp = .off) throws -> [CueSchedule] {
    var run = session(workout, cues: CuePreferences(countdown: countdown, voice: voice, headsUp: headsUp))
    var legs: [CueSchedule] = []
    for _ in 0..<1000 {
        legs.append(try #require(run.cueSchedule))
        let halt = try #require(run.haltDate)
        guard case .active = run.snapshot(at: halt) else { return legs }
        run.perform(.next, at: halt)
    }
    throw NeverFinished()
}

func bounds(_ window: DuckWindow) -> [Int] {
    [ms(window.start), ms(window.end)]
}
