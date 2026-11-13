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
    private func routine(getReady: Int = 10, switchSides: Int = 5, stretches: Int = 1) throws -> Routine? {
        Routine(getReady: try span(getReady), switchSides: try span(switchSides),
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

    @Test func theGetReadyGapIsAtLeastFiveSeconds() throws {
        #expect(try routine(getReady: 4) == nil)
        #expect(try routine(getReady: 5)?.getReady.seconds == 5)
        #expect(Routine.minimumGetReady == 5)
    }

    @Test func theSwitchSidesGapIsAtLeastThreeSeconds() throws {
        #expect(try routine(switchSides: 2) == nil)
        #expect(try routine(switchSides: 3)?.switchSides.seconds == 3)
        #expect(Routine.minimumSwitchSides == 3)
    }

    @Test func keepsItsStretchesInOrder() throws {
        let stretches = [try stretch("Cobra", try hold(30)), try stretch("Pigeon", try hold(45), .each)]
        let routine = try #require(Routine(getReady: try span(8), switchSides: try span(5), stretches: stretches))
        #expect(routine.stretches == stretches)
    }
}

struct RoutineTimelineTests {
    @Test func dailyStretchIsJuliansTenStretches() throws {
        guard case .routine(let routine) = Workout.dailyStretch.plan else {
            Issue.record("Daily Stretch is not a routine")
            return
        }
        #expect(routine.getReady.seconds == 8)
        #expect(routine.switchSides.seconds == 5)
        #expect(routine.stretches.map(\.name) == [
            "Cat-Cow", "Child's Pose", "Cobra", "Hip Flexor Couch Stretch", "Pigeon",
            "Butterfly", "Standing Hamstring", "Doorway Pec", "Thread the Needle", "Passive Dead Hang",
        ])
        #expect(routine.stretches.map(\.amount) == [
            try reps(10), try hold(45), try hold(30), try hold(45), try hold(45),
            try hold(45), try hold(45), try hold(30), try hold(30), try hold(30),
        ])
        #expect(routine.stretches.map(\.sides) == [
            .once, .once, .once, .each, .each, .once, .once, .each, .each, .once,
        ])
        #expect(routine.stretches.map(\.howTo?.absoluteString) == [
            "https://youtu.be/1Y0YjXS9sKI", "https://youtu.be/_ZX_zTOBgp8", "https://youtu.be/Aqyvevt4EUU",
            "https://youtu.be/m2u7jOCMyBg", "https://youtu.be/lqCqETr7Q0g", "https://youtu.be/MHwUChXNy-Y",
            "https://youtu.be/goN4rWbQUn4", "https://youtu.be/M850sCj9LHQ", "https://youtu.be/SkQhKf74nZk",
            "https://youtu.be/3CEmHJXbNpc",
        ])
        #expect(Set(routine.stretches.map(\.id)).count == 10)
    }

    @Test func dailyStretchHasNineMinutesFiftyFiveOfTimedLengthAndWaitsAfterEveryStretch() throws {
        #expect(try rows(of: .dailyStretch) == [
            Row("Cat-Cow", "Get ready", start: 0, duration: 8),
            Row("Cat-Cow", "Stretch 1 of 10", start: 8, duration: 0, waits: true),
            Row("Child's Pose", "Get ready", start: 8, duration: 8),
            Row("Child's Pose", "Stretch 2 of 10", start: 16, duration: 45, waits: true),
            Row("Cobra", "Get ready", start: 61, duration: 8),
            Row("Cobra", "Stretch 3 of 10", start: 69, duration: 30, waits: true),
            Row("Hip Flexor Couch Stretch", "Get ready · Left side", start: 99, duration: 8),
            Row("Hip Flexor Couch Stretch", "Left side · Stretch 4 of 10", start: 107, duration: 45, waits: true),
            Row("Hip Flexor Couch Stretch", "Switch sides · Right side next", start: 152, duration: 5),
            Row("Hip Flexor Couch Stretch", "Right side · Stretch 4 of 10", start: 157, duration: 45, waits: true),
            Row("Pigeon", "Get ready · Left side", start: 202, duration: 8),
            Row("Pigeon", "Left side · Stretch 5 of 10", start: 210, duration: 45, waits: true),
            Row("Pigeon", "Switch sides · Right side next", start: 255, duration: 5),
            Row("Pigeon", "Right side · Stretch 5 of 10", start: 260, duration: 45, waits: true),
            Row("Butterfly", "Get ready", start: 305, duration: 8),
            Row("Butterfly", "Stretch 6 of 10", start: 313, duration: 45, waits: true),
            Row("Standing Hamstring", "Get ready", start: 358, duration: 8),
            Row("Standing Hamstring", "Stretch 7 of 10", start: 366, duration: 45, waits: true),
            Row("Doorway Pec", "Get ready · Left side", start: 411, duration: 8),
            Row("Doorway Pec", "Left side · Stretch 8 of 10", start: 419, duration: 30, waits: true),
            Row("Doorway Pec", "Switch sides · Right side next", start: 449, duration: 5),
            Row("Doorway Pec", "Right side · Stretch 8 of 10", start: 454, duration: 30, waits: true),
            Row("Thread the Needle", "Get ready · Left side", start: 484, duration: 8),
            Row("Thread the Needle", "Left side · Stretch 9 of 10", start: 492, duration: 30, waits: true),
            Row("Thread the Needle", "Switch sides · Right side next", start: 522, duration: 5),
            Row("Thread the Needle", "Right side · Stretch 9 of 10", start: 527, duration: 30, waits: true),
            Row("Passive Dead Hang", "Get ready", start: 557, duration: 8),
            Row("Passive Dead Hang", "Stretch 10 of 10", start: 565, duration: 30, waits: true),
        ])
        #expect(Workout.dailyStretch.totalDuration == 595)
        #expect(Workout.dailyStretch.outline.count == 28)
        #expect(Workout.dailyStretch.outline.map(\.duration).reduce(0, +) == 595)
    }

    @Test func aStretchDoneOnceIsAGapThenAHold() throws {
        #expect(try steps(of: try routine(getReady: 6, [try stretch("Cobra", try hold(30))])) == [
            Step("getReady Cobra 1/1", start: 0, duration: 6),
            Step("hold Cobra 1/1", start: 6, duration: 30, waits: true),
        ])
    }

    @Test func anEachSideStretchSwitchesSidesBetweenTwoHoldsAndWaitsAfterEach() throws {
        #expect(try steps(of: try routine(getReady: 6, switchSides: 4, [try stretch("Pigeon", try hold(45), .each)])) == [
            Step("getReady Pigeon left 1/1", start: 0, duration: 6),
            Step("hold Pigeon left 1/1", start: 6, duration: 45, waits: true),
            Step("switchSides to Pigeon right 1/1", start: 51, duration: 4),
            Step("hold Pigeon right 1/1", start: 55, duration: 45, waits: true),
        ])
    }

    @Test func repsAreDoneOnEachSideTooAndAddNoLength() throws {
        let workout = try routine(getReady: 5, switchSides: 3, [
            try stretch("Leg Swings", try reps(6), .each),
            try stretch("Cobra", try hold(20)),
        ])
        #expect(try steps(of: workout) == [
            Step("getReady Leg Swings left 1/2", start: 0, duration: 5),
            Step("hold Leg Swings left 1/2", start: 5, duration: 0, waits: true),
            Step("switchSides to Leg Swings right 1/2", start: 5, duration: 3),
            Step("hold Leg Swings right 1/2", start: 8, duration: 0, waits: true),
            Step("getReady Cobra 2/2", start: 8, duration: 5),
            Step("hold Cobra 2/2", start: 13, duration: 20, waits: true),
        ])
        #expect(workout.totalDuration == 33)
        #expect(workout.outline.map(\.duration) == [5, 0, 3, 0, 5, 20])
        #expect(workout.outline.map(\.phase.reps?.value) == [nil, 6, nil, 6, nil, nil])
    }

    @Test func everyHoldWaitsAndNoGapDoes() throws {
        let timedLast = try routine(getReady: 5, switchSides: 3, [
            try stretch("Cobra", try hold(20)),
            try stretch("Squat", try reps(8)),
            try stretch("Pigeon", try hold(30), .each),
        ])
        let repsLast = try routine(getReady: 5, switchSides: 3, [
            try stretch("Cobra", try hold(20)),
            try stretch("Squat", try reps(8), .each),
        ])
        let timedOnly = try routine([try stretch("Cobra", try hold(20))])
        for workout in [timedLast, repsLast, timedOnly, .dailyStretch] {
            for step in try steps(of: workout) {
                #expect(step.waits == step.phase.hasPrefix("hold"), "\(step)")
            }
        }
        #expect(try steps(of: timedLast).filter(\.waits).count == 4)
        #expect(try steps(of: .dailyStretch).filter(\.waits).count == 14)
    }
}

struct RoutinePhaseTests {
    private func phases() throws -> [Phase] {
        try walk(try routine(getReady: 10, switchSides: 5, [
            try stretch("Cobra", try hold(30), howTo: "https://example.com/cobra"),
            try stretch("Pigeon", try hold(45), .each),
        ])).map(\.progress.phase)
    }

    @Test func titlesNameTheStretchInEveryStretchPhase() throws {
        #expect(try phases().map(\.title) == ["Cobra", "Cobra", "Pigeon", "Pigeon", "Pigeon", "Pigeon"])
    }

    @Test func captionsSayWhatToDoAndWhere() throws {
        #expect(try phases().map(\.caption) == [
            "Get ready", "Stretch 1 of 2", "Get ready · Left side", "Left side · Stretch 2 of 2",
            "Switch sides · Right side next", "Right side · Stretch 2 of 2",
        ])
    }

    @Test func tonesSetGapsApartFromHolds() throws {
        #expect(try phases().map(\.tone) == [.prepare, .stretch, .prepare, .stretch, .recover, .stretch])
        #expect(Tone.allCases == [.prepare, .effort, .recover, .stretch, .cool])
    }

    @Test func nextIsWhatEndingAStretchPhaseIsCalled() throws {
        #expect(try phases().map(\.advanceTitle) == ["Next", "Next", "Next", "Next", "Next", "Next"])
    }

    @Test func theHowToLinkShowsInTheGapsAndTheHolds() throws {
        let cobra = URL(string: "https://example.com/cobra")
        #expect(try phases().map(\.howTo) == [cobra, cobra, nil, nil, nil, nil])

        let pigeon = URL(string: "https://youtu.be/lqCqETr7Q0g")
        let daily = try walk(.dailyStretch).map(\.progress.phase).filter { $0.title == "Pigeon" }
        #expect(daily.map(\.howTo) == [pigeon, pigeon, pigeon, pigeon])
    }

    @Test func aPoseCarriesItsStretchSideAndPlace() throws {
        let phase = try progress(try session(.dailyStretch, in: "switchSides to Pigeon right 5/10"), at: 2).phase
        guard case .switchSides(let pose) = phase else {
            Issue.record("expected switch sides, got \(phase)")
            return
        }
        #expect(pose.stretch.name == "Pigeon")
        #expect(pose.side == .right)
        #expect(pose.position.number == 5)
        #expect(pose.position.total == 10)
    }

    @Test func onlyAStretchCountedInRepsHasARepCount() throws {
        #expect(try walk(.dailyStretch).map(\.progress.reps?.value) == [nil, 10] + Array(repeating: nil, count: 26))
    }
}

struct RoutineCueTests {
    @Test func theStartNamesTheFirstStretch() throws {
        let first = try #require(try schedule(.dailyStretch).windows.first)
        #expect(bounds(first) == [0, 2200])
        #expect(cues(first) == [Cue(0, .phaseChange), Cue(500, voice("Cat-Cow"))])
    }

    @Test func aRepStretchSoundsItsStartToneAndThenNothing() throws {
        let plan = try schedule(.dailyStretch)
        #expect(plan.windows.map(bounds) == [[0, 2200], [4500, 8600]])
        #expect(cues(plan) == [
            Cue(0, .phaseChange), Cue(500, voice("Cat-Cow")),
            Cue(5000, .tick), Cue(6000, .tick), Cue(7000, .tick),
            Cue(8000, .phaseChange),
        ])
        #expect(plan.end == t0 + 8.6)
        #expect(!plan.isDucked(at: t0 + 30))
        #expect(plan.remaining(after: t0 + 30).isEmpty)
    }

    @Test func nothingIsScheduledPastAHoldTheRunWillWaitAt() throws {
        let run = try session(.dailyStretch, in: "getReady Child's Pose 2/10")
        let plan = try #require(run.cueSchedule)
        #expect(plan.windows.map(bounds) == [[-500, 2200], [4500, 8600], [49_500, 53_600]])
        #expect(cues(plan) == [
            Cue(0, .phaseChange), Cue(500, voice("Child's Pose")),
            Cue(5000, .tick), Cue(6000, .tick), Cue(7000, .tick),
            Cue(8000, .phaseChange),
            Cue(50_000, .tick), Cue(51_000, .tick), Cue(52_000, .tick),
            Cue(53_000, .phaseChange),
        ])
    }

    @Test func nextSchedulesTheNextStretchFromThePress() throws {
        var run = session(.dailyStretch)
        run.perform(.next, at: t0 + 100)
        let plan = try #require(run.cueSchedule).remaining(after: t0 + 100)
        #expect(cues(plan) == [
            Cue(100_000, .phaseChange), Cue(100_500, voice("Child's Pose")),
            Cue(105_000, .tick), Cue(106_000, .tick), Cue(107_000, .tick),
            Cue(108_000, .phaseChange),
            Cue(150_000, .tick), Cue(151_000, .tick), Cue(152_000, .tick),
            Cue(153_000, .phaseChange),
        ])
    }

    @Test func aHoldEndsOnAToneAndTheNextNameWaitsForNext() throws {
        let plans = try legs(.dailyStretch)
        try #require(plans.count == 15, "one leg up to each of the 14 holds, then the finish")

        let rightSideOfHipFlexor = try #require(plans[4].windows.last)
        #expect(bounds(rightSideOfHipFlexor) == [198_500, 202_600])
        #expect(cues(rightSideOfHipFlexor) == [
            Cue(199_000, .tick), Cue(200_000, .tick), Cue(201_000, .tick),
            Cue(202_000, .phaseChange),
        ])

        #expect(plans[5].windows.map(bounds) == [[201_500, 204_200], [206_500, 210_600], [251_500, 255_600]])
        #expect(cues(plans[5]) == [
            Cue(202_000, .phaseChange), Cue(202_500, voice("Pigeon, left side")),
            Cue(207_000, .tick), Cue(208_000, .tick), Cue(209_000, .tick),
            Cue(210_000, .phaseChange),
            Cue(252_000, .tick), Cue(253_000, .tick), Cue(254_000, .tick),
            Cue(255_000, .phaseChange),
        ])
    }

    @Test func switchingSidesIsOneWindowFromNextToTheSecondHold() throws {
        let plan = try legs(.dailyStretch)[6]
        #expect(plan.windows.map(bounds) == [[254_500, 260_600], [301_500, 305_600]])
        #expect(cues(plan.windows[0]) == [
            Cue(255_000, .phaseChange), Cue(255_500, voice("Switch sides")),
            Cue(257_000, .tick), Cue(258_000, .tick), Cue(259_000, .tick),
            Cue(260_000, .phaseChange),
        ])
    }

    @Test func aLongNameKeepsTheMusicLowUntilTheHoldStarts() throws {
        let window = try #require(try legs(.dailyStretch)[3].windows.first)
        #expect(bounds(window) == [98_500, 107_600])
        #expect(cues(window) == [
            Cue(99_000, .phaseChange), Cue(99_500, voice("Hip Flexor Couch Stretch, left side")),
            Cue(104_000, .tick), Cue(105_000, .tick), Cue(106_000, .tick),
            Cue(107_000, .phaseChange),
        ])
    }

    @Test func aSkippedHoldDoesNotSoundItsEndTone() throws {
        var run = try session(.dailyStretch, in: "hold Child's Pose 2/10")
        run.perform(.next, at: t0 + 20)
        let plan = try #require(run.cueSchedule).remaining(after: t0 + 20)
        #expect(cues(plan).prefix(3) == [
            Cue(20_000, .phaseChange), Cue(20_500, voice("Cobra")), Cue(25_000, .tick),
        ])
    }

    @Test func theLastTimedHoldEndsOnAToneAndTheFinishSoundsWhenNextIsPressed() throws {
        var run = try session(.dailyStretch, in: "hold Passive Dead Hang 10/10")
        let hold = try #require(run.cueSchedule).remaining(after: t0)
        #expect(hold.windows.map(bounds) == [[0, 600], [26_500, 30_600]])
        #expect(cues(hold) == [
            Cue(0, .phaseChange),
            Cue(27_000, .tick), Cue(28_000, .tick), Cue(29_000, .tick),
            Cue(30_000, .phaseChange),
        ])
        #expect(hold.remaining(after: t0 + 31).isEmpty, "nothing sounds while the last hold waits")

        run.perform(.next, at: t0 + 75)
        let finish = try #require(run.cueSchedule)
        #expect(finish.windows.map(bounds) == [[74_500, 77_700]])
        #expect(cues(finish) == [Cue(75_000, .finish), Cue(76_000, voice("Workout complete"))])
    }

    @Test func theRightSideInLastPlaceEndsOnAToneAndTheFinishSoundsWhenNextIsPressed() throws {
        let workout = try routine(getReady: 6, switchSides: 4, [try stretch("Pigeon", try hold(20), .each)])
        var run = try session(workout, in: "hold Pigeon right 1/1")
        #expect(cues(try #require(run.cueSchedule).remaining(after: t0)) == [
            Cue(0, .phaseChange),
            Cue(17_000, .tick), Cue(18_000, .tick), Cue(19_000, .tick),
            Cue(20_000, .phaseChange),
        ])

        run.perform(.next, at: t0 + 40)
        #expect(cues(try #require(run.cueSchedule)) == [Cue(40_000, .finish), Cue(41_000, voice("Workout complete"))])
    }

    @Test func aRepStretchInLastPlaceFinishesWhenNextIsPressed() throws {
        var run = session(try routine([try stretch("Squat", try reps(5))]))
        #expect(cues(try #require(run.cueSchedule)) == [
            Cue(0, .phaseChange), Cue(500, voice("Squat")),
            Cue(7000, .tick), Cue(8000, .tick), Cue(9000, .tick),
            Cue(10_000, .phaseChange),
        ])

        run.perform(.next, at: t0 + 70)
        let finish = try #require(run.cueSchedule)
        #expect(finish.windows.map(bounds) == [[69_500, 72_700]])
        #expect(cues(finish) == [Cue(70_000, .finish), Cue(71_000, voice("Workout complete"))])
    }

    @Test func dailyStretchSpeaksEveryNameOnceAndEverySwitch() throws {
        #expect(try legs(.dailyStretch).flatMap(spoken) == [
            "Cat-Cow", "Child's Pose", "Cobra",
            "Hip Flexor Couch Stretch, left side", "Switch sides",
            "Pigeon, left side", "Switch sides",
            "Butterfly", "Standing Hamstring",
            "Doorway Pec, left side", "Switch sides",
            "Thread the Needle, left side", "Switch sides",
            "Passive Dead Hang", "Workout complete",
        ])
    }

    @Test func theVocabularyCoversTheWholeRunHoweverFarItHasGot() throws {
        let whole: [Sound] = [
            .phaseChange, voice("Cat-Cow"), .tick, voice("Child's Pose"), voice("Cobra"),
            voice("Hip Flexor Couch Stretch, left side"), voice("Switch sides"), voice("Pigeon, left side"),
            voice("Butterfly"), voice("Standing Hamstring"), voice("Doorway Pec, left side"),
            voice("Thread the Needle, left side"), voice("Passive Dead Hang"),
            .finish, voice("Workout complete"),
        ]
        #expect(session(.dailyStretch).vocabulary == whole)
        #expect(try session(.dailyStretch, in: "hold Pigeon right 5/10").vocabulary == whole)
        #expect(try schedule(.dailyStretch).vocabulary == [.phaseChange, voice("Cat-Cow"), .tick])

        #expect(session().vocabulary == (try schedule().vocabulary))
        #expect(session(.dailyStretch, cues: CuePreferences(countdown: .off, voice: false)).vocabulary == [.phaseChange, .finish])
    }

    @Test func aTickNeverTalksOverALongName() throws {
        let name = "Standing Quad Stretch and Overhead Reach"
        try #require(name.count == 40)
        let workout = try routine(getReady: 5, switchSides: 3, [try stretch(name, try hold(10), .each)])
        let plans = try legs(workout, countdown: .five)
        #expect(plans.map { $0.windows.map(bounds) } == [
            [[0, 5600], [9500, 15_600]], [[14_500, 18_600], [22_500, 28_600]], [[27_500, 30_700]],
        ])
        #expect(plans.map { cues($0) } == [
            [
                Cue(0, .phaseChange), Cue(500, voice("\(name), left side")),
                Cue(4000, .tick),
                Cue(5000, .phaseChange),
                Cue(10_000, .tick), Cue(11_000, .tick), Cue(12_000, .tick), Cue(13_000, .tick), Cue(14_000, .tick),
                Cue(15_000, .phaseChange),
            ],
            [
                Cue(15_000, .phaseChange), Cue(15_500, voice("Switch sides")),
                Cue(17_000, .tick),
                Cue(18_000, .phaseChange),
                Cue(23_000, .tick), Cue(24_000, .tick), Cue(25_000, .tick), Cue(26_000, .tick), Cue(27_000, .tick),
                Cue(28_000, .phaseChange),
            ],
            [Cue(28_000, .finish), Cue(29_000, voice("Workout complete"))],
        ])
    }

    @Test func everyNameIsSpokenAndNothingSoundsOverAVoice() throws {
        let amounts = [
            try hold(1), try hold(2), try hold(3), try hold(7), try hold(30),
            try reps(1), try reps(3), try reps(99),
        ]
        for size in 1...amounts.count {
            for sides in Sides.allCases {
                let stretches = try amounts.prefix(size).enumerated().map { index, amount in
                    let name = "Stretch number \(index)".padding(toLength: 40, withPad: "x", startingAt: 0)
                    return try stretch(name, amount, sides)
                }
                let plans = try legs(try routine(getReady: 5, switchSides: 3, stretches), countdown: .five)

                var expected: [String] = []
                for stretch in stretches {
                    switch sides {
                    case .once: expected.append(stretch.name)
                    case .each: expected += ["\(stretch.name), left side", "Switch sides"]
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
