import Foundation
import IntervalCore
import Testing

private struct Row: Equatable, CustomStringConvertible {
    let title: String
    let caption: String?
    let start: Int
    let duration: Int

    init(_ title: String, _ caption: String?, start: Int, duration: Int) {
        self.title = title; self.caption = caption; self.start = start; self.duration = duration
    }

    var description: String { "\(title) (\(caption ?? "no caption")) @\(start) for \(duration)" }
}

private func rows(of workout: Workout) -> [Row] {
    let run = session(workout)
    var rows: [Row] = []
    var offset: TimeInterval = 0
    while case .active(let progress) = run.snapshot(at: t0 + offset), rows.count < 1000 {
        rows.append(Row(progress.phase.title, progress.phase.caption,
                        start: Int(offset), duration: Int(progress.phaseRemaining)))
        offset += progress.phaseRemaining
    }
    return rows
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
        let amount = try reps(10, every: 5)
        let stretch = try #require(Stretch(id: id, name: "Cat-Cow", amount: amount, sides: .each, howTo: nil))
        #expect(stretch.id == id)
        #expect(stretch.amount == amount)
        #expect(stretch.sides == .each)
        #expect(stretch.howTo == nil)
    }

    @Test func anAmountLastsItsHoldOrItsRepsTimesTheirPace() throws {
        #expect(try hold(45).duration == 45)
        #expect(try reps(10, every: 5).duration == 50)
        #expect(try reps(1, every: 30).duration == 30)
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
            try reps(10, every: 5), try hold(45), try hold(30), try hold(45), try hold(45),
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

    @Test func dailyStretchHasTwentyEightSegmentsOverTenMinutesFortyFive() {
        #expect(rows(of: .dailyStretch) == [
            Row("Cat-Cow", "Get ready", start: 0, duration: 8),
            Row("Cat-Cow", "1 of 10", start: 8, duration: 50),
            Row("Child's Pose", "Get ready", start: 58, duration: 8),
            Row("Child's Pose", "2 of 10", start: 66, duration: 45),
            Row("Cobra", "Get ready", start: 111, duration: 8),
            Row("Cobra", "3 of 10", start: 119, duration: 30),
            Row("Hip Flexor Couch Stretch", "Get ready · Left side", start: 149, duration: 8),
            Row("Hip Flexor Couch Stretch", "Left side · 4 of 10", start: 157, duration: 45),
            Row("Hip Flexor Couch Stretch", "Switch sides · Right side next", start: 202, duration: 5),
            Row("Hip Flexor Couch Stretch", "Right side · 4 of 10", start: 207, duration: 45),
            Row("Pigeon", "Get ready · Left side", start: 252, duration: 8),
            Row("Pigeon", "Left side · 5 of 10", start: 260, duration: 45),
            Row("Pigeon", "Switch sides · Right side next", start: 305, duration: 5),
            Row("Pigeon", "Right side · 5 of 10", start: 310, duration: 45),
            Row("Butterfly", "Get ready", start: 355, duration: 8),
            Row("Butterfly", "6 of 10", start: 363, duration: 45),
            Row("Standing Hamstring", "Get ready", start: 408, duration: 8),
            Row("Standing Hamstring", "7 of 10", start: 416, duration: 45),
            Row("Doorway Pec", "Get ready · Left side", start: 461, duration: 8),
            Row("Doorway Pec", "Left side · 8 of 10", start: 469, duration: 30),
            Row("Doorway Pec", "Switch sides · Right side next", start: 499, duration: 5),
            Row("Doorway Pec", "Right side · 8 of 10", start: 504, duration: 30),
            Row("Thread the Needle", "Get ready · Left side", start: 534, duration: 8),
            Row("Thread the Needle", "Left side · 9 of 10", start: 542, duration: 30),
            Row("Thread the Needle", "Switch sides · Right side next", start: 572, duration: 5),
            Row("Thread the Needle", "Right side · 9 of 10", start: 577, duration: 30),
            Row("Passive Dead Hang", "Get ready", start: 607, duration: 8),
            Row("Passive Dead Hang", "10 of 10", start: 615, duration: 30),
        ])
        #expect(Workout.dailyStretch.totalDuration == 645)
        #expect(Workout.dailyStretch.outline.count == 28)
        #expect(session(.dailyStretch).snapshot(at: t0 + 645) == .finished(worked: 645))
    }

    @Test func aStretchDoneOnceIsAGapThenAHold() throws {
        #expect(steps(of: try routine(getReady: 6, [try stretch("Cobra", try hold(30))])) == [
            Step("getReady Cobra 1/1", start: 0, duration: 6),
            Step("hold Cobra 1/1", start: 6, duration: 30),
        ])
    }

    @Test func anEachSideStretchSwitchesSidesBetweenTwoHolds() throws {
        #expect(steps(of: try routine(getReady: 6, switchSides: 4, [try stretch("Pigeon", try hold(45), .each)])) == [
            Step("getReady Pigeon left 1/1", start: 0, duration: 6),
            Step("hold Pigeon left 1/1", start: 6, duration: 45),
            Step("switchSides to Pigeon right 1/1", start: 51, duration: 4),
            Step("hold Pigeon right 1/1", start: 55, duration: 45),
        ])
    }

    @Test func repsAreDoneOnEachSideToo() throws {
        let workout = try routine(getReady: 5, switchSides: 3, [
            try stretch("Leg Swings", try reps(6, every: 2), .each),
            try stretch("Cobra", try hold(20)),
        ])
        #expect(steps(of: workout) == [
            Step("getReady Leg Swings left 1/2", start: 0, duration: 5),
            Step("hold Leg Swings left 1/2", start: 5, duration: 12),
            Step("switchSides to Leg Swings right 1/2", start: 17, duration: 3),
            Step("hold Leg Swings right 1/2", start: 20, duration: 12),
            Step("getReady Cobra 2/2", start: 32, duration: 5),
            Step("hold Cobra 2/2", start: 37, duration: 20),
        ])
        #expect(workout.totalDuration == 57)
        #expect(workout.outline.map(\.duration) == [5, 12, 3, 12, 5, 20])
    }
}

struct RoutinePhaseTests {
    private func workout() throws -> Workout {
        try routine(getReady: 10, switchSides: 5, [
            try stretch("Cobra", try hold(30), howTo: "https://example.com/cobra"),
            try stretch("Pigeon", try hold(45), .each),
        ])
    }

    @Test func titlesNameTheStretchInEveryStretchPhase() throws {
        let run = session(try workout())
        #expect(try [0, 10, 40, 50, 95, 100].map { try progress(run, at: $0).phase.title } == [
            "Cobra", "Cobra", "Pigeon", "Pigeon", "Pigeon", "Pigeon",
        ])
    }

    @Test func captionsSayWhatToDoAndWhere() throws {
        let run = session(try workout())
        #expect(try [0, 10, 40, 50, 95, 100].map { try progress(run, at: $0).phase.caption } == [
            "Get ready", "1 of 2", "Get ready · Left side", "Left side · 2 of 2",
            "Switch sides · Right side next", "Right side · 2 of 2",
        ])
    }

    @Test func tonesSetGapsApartFromHolds() throws {
        let run = session(try workout())
        #expect(try [0, 10, 40, 50, 95, 100].map { try progress(run, at: $0).phase.tone } == [
            .prepare, .stretch, .prepare, .stretch, .recover, .stretch,
        ])
        #expect(Tone.allCases == [.prepare, .effort, .recover, .stretch, .cool])
    }

    @Test func theHowToLinkShowsInTheGapsAndTheHolds() throws {
        let run = session(try workout())
        let cobra = URL(string: "https://example.com/cobra")
        #expect(try [0, 10, 40, 50, 95, 100].map { try progress(run, at: $0).phase.howTo } == [
            cobra, cobra, nil, nil, nil, nil,
        ])

        let pigeon = URL(string: "https://youtu.be/lqCqETr7Q0g")
        let daily = session(.dailyStretch)
        #expect(try [255, 280, 307, 320].map { try progress(daily, at: $0).phase.howTo } == [
            pigeon, pigeon, pigeon, pigeon,
        ])
    }

    @Test func aPoseCarriesItsStretchSideAndPlace() throws {
        let phase = try progress(session(.dailyStretch), at: 307).phase
        guard case .switchSides(let pose) = phase else {
            Issue.record("expected switch sides, got \(phase)")
            return
        }
        #expect(pose.stretch.name == "Pigeon")
        #expect(pose.side == .right)
        #expect(pose.position.number == 5)
        #expect(pose.position.total == 10)
    }
}

struct RoutineCueTests {
    @Test func theStartNamesTheFirstStretch() throws {
        let first = try #require(try schedule(.dailyStretch).windows.first)
        #expect(bounds(first) == [0, 2200])
        #expect(cues(first) == [Cue(0, .phaseChange), Cue(500, voice("Cat-Cow"))])
    }

    @Test func aHoldCountsDownIntoTheNextStretchesNameThenIntoItsHold() throws {
        let plan = try schedule(.dailyStretch)
        let index = try #require(plan.windows.firstIndex { ms($0.start) == 248_500 })

        let endOfHipFlexor = plan.windows[index]
        #expect(bounds(endOfHipFlexor) == [248_500, 254_200])
        #expect(cues(endOfHipFlexor) == [
            Cue(249_000, .tick), Cue(250_000, .tick), Cue(251_000, .tick),
            Cue(252_000, .phaseChange), Cue(252_500, voice("Pigeon, left side")),
        ])

        let startOfTheHold = plan.windows[index + 1]
        #expect(bounds(startOfTheHold) == [256_500, 260_600])
        #expect(cues(startOfTheHold) == [
            Cue(257_000, .tick), Cue(258_000, .tick), Cue(259_000, .tick),
            Cue(260_000, .phaseChange),
        ])
    }

    @Test func switchingSidesIsOneWindowFromTheLastTicksToTheSecondHold() throws {
        let plan = try schedule(.dailyStretch)
        let window = try #require(plan.windows.first { ms($0.start) == 301_500 })
        #expect(bounds(window) == [301_500, 310_600])
        #expect(cues(window) == [
            Cue(302_000, .tick), Cue(303_000, .tick), Cue(304_000, .tick),
            Cue(305_000, .phaseChange), Cue(305_500, voice("Switch sides")),
            Cue(307_000, .tick), Cue(308_000, .tick), Cue(309_000, .tick),
            Cue(310_000, .phaseChange),
        ])
    }

    @Test func aLongNameKeepsTheMusicLowUntilTheHoldStarts() throws {
        let plan = try schedule(.dailyStretch)
        let window = try #require(plan.windows.first { ms($0.start) == 145_500 })
        #expect(bounds(window) == [145_500, 157_600])
        #expect(cues(window) == [
            Cue(146_000, .tick), Cue(147_000, .tick), Cue(148_000, .tick),
            Cue(149_000, .phaseChange), Cue(149_500, voice("Hip Flexor Couch Stretch, left side")),
            Cue(154_000, .tick), Cue(155_000, .tick), Cue(156_000, .tick),
            Cue(157_000, .phaseChange),
        ])
    }

    @Test func aRepHoldGetsABeatPerRepAndNoCountdownInOneWindow() throws {
        let plan = try schedule(.dailyStretch)
        let window = plan.windows[1]
        #expect(bounds(window) == [4500, 60_200])
        #expect(cues(window) == [
            Cue(5000, .tick), Cue(6000, .tick), Cue(7000, .tick),
            Cue(8000, .phaseChange),
            Cue(13_000, .beat), Cue(18_000, .beat), Cue(23_000, .beat), Cue(28_000, .beat), Cue(33_000, .beat),
            Cue(38_000, .beat), Cue(43_000, .beat), Cue(48_000, .beat), Cue(53_000, .beat),
            Cue(58_000, .phaseChange), Cue(58_500, voice("Child's Pose")),
        ])
        #expect(bounds(plan.windows[2]) == [62_500, 66_600])
        #expect(cues(plan).filter { $0.sound == .beat }.count == 9)

        #expect(!plan.isDucked(at: t0 + 3))
        #expect(plan.isDucked(at: t0 + 30))
        #expect(!plan.isDucked(at: t0 + 61))
    }

    @Test func aRepHoldStaysLowWithoutVoiceOrCountdown() throws {
        let quiet = try schedule(.dailyStretch, voice: false)
        #expect(bounds(quiet.windows[0]) == [0, 600])
        #expect(bounds(quiet.windows[1]) == [4500, 58_600])

        let uncounted = try schedule(.dailyStretch, countdown: .off)
        #expect(bounds(uncounted.windows[0]) == [0, 2200])
        #expect(bounds(uncounted.windows[1]) == [7500, 60_200])
        #expect(cues(uncounted.windows[1]).map(\.sound) == [.phaseChange] + Array(repeating: .beat, count: 9)
            + [.phaseChange, voice("Child's Pose")])
    }

    @Test func aSingleRepHoldHasNoBeatsAndNoCountdown() throws {
        let plan = try schedule(try routine([try stretch("Squat", try reps(1, every: 30))]))
        #expect(plan.windows.map(bounds) == [[0, 2200], [6500, 42_700]])
        #expect(cues(plan) == [
            Cue(0, .phaseChange), Cue(500, voice("Squat")),
            Cue(7000, .tick), Cue(8000, .tick), Cue(9000, .tick),
            Cue(10_000, .phaseChange),
            Cue(40_000, .finish), Cue(41_000, voice("Workout complete")),
        ])
    }

    @Test func theLastHoldEndsOnTheFinish() throws {
        let plan = try schedule(.dailyStretch)
        let last = try #require(plan.windows.last)
        #expect(bounds(last) == [641_500, 647_700])
        #expect(cues(last) == [
            Cue(642_000, .tick), Cue(643_000, .tick), Cue(644_000, .tick),
            Cue(645_000, .finish), Cue(646_000, voice("Workout complete")),
        ])
    }

    @Test func dailyStretchSpeaksEveryNameOnceAndEverySwitch() throws {
        #expect(spoken(try schedule(.dailyStretch)) == [
            "Cat-Cow", "Child's Pose", "Cobra",
            "Hip Flexor Couch Stretch, left side", "Switch sides",
            "Pigeon, left side", "Switch sides",
            "Butterfly", "Standing Hamstring",
            "Doorway Pec, left side", "Switch sides",
            "Thread the Needle, left side", "Switch sides",
            "Passive Dead Hang", "Workout complete",
        ])
    }

    @Test func vocabularyFollowsTheOrderOfFirstUse() throws {
        #expect(try schedule(.dailyStretch).vocabulary == [
            .phaseChange, voice("Cat-Cow"), .tick, .beat, voice("Child's Pose"), voice("Cobra"),
            voice("Hip Flexor Couch Stretch, left side"), voice("Switch sides"), voice("Pigeon, left side"),
            voice("Butterfly"), voice("Standing Hamstring"), voice("Doorway Pec, left side"),
            voice("Thread the Needle, left side"), voice("Passive Dead Hang"),
            .finish, voice("Workout complete"),
        ])
    }

    @Test func aTickNeverTalksOverALongName() throws {
        let name = "Standing Quad Stretch and Overhead Reach"
        try #require(name.count == 40)
        let workout = try routine(getReady: 5, switchSides: 3, [try stretch(name, try hold(10), .each)])
        let plan = try schedule(workout, countdown: .five)
        #expect(plan.windows.map(bounds) == [[0, 5600], [9500, 18_600], [22_500, 30_700]])
        #expect(cues(plan) == [
            Cue(0, .phaseChange), Cue(500, voice("\(name), left side")),
            Cue(4000, .tick),
            Cue(5000, .phaseChange),
            Cue(10_000, .tick), Cue(11_000, .tick), Cue(12_000, .tick), Cue(13_000, .tick), Cue(14_000, .tick),
            Cue(15_000, .phaseChange), Cue(15_500, voice("Switch sides")),
            Cue(17_000, .tick),
            Cue(18_000, .phaseChange),
            Cue(23_000, .tick), Cue(24_000, .tick), Cue(25_000, .tick), Cue(26_000, .tick), Cue(27_000, .tick),
            Cue(28_000, .finish), Cue(29_000, voice("Workout complete")),
        ])
    }

    @Test func everyNameIsSpokenAndNothingSoundsOverAVoice() throws {
        let amounts = [
            try hold(1), try hold(2), try hold(3), try hold(7), try hold(30),
            try reps(1, every: 1), try reps(3, every: 1), try reps(2, every: 4), try reps(99, every: 2),
        ]
        for size in 1...amounts.count {
            for sides in Sides.allCases {
                let stretches = try amounts.prefix(size).enumerated().map { index, amount in
                    let name = "Stretch number \(index)".padding(toLength: 40, withPad: "x", startingAt: 0)
                    return try stretch(name, amount, sides)
                }
                let plan = try schedule(try routine(getReady: 5, switchSides: 3, stretches), countdown: .five)

                var expected: [String] = []
                for stretch in stretches {
                    switch sides {
                    case .once: expected.append(stretch.name)
                    case .each: expected += ["\(stretch.name), left side", "Switch sides"]
                    }
                }
                #expect(spoken(plan) == expected + ["Workout complete"])

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
