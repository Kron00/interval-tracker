import Foundation
import IntervalCore
import Testing

private struct Row: Equatable, CustomStringConvertible {
    let title: String
    let caption: String?
    let start: Int
    let duration: Int
    let waits: Bool

    init(_ title: String, _ caption: String?, start: Int, duration: Int, waits: Bool = false) {
        self.title = title; self.caption = caption; self.start = start; self.duration = duration; self.waits = waits
    }

    var description: String {
        "\(title) (\(caption ?? "no caption")) @\(start) for \(duration)\(waits ? ", then waits" : "")"
    }
}

/// The three phases of one timed hold under a 3 s count-in: the wait for Start, the count-in, the hold.
private func timed(_ title: String, _ place: String, side: String? = nil, start: Int, hold: Int) -> [Row] {
    let caption = [side, place].compactMap { $0 }.joined(separator: " · ")
    return [
        Row(title, caption, start: start, duration: 0, waits: true),
        Row(title, ["Get ready", side].compactMap { $0 }.joined(separator: " · "), start: start, duration: 3),
        Row(title, caption, start: start + 3, duration: hold),
    ]
}

private func rows(of workout: Workout) throws -> [Row] {
    try walk(workout).map {
        Row($0.progress.phase.title, $0.progress.phase.caption,
            start: Int($0.progress.elapsed), duration: Int($0.progress.phaseDuration), waits: $0.waited)
    }
}

struct StretchValidationTests {
    @Test func theNameIsTrimmed() throws {
        let stretch = try #require(Stretch(name: "  Pigeon \n", amount: try hold(45), sides: .each, howTo: nil))
        #expect(stretch.name == "Pigeon")
    }

    @Test(arguments: ["", "   ", "\n\t", String(repeating: "a", count: 41)])
    func rejectsTheName(_ name: String) throws {
        #expect(Stretch(name: name, amount: try hold(45), sides: .once, howTo: nil) == nil)
    }

    @Test func acceptsAFortyCharacterName() throws {
        let name = String(repeating: "a", count: 40)
        #expect(Stretch(name: " \(name) ", amount: try hold(45), sides: .once, howTo: nil)?.name == name)
        #expect(Stretch(name: "a", amount: try hold(45), sides: .once, howTo: nil)?.name == "a")
        #expect(Stretch.maximumNameLength == 40)
    }

    @Test(arguments: [
        "ftp://example.com/pigeon", "file:///pigeon.mp4", "youtu.be/lqCqETr7Q0g", "javascript:alert(1)",
    ])
    func rejectsALinkThatIsNotOnTheWeb(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(Stretch(name: "Pigeon", amount: try hold(45), sides: .once, howTo: url) == nil)
    }

    @Test(arguments: ["https://youtu.be/lqCqETr7Q0g", "http://example.com/pigeon", "HTTPS://example.com/pigeon"])
    func acceptsAWebLink(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(Stretch(name: "Pigeon", amount: try hold(45), sides: .once, howTo: url)?.howTo == url)
    }

    @Test func keepsWhatItIsGiven() throws {
        let id = UUID()
        let amount = try reps(10)
        let stretch = try #require(Stretch(id: id, name: "Cat-Cow", amount: amount, sides: .each, howTo: nil))
        #expect(stretch.id == id)
        #expect(stretch.amount == amount)
        #expect(stretch.sides == .each)
        #expect(stretch.howTo == nil)
    }
}

struct RoutineValidationTests {
    private func routine(countIn: Int? = 3, stretches: Int = 1) throws -> Routine? {
        Routine(countIn: try countIn.map(span),
                stretches: try (0..<stretches).map { try stretch("Stretch \($0)", try hold(30)) })
    }

    @Test func needsAtLeastOneStretch() throws {
        #expect(try routine(stretches: 0) == nil)
        #expect(try routine(stretches: 1)?.stretches.count == 1)
    }

    @Test func holdsAtMostNinetyNineStretches() throws {
        #expect(try routine(stretches: 99)?.stretches.count == 99)
        #expect(try routine(stretches: 100) == nil)
        #expect(Routine.maximumStretches == 99)
    }

    @Test func theCountInIsThreeSecondsUnlessItIsSet() throws {
        #expect(Routine(stretches: [try stretch("Cobra", try hold(30))])?.countIn?.seconds == 3)
        #expect(try routine(countIn: 10)?.countIn?.seconds == 10)
        #expect(try #require(try routine(countIn: nil)).countIn == nil)
    }

    @Test func theCountInIsAtMostThirtySeconds() throws {
        #expect(try routine(countIn: 1)?.countIn?.seconds == 1)
        #expect(try routine(countIn: 30)?.countIn?.seconds == 30)
        #expect(try routine(countIn: 31) == nil)
        #expect(Routine.maximumCountIn == 30)
    }

    @Test func keepsItsStretchesInOrder() throws {
        let stretches = [try stretch("Cobra", try hold(30)), try stretch("Pigeon", try hold(45), .each)]
        #expect(try #require(Routine(stretches: stretches)).stretches == stretches)
    }
}

struct RoutineTimelineTests {
    @Test func dailyStretchIsTheTenBuiltInStretches() throws {
        guard case .routine(let routine) = Workout.dailyStretch.plan else {
            Issue.record("Daily Stretch is not a routine")
            return
        }
        #expect(routine.countIn?.seconds == 3)
        #expect(routine.stretches.map(\.name) == [
            "Cat-Cow", "Child's Pose", "Cobra", "Hip Flexor Couch Stretch", "Pigeon",
            "Butterfly", "Standing Hamstring", "Doorway Pec", "Thread the Needle", "Passive Dead Hang",
        ])
        #expect(routine.stretches.map(\.amount) == [
            try reps(10), try hold(45), try hold(30), try hold(45), try hold(45),
            try hold(45), try hold(45), try hold(30), try hold(30), try hold(30),
        ])
        #expect(routine.stretches.map(\.sides) == [
            .once, .once, .once, .each, .each, .once, .once, .once, .each, .once,
        ])
        #expect(routine.stretches.map(\.howTo?.absoluteString) == [
            "https://youtu.be/1Y0YjXS9sKI", "https://youtu.be/_ZX_zTOBgp8", "https://youtu.be/Aqyvevt4EUU",
            "https://youtu.be/m2u7jOCMyBg", "https://youtu.be/lqCqETr7Q0g", "https://youtu.be/MHwUChXNy-Y",
            "https://youtu.be/goN4rWbQUn4", "https://youtu.be/M850sCj9LHQ", "https://youtu.be/SkQhKf74nZk",
            "https://youtu.be/3CEmHJXbNpc",
        ])
        #expect(Set(routine.stretches.map(\.id)).count == 10)
    }

    /// 12 timed holds add up to 465 s, and each has a 3 s count-in: 465 + 36 = 501.
    @Test func dailyStretchWaitsBeforeEveryHoldAndHasEightMinutesTwentyOneOfTimedLength() throws {
        let expected = [Row("Cat-Cow", "Stretch 1 of 10", start: 0, duration: 0, waits: true)]
            + timed("Child's Pose", "Stretch 2 of 10", start: 0, hold: 45)
            + timed("Cobra", "Stretch 3 of 10", start: 48, hold: 30)
            + timed("Hip Flexor Couch Stretch", "Stretch 4 of 10", side: "Left side", start: 81, hold: 45)
            + timed("Hip Flexor Couch Stretch", "Stretch 4 of 10", side: "Right side", start: 129, hold: 45)
            + timed("Pigeon", "Stretch 5 of 10", side: "Left side", start: 177, hold: 45)
            + timed("Pigeon", "Stretch 5 of 10", side: "Right side", start: 225, hold: 45)
            + timed("Butterfly", "Stretch 6 of 10", start: 273, hold: 45)
            + timed("Standing Hamstring", "Stretch 7 of 10", start: 321, hold: 45)
            + timed("Doorway Pec", "Stretch 8 of 10", start: 369, hold: 30)
            + timed("Thread the Needle", "Stretch 9 of 10", side: "Left side", start: 402, hold: 30)
            + timed("Thread the Needle", "Stretch 9 of 10", side: "Right side", start: 435, hold: 30)
            + timed("Passive Dead Hang", "Stretch 10 of 10", start: 468, hold: 30)
        #expect(try rows(of: .dailyStretch) == expected)
        #expect(Workout.dailyStretch.totalDuration == 501)
    }

    @Test func theOutlineHasTheCountInsAndTheHoldsAndNoWaits() throws {
        let outline = Workout.dailyStretch.outline
        #expect(outline.count == 25, "one hold in reps, then a count-in and a hold for each of 12 timed holds")
        #expect(outline.map(\.duration).reduce(0, +) == 501)
        #expect(outline.filter { $0.duration == 0 }.map(\.phase.reps?.value) == [10])
        #expect(outline.allSatisfy { $0.phase.pendingHold == nil })
        #expect(outline.prefix(3).map(\.phase.caption) == ["Stretch 1 of 10", "Get ready", "Stretch 2 of 10"])
    }

    @Test func aStretchDoneOnceIsAWaitACountInAndAHold() throws {
        #expect(try steps(of: try routine(countIn: 5, [try stretch("Cobra", try hold(30))])) == [
            Step("ready Cobra 1/1", start: 0, duration: 0, waits: true),
            Step("getReady Cobra 1/1", start: 0, duration: 5),
            Step("hold Cobra 1/1", start: 5, duration: 30),
        ])
    }

    @Test func withNoCountInAStretchIsAWaitAndAHold() throws {
        let workout = try routine(countIn: nil, [try stretch("Cobra", try hold(30)), try stretch("Pigeon", try hold(45))])
        #expect(try steps(of: workout) == [
            Step("ready Cobra 1/2", start: 0, duration: 0, waits: true),
            Step("hold Cobra 1/2", start: 0, duration: 30),
            Step("ready Pigeon 2/2", start: 30, duration: 0, waits: true),
            Step("hold Pigeon 2/2", start: 30, duration: 45),
        ])
        #expect(workout.totalDuration == 75)
    }

    @Test func eachSideOfAStretchIsItsOwnWaitCountInAndHold() throws {
        #expect(try steps(of: try routine([try stretch("Pigeon", try hold(45), .each)])) == [
            Step("ready Pigeon left 1/1", start: 0, duration: 0, waits: true),
            Step("getReady Pigeon left 1/1", start: 0, duration: 3),
            Step("hold Pigeon left 1/1", start: 3, duration: 45),
            Step("ready Pigeon right 1/1", start: 48, duration: 0, waits: true),
            Step("getReady Pigeon right 1/1", start: 48, duration: 3),
            Step("hold Pigeon right 1/1", start: 51, duration: 45),
        ])
    }

    @Test func repsAreDoneOnEachSideTooWithNoCountInAndNoLength() throws {
        let workout = try routine([
            try stretch("Leg Swings", try reps(6), .each),
            try stretch("Cobra", try hold(20)),
        ])
        #expect(try steps(of: workout) == [
            Step("hold Leg Swings left 1/2", start: 0, duration: 0, waits: true),
            Step("hold Leg Swings right 1/2", start: 0, duration: 0, waits: true),
            Step("ready Cobra 2/2", start: 0, duration: 0, waits: true),
            Step("getReady Cobra 2/2", start: 0, duration: 3),
            Step("hold Cobra 2/2", start: 3, duration: 20),
        ])
        #expect(workout.totalDuration == 23)
        #expect(workout.outline.map(\.duration) == [0, 0, 3, 20])
        #expect(workout.outline.map(\.phase.reps?.value) == [6, 6, nil, nil])
    }

    @Test func theRunWaitsBeforeEveryTimedHoldAndInEveryRepStretchAndNowhereElse() throws {
        let timedLast = try routine([
            try stretch("Cobra", try hold(20)),
            try stretch("Squat", try reps(8)),
            try stretch("Pigeon", try hold(30), .each),
        ])
        let repsLast = try routine(countIn: nil, [
            try stretch("Cobra", try hold(20)),
            try stretch("Squat", try reps(8), .each),
        ])
        for workout in [timedLast, repsLast, .dailyStretch] {
            for step in try steps(of: workout) {
                #expect(step.waits == (step.duration == 0), "\(step)")
                #expect(step.phase.hasPrefix("ready") ? step.waits : true, "\(step)")
                #expect(step.phase.hasPrefix("getReady") ? !step.waits : true, "\(step)")
            }
        }
        #expect(try steps(of: timedLast).filter(\.waits).map(\.phase) == [
            "ready Cobra 1/3", "hold Squat 2/3", "ready Pigeon left 3/3", "ready Pigeon right 3/3",
        ])
        #expect(try steps(of: repsLast).filter(\.waits).map(\.phase) == [
            "ready Cobra 1/2", "hold Squat left 2/2", "hold Squat right 2/2",
        ])
        #expect(try steps(of: .dailyStretch).filter(\.waits).count == 13)
    }
}

struct RoutinePhaseTests {
    /// Three phases for Cobra, then three for each side of Pigeon.
    private func phases() throws -> [Phase] {
        try walk(try routine([
            try stretch("Cobra", try hold(30), howTo: "https://example.com/cobra"),
            try stretch("Pigeon", try hold(45), .each),
        ])).map(\.progress.phase)
    }

    @Test func titlesNameTheStretchInEveryStretchPhase() throws {
        #expect(try phases().map(\.title) == Array(repeating: "Cobra", count: 3) + Array(repeating: "Pigeon", count: 6))
    }

    @Test func captionsSayWhereTheStretchIsAndTheCountInSaysGetReady() throws {
        #expect(try phases().map(\.caption) == [
            "Stretch 1 of 2", "Get ready", "Stretch 1 of 2",
            "Left side · Stretch 2 of 2", "Get ready · Left side", "Left side · Stretch 2 of 2",
            "Right side · Stretch 2 of 2", "Get ready · Right side", "Right side · Stretch 2 of 2",
        ])
    }

    @Test func tonesSetTheWaitAndTheCountInApartFromTheHold() throws {
        #expect(try phases().map(\.tone) == [
            .prepare, .prepare, .stretch, .prepare, .prepare, .stretch, .prepare, .prepare, .stretch,
        ])
        #expect(Tone.allCases == [.prepare, .effort, .recover, .stretch, .cool])
    }

    @Test func aWaitEndsOnStartAndTheRestOfAStretchOnNext() throws {
        #expect(try phases().map(\.advanceTitle) == [
            "Start", "Next", "Next", "Start", "Next", "Next", "Start", "Next", "Next",
        ])
        let reps = try progress(session(try routine([try stretch("Squat", try reps(5))])), at: 0).phase
        #expect(reps.advanceTitle == "Next")
    }

    @Test func onlyAWaitForStartCarriesTheLengthOfTheHoldItStarts() throws {
        #expect(try phases().map(\.pendingHold) == [30, nil, nil, 45, nil, nil, 45, nil, nil])
        #expect(try walk(.dailyStretch).first?.progress.phase.pendingHold == nil, "reps wait for Next, not for Start")
        #expect(try progress(session(), at: 0).phase.pendingHold == nil)
    }

    @Test func theHowToLinkShowsInEveryPhaseOfItsStretch() throws {
        let cobra = URL(string: "https://example.com/cobra")
        #expect(try phases().map(\.howTo) == [cobra, cobra, cobra, nil, nil, nil, nil, nil, nil])

        let pigeon = URL(string: "https://youtu.be/lqCqETr7Q0g")
        let daily = try walk(.dailyStretch).map(\.progress.phase).filter { $0.title == "Pigeon" }
        #expect(daily.map(\.howTo) == Array(repeating: pigeon, count: 6))
    }

    @Test func aPoseCarriesItsStretchSideAndPlace() throws {
        let phase = try progress(try session(.dailyStretch, in: "ready Pigeon right 5/10"), at: 2).phase
        guard case .ready(let pose) = phase else {
            Issue.record("expected the wait for Start, got \(phase)")
            return
        }
        #expect(pose.stretch.name == "Pigeon")
        #expect(pose.side == .right)
        #expect(pose.position.number == 5)
        #expect(pose.position.total == 10)
    }

    @Test func onlyAStretchCountedInRepsHasARepCount() throws {
        #expect(try walk(.dailyStretch).map(\.progress.reps?.value) == [10] + Array(repeating: nil, count: 36))
    }
}

struct RoutineCueTests {
    @Test func aRepStretchSoundsItsToneAndItsNameAndThenNothing() throws {
        let plan = try schedule(.dailyStretch)
        #expect(plan.windows.map(bounds) == [[0, 2200]])
        #expect(cues(plan) == [Cue(0, .phaseChange), Cue(500, voice("Cat-Cow"))])
        #expect(plan.end == t0 + 2.2)
        #expect(!plan.isDucked(at: t0 + 30))
        #expect(plan.remaining(after: t0 + 30).isEmpty)
    }

    @Test func aWaitForStartSoundsItsToneAndItsNameAndNothingPastTheGate() throws {
        var run = session(.dailyStretch)
        run.perform(.next, at: t0 + 100)
        let plan = try #require(run.cueSchedule).remaining(after: t0 + 100)
        #expect(plan.windows.map(bounds) == [[100_000, 103_200]])
        #expect(cues(plan) == [Cue(101_000, .phaseChange), Cue(101_500, voice("Child's Pose"))], "Next lands quietly, like a skip")
        #expect(plan.remaining(after: t0 + 104).isEmpty, "nothing counts in until Start")
    }

    @Test func startTicksThroughTheCountInThenSoundsTheHoldAndStopsAtTheNextWait() throws {
        var run = try session(.dailyStretch, in: "ready Child's Pose 2/10")
        run.perform(.play, at: t0 + 100)
        let plan = try #require(run.cueSchedule).remaining(after: t0 + 100)
        #expect(plan.windows.map(bounds) == [[100_000, 103_600], [144_500, 150_200]])
        #expect(cues(plan) == [
            Cue(100_000, .tick), Cue(101_000, .tick), Cue(102_000, .tick),
            Cue(103_000, .phaseChange),
            Cue(145_000, .tick), Cue(146_000, .tick), Cue(147_000, .tick),
            Cue(148_000, .phaseChange), Cue(148_500, voice("Cobra")),
        ])
        #expect(plan.end == t0 + 150.2, "Cobra counts in only after its own Start")
    }

    @Test func aCountInTicksOnEachOfItsSecondsWhateverTheCountdownLength() throws {
        let fiveSecondCountIn = try routine(countIn: 5, [try stretch("Cobra", try hold(20))])
        #expect(cues(try legs(fiveSecondCountIn)[1]) == [
            Cue(0, .tick), Cue(1000, .tick), Cue(2000, .tick), Cue(3000, .tick), Cue(4000, .tick),
            Cue(5000, .phaseChange),
            Cue(22_000, .tick), Cue(23_000, .tick), Cue(24_000, .tick),
            Cue(25_000, .finish), Cue(26_000, voice("Workout complete")),
        ])

        let threeSecondCountIn = try routine([try stretch("Cobra", try hold(20))])
        #expect(cues(try legs(threeSecondCountIn, countdown: .five)[1]) == [
            Cue(0, .tick), Cue(1000, .tick), Cue(2000, .tick),
            Cue(3000, .phaseChange),
            Cue(18_000, .tick), Cue(19_000, .tick), Cue(20_000, .tick), Cue(21_000, .tick), Cue(22_000, .tick),
            Cue(23_000, .finish), Cue(24_000, voice("Workout complete")),
        ])
    }

    @Test func countdownOffSilencesTheCountInToo() throws {
        let workout = try routine([try stretch("Cobra", try hold(20))])
        #expect(cues(try legs(workout, countdown: .off)[1]) == [
            Cue(3000, .phaseChange), Cue(23_000, .finish), Cue(24_000, voice("Workout complete")),
        ])
    }

    @Test func withNoCountInStartSoundsTheHoldAtOnce() throws {
        let workout = try routine(countIn: nil, [try stretch("Cobra", try hold(20))])
        #expect(try legs(workout).map { cues($0) } == [
            [Cue(0, .phaseChange), Cue(500, voice("Cobra"))],
            [
                Cue(0, .phaseChange),
                Cue(17_000, .tick), Cue(18_000, .tick), Cue(19_000, .tick),
                Cue(20_000, .finish), Cue(21_000, voice("Workout complete")),
            ],
        ])
    }

    @Test func aHoldEndsOnTheToneAndTheNameOfTheNextStretch() throws {
        let plans = try legs(.dailyStretch)
        try #require(plans.count == 14, "one leg up to each of the 13 waits, then the last hold and the finish")

        #expect(plans[5].windows.map(bounds) == [[128_500, 132_600], [173_500, 179_200]])
        #expect(cues(plans[5]) == [
            Cue(129_000, .tick), Cue(130_000, .tick), Cue(131_000, .tick),
            Cue(132_000, .phaseChange),
            Cue(174_000, .tick), Cue(175_000, .tick), Cue(176_000, .tick),
            Cue(177_000, .phaseChange), Cue(177_500, voice("Pigeon, left side")),
        ])
    }

    @Test func theOtherSideIsNamedWhenItsWaitBegins() throws {
        let plan = try legs(.dailyStretch)[6]
        #expect(plan.windows.map(bounds) == [[176_500, 180_600], [221_500, 227_200]])
        #expect(cues(plan.windows[1]) == [
            Cue(222_000, .tick), Cue(223_000, .tick), Cue(224_000, .tick),
            Cue(225_000, .phaseChange), Cue(225_500, voice("Pigeon, right side")),
        ])
    }

    @Test func aLongNameKeepsTheMusicLowUntilItHasBeenSpoken() throws {
        let window = try #require(try legs(.dailyStretch)[3].windows.last)
        #expect(bounds(window) == [77_500, 84_200])
        #expect(cues(window) == [
            Cue(78_000, .tick), Cue(79_000, .tick), Cue(80_000, .tick),
            Cue(81_000, .phaseChange), Cue(81_500, voice("Hip Flexor Couch Stretch, left side")),
        ])
    }

    @Test func aHoldEndedEarlyLandsOnTheNextWaitAndNamesItOneSecondLater() throws {
        var run = try session(.dailyStretch, in: "hold Child's Pose 2/10")
        run.perform(.next, at: t0 + 20)
        let plan = try #require(run.cueSchedule).remaining(after: t0 + 20)
        #expect(cues(plan) == [Cue(21_000, .phaseChange), Cue(21_500, voice("Cobra"))], "a wait has no length, and its landing is still announced")
        #expect(plan.isDucked(at: t0 + 20))
    }

    @Test func skipStretchFromAWaitPlaysNoCountInAndNamesTheNextStretch() throws {
        var run = try session(.dailyStretch, in: "ready Child's Pose 2/10")
        run.forward(try progress(run, at: 20).segment, at: t0 + 20)
        let plan = try #require(run.cueSchedule).remaining(after: t0 + 20)
        #expect(plan.windows.map(bounds) == [[20_000, 23_200]])
        #expect(cues(plan) == [Cue(21_000, .phaseChange), Cue(21_500, voice("Cobra"))])
    }

    @Test func startDuringTheSecondCountsInAtOnceAndTheLandingIsNotNamed() throws {
        var run = try session(.dailyStretch, in: "hold Child's Pose 2/10")
        run.perform(.next, at: t0 + 20)
        run.perform(.play, at: t0 + 20.5)
        let plan = try #require(run.cueSchedule).remaining(after: t0 + 20.5)
        #expect(cues(plan).prefix(4) == [Cue(20_500, .tick), Cue(21_500, .tick), Cue(22_500, .tick), Cue(23_500, .phaseChange)])
        #expect(!spoken(plan).contains("Cobra"))
    }

    @Test func theLastTimedHoldEndsOnTheFinish() throws {
        let run = try session(.dailyStretch, in: "hold Passive Dead Hang 10/10")
        let hold = try #require(run.cueSchedule).remaining(after: t0)
        #expect(hold.windows.map(bounds) == [[0, 600], [26_500, 32_700]])
        #expect(cues(hold) == [
            Cue(0, .phaseChange),
            Cue(27_000, .tick), Cue(28_000, .tick), Cue(29_000, .tick),
            Cue(30_000, .finish), Cue(31_000, voice("Workout complete")),
        ])
    }

    @Test func aRepStretchInLastPlaceFinishesWhenNextIsPressed() throws {
        var run = session(try routine([try stretch("Squat", try reps(5))]))
        #expect(cues(try #require(run.cueSchedule)) == [Cue(0, .phaseChange), Cue(500, voice("Squat"))])

        run.perform(.next, at: t0 + 70)
        let finish = try #require(run.cueSchedule).remaining(after: t0 + 70)
        #expect(finish.windows.map(bounds) == [[70_000, 73_700]])
        #expect(cues(finish) == [Cue(71_000, .finish), Cue(72_000, voice("Workout complete"))])
    }

    @Test func dailyStretchSpeaksEveryNameAndEverySideOnce() throws {
        #expect(try legs(.dailyStretch).flatMap(spoken) == [
            "Cat-Cow", "Child's Pose", "Cobra",
            "Hip Flexor Couch Stretch, left side", "Hip Flexor Couch Stretch, right side",
            "Pigeon, left side", "Pigeon, right side",
            "Butterfly", "Standing Hamstring",
            "Doorway Pec",
            "Thread the Needle, left side", "Thread the Needle, right side",
            "Passive Dead Hang", "Workout complete",
        ])
    }

    @Test func theVocabularyCoversTheWholeRunHoweverFarItHasGot() throws {
        let whole: [Sound] = [
            .phaseChange, voice("Cat-Cow"), voice("Child's Pose"), .tick, voice("Cobra"),
            voice("Hip Flexor Couch Stretch, left side"), voice("Hip Flexor Couch Stretch, right side"),
            voice("Pigeon, left side"), voice("Pigeon, right side"),
            voice("Butterfly"), voice("Standing Hamstring"),
            voice("Doorway Pec"),
            voice("Thread the Needle, left side"), voice("Thread the Needle, right side"),
            voice("Passive Dead Hang"),
            .finish, voice("Workout complete"),
        ]
        #expect(session(.dailyStretch).vocabulary == whole)
        #expect(try session(.dailyStretch, in: "hold Pigeon right 5/10").vocabulary == whole)
        #expect(try schedule(.dailyStretch).vocabulary == [.phaseChange, voice("Cat-Cow")])

        #expect(session().vocabulary == (try schedule(headsUp: .thirty).vocabulary))
        #expect(session(.dailyStretch, cues: CuePreferences(countdown: .off, voice: false)).vocabulary == [.phaseChange, .finish])
    }

    @Test func aLongNameIsSpokenInFullWhileTheRunWaits() throws {
        let name = "Standing Quad Stretch and Overhead Reach"
        try #require(name.count == 40)
        let plans = try legs(try routine([try stretch(name, try hold(10), .each)]), countdown: .five)
        #expect(plans.map { $0.windows.map(bounds) } == [
            [[0, 4200]], [[0, 3600], [7500, 17_300]], [[12_500, 16_600], [20_500, 28_700]],
        ])
        #expect(plans.map { cues($0) } == [
            [Cue(0, .phaseChange), Cue(500, voice("\(name), left side"))],
            [
                Cue(0, .tick), Cue(1000, .tick), Cue(2000, .tick),
                Cue(3000, .phaseChange),
                Cue(8000, .tick), Cue(9000, .tick), Cue(10_000, .tick), Cue(11_000, .tick), Cue(12_000, .tick),
                Cue(13_000, .phaseChange), Cue(13_500, voice("\(name), right side")),
            ],
            [
                Cue(13_000, .tick), Cue(14_000, .tick), Cue(15_000, .tick),
                Cue(16_000, .phaseChange),
                Cue(21_000, .tick), Cue(22_000, .tick), Cue(23_000, .tick), Cue(24_000, .tick), Cue(25_000, .tick),
                Cue(26_000, .finish), Cue(27_000, voice("Workout complete")),
            ],
        ])
    }

    @Test func everyNameIsSpokenAndNothingSoundsOverAVoice() throws {
        let amounts = [
            try hold(1), try hold(2), try hold(3), try hold(7), try hold(30),
            try reps(1), try reps(3), try reps(99),
        ]
        for size in 1...amounts.count {
            for sides in Sides.allCases {
                for countIn in [nil, 1, 3] {
                    let stretches = try amounts.prefix(size).enumerated().map { index, amount in
                        let name = "Stretch number \(index)".padding(toLength: 40, withPad: "x", startingAt: 0)
                        return try stretch(name, amount, sides)
                    }
                    let plans = try legs(try routine(countIn: countIn, stretches), countdown: .five)

                    var expected: [String] = []
                    for stretch in stretches {
                        switch sides {
                        case .once: expected.append(stretch.name)
                        case .each: expected += ["\(stretch.name), left side", "\(stretch.name), right side"]
                        }
                    }
                    #expect(plans.flatMap(spoken) == expected + ["Workout complete"])

                    for plan in plans {
                        let sounds = plan.windows.flatMap(\.sounds)
                        for (index, timed) in sounds.enumerated() {
                            guard case .voice = timed.sound else { continue }
                            let end = ms(timed.at + timed.sound.slot)
                            for (otherIndex, other) in sounds.enumerated() where otherIndex != index {
                                #expect(ms(other.at) < ms(timed.at) || ms(other.at) >= end,
                                        "\(other.sound) sounds over \(timed.sound)")
                            }
                        }
                    }
                }
            }
        }
    }
}
