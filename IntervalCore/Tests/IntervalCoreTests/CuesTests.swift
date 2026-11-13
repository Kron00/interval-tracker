import Foundation
import IntervalCore
import Testing

struct CueScheduleTests {
    @Test func startBurstOfNorwegian4x4() throws {
        let first = try #require(try schedule().windows.first)
        #expect(bounds(first) == [0, 2200])
        #expect(cues(first) == [Cue(0, .phaseChange), Cue(500, voice("Warm up"))])
    }

    @Test func firstBoundaryOfNorwegian4x4() throws {
        let window = try schedule().windows[1]
        #expect(bounds(window) == [296_500, 302_200])
        #expect(cues(window) == [
            Cue(297_000, .tick), Cue(298_000, .tick), Cue(299_000, .tick),
            Cue(300_000, .phaseChange), Cue(300_500, voice("Round one")),
        ])
    }

    @Test func finishOfNorwegian4x4() throws {
        let plan = try schedule()
        let last = try #require(plan.windows.last)
        #expect(bounds(last) == [2_276_500, 2_282_700])
        #expect(cues(last) == [
            Cue(2_277_000, .tick), Cue(2_278_000, .tick), Cue(2_279_000, .tick),
            Cue(2_280_000, .finish), Cue(2_281_000, voice("Workout complete")),
        ])
        #expect(plan.end == last.end)
    }

    @Test func norwegian4x4DucksOncePerBoundary() throws {
        let plan = try schedule()
        #expect(plan.windows.map { ms($0.start) } == [
            0, 296_500, 536_500, 716_500, 956_500, 1_136_500,
            1_376_500, 1_556_500, 1_796_500, 1_976_500, 2_276_500,
        ])
        #expect(cues(plan).count == 52)
    }

    @Test func lastRoundReplacesTheFinalRoundNumber() throws {
        #expect(spoken(try schedule()) == [
            "Warm up", "Round one", "Rest", "Round two", "Rest", "Round three", "Rest",
            "Last round", "Rest", "Cool down", "Workout complete",
        ])
    }

    @Test func aSingleRoundIsAnnouncedByNumber() throws {
        #expect(cues(try schedule(try timer(work: 60))) == [
            Cue(0, .phaseChange), Cue(500, voice("Round one")),
            Cue(57_000, .tick), Cue(58_000, .tick), Cue(59_000, .tick),
            Cue(60_000, .finish), Cue(61_000, voice("Workout complete")),
        ])
    }

    @Test func twentySecondPhasesKeepTheirOwnWindows() throws {
        let plan = try schedule(.hiit2020)
        #expect(plan.windows.count == 21)
        #expect(cues(plan).count == 102)

        let firstRest = plan.windows[2]
        #expect(bounds(firstRest) == [316_500, 322_200])
        #expect(cues(firstRest) == [
            Cue(317_000, .tick), Cue(318_000, .tick), Cue(319_000, .tick),
            Cue(320_000, .phaseChange), Cue(320_500, voice("Rest")),
        ])
        #expect(cues(plan.windows[17]).last == Cue(620_500, voice("Last round")))
    }

    @Test func audioCheckLeavesTheMusicAloneBetweenCues() throws {
        #expect(try schedule(.audioCheck).windows.map(bounds) == [
            [0, 2200], [26_500, 32_200], [36_500, 42_200], [46_500, 52_200], [56_500, 62_700],
        ])
    }

    @Test func shortPhasesDropEarlyTicksAndMergeIntoOneWindow() throws {
        let plan = try schedule(try timer(work: 4, rest: 4, rounds: 2, restAfterLastRound: false))
        #expect(plan.windows.map(bounds) == [[0, 14_700]])
        #expect(cues(plan) == [
            Cue(0, .phaseChange), Cue(500, voice("Round one")),
            Cue(2000, .tick), Cue(3000, .tick),
            Cue(4000, .phaseChange), Cue(4500, voice("Rest")),
            Cue(6000, .tick), Cue(7000, .tick),
            Cue(8000, .phaseChange), Cue(8500, voice("Last round")),
            Cue(10_000, .tick), Cue(11_000, .tick),
            Cue(12_000, .finish), Cue(13_000, voice("Workout complete")),
        ])
    }

    @Test func aTwoSecondPhaseHasNoTicks() throws {
        #expect(cues(try schedule(try timer(work: 2))) == [
            Cue(0, .phaseChange), Cue(500, voice("Round one")),
            Cue(2000, .finish), Cue(3000, voice("Workout complete")),
        ])
    }

    @Test func aPhaseTooShortForItsPhraseKeepsTheToneAndDropsTheVoice() throws {
        let plan = try schedule(try timer(work: 1, rest: 1, rounds: 2, restAfterLastRound: false))
        #expect(cues(plan) == [
            Cue(0, .phaseChange),
            Cue(1000, .phaseChange),
            Cue(2000, .phaseChange),
            Cue(3000, .finish), Cue(4000, voice("Workout complete")),
        ])
    }

    @Test func aThreeSecondPhaseKeepsOnlyTheLastTick() throws {
        #expect(cues(try schedule(try timer(work: 3), countdown: .five)) == [
            Cue(0, .phaseChange), Cue(500, voice("Round one")),
            Cue(2000, .tick),
            Cue(3000, .finish), Cue(4000, voice("Workout complete")),
        ])
    }

    @Test func countdownOffGivesNoTicks() throws {
        let plan = try schedule(countdown: .off)
        #expect(!plan.vocabulary.contains(.tick))
        #expect(bounds(plan.windows[1]) == [299_500, 302_200])
        #expect(cues(plan.windows[1]) == [Cue(300_000, .phaseChange), Cue(300_500, voice("Round one"))])
        #expect(cues(plan).count == 22)
    }

    @Test func countdownFiveStartsTwoSecondsEarlier() throws {
        let window = try schedule(countdown: .five).windows[1]
        #expect(bounds(window) == [294_500, 302_200])
        #expect(cues(window) == [
            Cue(295_000, .tick), Cue(296_000, .tick), Cue(297_000, .tick),
            Cue(298_000, .tick), Cue(299_000, .tick),
            Cue(300_000, .phaseChange), Cue(300_500, voice("Round one")),
        ])
    }

    @Test func withoutVoiceTheWindowClosesRightAfterTheTone() throws {
        let plan = try schedule(voice: false)
        #expect(bounds(plan.windows[0]) == [0, 600])
        #expect(bounds(plan.windows[1]) == [296_500, 300_600])
        #expect(cues(plan.windows[1]) == [
            Cue(297_000, .tick), Cue(298_000, .tick), Cue(299_000, .tick), Cue(300_000, .phaseChange),
        ])
        #expect(bounds(try #require(plan.windows.last)) == [2_276_500, 2_281_100])
        #expect(plan.vocabulary == [.phaseChange, .tick, .finish])
    }

    @Test func vocabularyListsEveryDistinctSoundInOrderOfFirstUse() throws {
        #expect(try schedule().vocabulary == [
            .phaseChange, voice("Warm up"), .tick, voice("Round one"), voice("Rest"),
            voice("Round two"), voice("Round three"), voice("Last round"), voice("Cool down"),
            .finish, voice("Workout complete"),
        ])
    }

    @Test func windowsAreSortedDisjointAndHoldTheirSounds() throws {
        let workouts = [
            .norwegian4x4, .hiit2020, .audioCheck, .dailyStretch,
            try timer(work: 1, rest: 1, rounds: 5),
            try timer(warmUp: 3, work: 4, rest: 4, rounds: 3, coolDown: 2),
            try timer(work: 7, rest: 5, rounds: 4, restAfterLastRound: false),
            try timer(warmUp: 25, work: 5, rest: 45, rounds: 3),
            try routine([
                try stretch("Neck Rolls", try reps(4), .each),
                try stretch("Calf", try hold(1), .each),
                try stretch("Squat", try reps(1)),
            ]),
            try routine(countIn: nil, [try stretch("Calf", try hold(2), .each), try stretch("Cobra", try hold(30))]),
            try routine(countIn: 30, [try stretch("Cobra", try hold(30))]),
        ]
        for workout in workouts {
            for countdown in Countdown.allCases {
                for voice in [true, false] {
                    for headsUp in HeadsUp.allCases {
                        for plan in try legs(workout, countdown: countdown, voice: voice, headsUp: headsUp) {
                            for (earlier, later) in zip(plan.windows, plan.windows.dropFirst()) {
                                #expect(ms(later.start) - ms(earlier.end) >= 1500)
                            }
                            for window in plan.windows {
                                #expect(!window.sounds.isEmpty)
                                #expect(window.sounds.map(\.at) == window.sounds.map(\.at).sorted())
                                for timed in window.sounds {
                                    #expect(timed.at >= window.start)
                                    #expect(ms(timed.at + timed.sound.slot) + 200 <= ms(window.end))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CueProjectionTests {
    @Test func remainingBeforeTheStartIsTheWholePlan() throws {
        let plan = try schedule()
        #expect(plan.remaining(after: t0 - 5) == plan)
    }

    @Test func remainingBetweenWindowsDropsTheClosedOnes() throws {
        let plan = try schedule()
        #expect(plan.remaining(after: t0 + 100).windows == Array(plan.windows.dropFirst()))
    }

    @Test func remainingClampsTheWindowInProgressAndDropsOldSounds() throws {
        let todo = try schedule().remaining(after: t0 + 298.5)
        #expect(todo.windows.count == 10)
        #expect(bounds(todo.windows[0]) == [298_500, 302_200])
        #expect(cues(todo.windows[0]) == [
            Cue(299_000, .tick), Cue(300_000, .phaseChange), Cue(300_500, voice("Round one")),
        ])
    }

    @Test(arguments: [298.1, 298.25])
    func aSoundWithinTheGraceKeepsItsPastTime(now: TimeInterval) throws {
        let todo = try schedule().remaining(after: t0 + now)
        #expect(ms(todo.windows[0].start) == Int(now * 1000))
        #expect(cues(todo.windows[0]) == [
            Cue(298_000, .tick), Cue(299_000, .tick),
            Cue(300_000, .phaseChange), Cue(300_500, voice("Round one")),
        ])
    }

    @Test func aWindowStaysOpenWhileItsLastSoundPlaysOut() throws {
        let todo = try schedule().remaining(after: t0 + 301)
        #expect(bounds(todo.windows[0]) == [301_000, 302_200])
        #expect(todo.windows[0].sounds.isEmpty)
        #expect(todo.isDucked(at: t0 + 301))
    }

    @Test func aWindowIsClosedAtItsEnd() throws {
        let plan = try schedule()
        #expect(plan.remaining(after: plan.windows[1].end).windows == Array(plan.windows.dropFirst(2)))
    }

    @Test func nothingRemainsAfterTheLastWindow() throws {
        let plan = try schedule()
        #expect(ms(try #require(plan.end)) == 2_282_700)

        let todo = plan.remaining(after: t0 + 2283)
        #expect(todo.isEmpty)
        #expect(todo.end == nil)
        #expect(!plan.isEmpty)
    }

    @Test func duckedExactlyInsideTheWindows() throws {
        let plan = try schedule()
        #expect(!plan.isDucked(at: t0 - 0.1))
        #expect(plan.isDucked(at: t0))
        #expect(plan.isDucked(at: t0 + 2.1))
        #expect(!plan.isDucked(at: t0 + 2.3))
        #expect(!plan.isDucked(at: t0 + 296.4))
        #expect(plan.isDucked(at: t0 + 296.5))
        #expect(plan.isDucked(at: t0 + 302.1))
        #expect(!plan.isDucked(at: t0 + 302.3))
        #expect(!plan.isDucked(at: t0 + 5000))
    }

    @Test func nextEdgeIsTheNextWindowStartOrEnd() throws {
        let plan = try schedule()
        #expect(plan.nextEdge(after: t0 - 5) == t0)
        #expect(ms(try #require(plan.nextEdge(after: t0))) == 2200)
        #expect(plan.nextEdge(after: t0 + 100) == t0 + 296.5)
        #expect(ms(try #require(plan.nextEdge(after: t0 + 296.5))) == 302_200)
        #expect(plan.nextEdge(after: t0 + 5000) == nil)
    }

    @Test func duckingFlipsAtEveryEdgeAndNowhereElse() throws {
        let plan = try schedule(.hiit2020)
        var edges: [Date] = []
        var cursor = t0 - 5
        while let edge = plan.nextEdge(after: cursor), edges.count < 1000 {
            edges.append(edge)
            cursor = edge
        }
        #expect(edges == plan.windows.flatMap { [$0.start, $0.end] })
        #expect(edges.count == 42)
        for (index, edge) in edges.enumerated() {
            let opensWindow = index.isMultiple(of: 2)
            #expect(plan.isDucked(at: edge) == opensWindow)
            #expect(plan.isDucked(at: edge - 0.01) == !opensWindow)
        }
    }

    @Test func afterASkipTheNewPhaseIsAnnouncedOneSecondLaterAndTheMusicDipsAtOnce() throws {
        var run = session()
        let now = t0 + 100
        run.skip(try progress(run, at: 100).segment, at: now)

        let todo = try #require(run.cueSchedule).remaining(after: now)
        let first = try #require(todo.windows.first)
        #expect(first.start == now)
        #expect(cues(first) == [Cue(101_000, .phaseChange), Cue(101_500, voice("Round one"))], "nothing sounds in the first second")
        #expect(ms(first.end) == 103_200)
        #expect(todo.isDucked(at: now))
    }

    @Test func skippingTheLastPhaseSoundsTheFinishOneSecondLater() throws {
        var run = session()
        let now = t0 + 2000
        run.skip(try progress(run, at: 2000).segment, at: now)

        let todo = try #require(run.cueSchedule).remaining(after: now)
        #expect(bounds(try #require(todo.windows.first)) == [2_000_000, 2_003_700])
        #expect(cues(todo) == [Cue(2_001_000, .finish), Cue(2_002_000, voice("Workout complete"))])
    }

    @Test func resumingShiftsThePlanByThePausedTime() throws {
        var run = session(cues: CuePreferences(headsUp: .off))
        run.pause(at: t0 + 100)
        run.resume(at: t0 + 1000)

        let todo = try #require(run.cueSchedule).remaining(after: t0 + 1000)
        let next = try #require(todo.windows.first)
        #expect(bounds(next) == [1_196_500, 1_202_200])
        #expect(cues(next).last == Cue(1_200_500, voice("Round one")))
    }
}

struct UtteranceTests {
    @Test func roundNumbersAreSpelledOut() throws {
        let spoken = spoken(try schedule(try timer(work: 5, rounds: 22)))
        try #require(spoken.count == 23)
        #expect(spoken[2] == "Round three")
        #expect(spoken[20] == "Round twenty-one")
        #expect(spoken[21] == "Last round")
    }

    @Test(arguments: [
        "Warm up", "Round one", "Round twenty-one", "Last round", "Rest", "Cool down",
        "Switch sides", "Workout complete", "",
    ])
    func aShortTextGetsTheMinimumSlot(_ text: String) {
        #expect(Utterance(text).slot == 1.5)
    }

    @Test(arguments: [
        (18, 1.5), (19, 1.6), (20, 1.6), (21, 1.7), (25, 1.9), (35, 2.5), (51, 3.5), (52, 3.6),
        (60, 4.0), (61, 4.0), (500, 4.0),
    ])
    func theSlotGrowsWithTheTextUpToFourSeconds(characters: Int, slot: TimeInterval) {
        #expect(Utterance(String(repeating: "a", count: characters)).slot == slot)
    }

    @Test func aFortyCharacterNameWithItsSideGetsThreePointSixSeconds() {
        let longest = Utterance(String(repeating: "a", count: 40) + ", right side")
        #expect(longest.text.count == 52)
        #expect(longest.slot == 3.6)
    }

    @Test func theFixedTexts() {
        #expect(Utterance.workoutComplete.text == "Workout complete")
    }

    @Test func soundSlots() {
        #expect(Sound.tick.slot == 0.12)
        #expect(Sound.phaseChange.slot == 0.40)
        #expect(Sound.finish.slot == 0.90)
        #expect(voice("Rest").slot == 1.5)
        #expect(voice("Hip Flexor Couch Stretch, left side").slot == 2.5)
    }
}

struct QuietSkipTests {
    @Test func everySkipThroughEveryWorkoutIsSilentForOneSecondAndKeepsTheMusicDown() throws {
        let workouts = [
            .norwegian4x4, .hiit2020, .audioCheck, .dailyStretch,
            try timer(work: 1, rest: 1, rounds: 5),
            try timer(warmUp: 3, work: 4, rest: 4, rounds: 3, coolDown: 2),
            try routine([try stretch("Neck Rolls", try reps(4), .each), try stretch("Calf", try hold(1), .each)]),
            try routine(countIn: nil, [try stretch("Calf", try hold(2), .each), try stretch("Cobra", try hold(30))]),
        ]
        for workout in workouts {
            for voice in [true, false] {
                var run = session(workout, cues: CuePreferences(voice: voice))
                var now = t0 + 0.5
                for _ in 0..<100 {
                    guard case .active(let progress) = run.snapshot(at: now) else { break }
                    run.forward(progress.segment, at: now)
                    let plan = try #require(run.cueSchedule)
                    let todo = plan.remaining(after: now)
                    #expect(todo.windows.flatMap(\.sounds).allSatisfy { $0.at >= now + 1 }, "\(workout.name) at \(ms(now))")
                    #expect(plan.isDucked(at: now), "\(workout.name) at \(ms(now))")
                    for (earlier, later) in zip(plan.windows, plan.windows.dropFirst()) {
                        #expect(ms(later.start) - ms(earlier.end) >= 1500)
                    }
                    for window in plan.windows {
                        #expect(window.sounds.allSatisfy { $0.at >= window.start && $0.at + $0.sound.slot + 0.2 <= window.end + 0.0001 })
                    }
                    now += 0.4
                }
                #expect(run.snapshot(at: now) != run.snapshot(at: t0), "\(workout.name) reached the finish")
            }
        }
    }

    @Test func ofTwoSkipsHalfASecondApartOnlyTheSecondLandingSounds() throws {
        var run = session()
        run.skip(try progress(run, at: 100).segment, at: t0 + 100)
        let first = try #require(run.cueSchedule)
        run.skip(try progress(run, at: 100.5).segment, at: t0 + 100.5)
        let second = try #require(run.cueSchedule)

        let todo = second.remaining(after: t0 + 100.5)
        #expect(cues(todo.windows[0]) == [Cue(101_500, .phaseChange), Cue(102_000, voice("Rest"))])
        #expect(!spoken(todo).contains("Round one"))
        #expect(first.isDucked(at: t0 + 100.5) && second.isDucked(at: t0 + 100.5), "the music stays down from one skip to the next")
    }

    @Test func aNaturalBoundaryAfterALandingSoundsAtItsOwnTime() throws {
        var run = session()
        run.skip(try progress(run, at: 100).segment, at: t0 + 100)
        let todo = try #require(run.cueSchedule).remaining(after: t0 + 100)
        #expect(cues(todo.windows[1]) == [
            Cue(337_000, .tick), Cue(338_000, .tick), Cue(339_000, .tick),
            Cue(340_000, .phaseChange), Cue(340_500, voice("Rest")),
        ])
    }

    @Test func aLandingTooCloseToTheEndOfItsPhaseIsLeftToTheNextTone() throws {
        var run = session(try timer(work: 20, rest: 2, rounds: 2, restAfterLastRound: false))
        run.skip(try progress(run, at: 5).segment, at: t0 + 5)
        #expect(cues(try #require(run.cueSchedule).remaining(after: t0 + 5)) == [
            Cue(7000, .phaseChange), Cue(7500, voice("Last round")),
            Cue(24_000, .tick), Cue(25_000, .tick), Cue(26_000, .tick),
            Cue(27_000, .finish), Cue(28_000, voice("Workout complete")),
        ])
    }

    @Test func aLandingThatJustFitsKeepsItsToneAndItsName() throws {
        var run = session(try timer(work: 20, rest: 3, rounds: 2, restAfterLastRound: false))
        run.skip(try progress(run, at: 5).segment, at: t0 + 5)
        let todo = try #require(run.cueSchedule).remaining(after: t0 + 5)
        #expect(cues(todo).prefix(4) == [
            Cue(6000, .phaseChange), Cue(6500, voice("Rest")), Cue(8000, .phaseChange), Cue(8500, voice("Last round")),
        ])
    }

    @Test func aPauseDuringTheSecondHoldsTheAnnouncementBack() throws {
        var run = session()
        run.skip(try progress(run, at: 100).segment, at: t0 + 100)
        run.pause(at: t0 + 100.4)
        #expect(run.cueSchedule == nil)
        run.resume(at: t0 + 200)

        let todo = try #require(run.cueSchedule).remaining(after: t0 + 200)
        #expect(cues(todo.windows[0]) == [Cue(200_600, .phaseChange), Cue(201_100, voice("Round one"))])
    }

    @Test func aSkipWhilePausedIsAnnouncedOneSecondAfterResume() throws {
        var run = session()
        run.pause(at: t0 + 100)
        run.skip(try progress(run, at: 100).segment, at: t0 + 150)
        run.resume(at: t0 + 200)
        #expect(cues(try #require(run.cueSchedule).remaining(after: t0 + 200).windows[0]) == [
            Cue(201_000, .phaseChange), Cue(201_500, voice("Round one")),
        ])
    }

    @Test func restartSoundsAtOnceEvenBeforeALandingWasAnnounced() throws {
        var run = session()
        run.skip(try progress(run, at: 100).segment, at: t0 + 100)
        run.restart(try progress(run, at: 100.5).segment, at: t0 + 100.5)
        #expect(cues(try #require(run.cueSchedule).remaining(after: t0 + 100.5).windows[0]) == [
            Cue(100_500, .phaseChange), Cue(101_000, voice("Round one")),
        ])
    }

    @Test func withoutVoiceALandingIsTheToneAlone() throws {
        var run = session(cues: CuePreferences(voice: false, headsUp: .off))
        run.skip(try progress(run, at: 100).segment, at: t0 + 100)
        let todo = try #require(run.cueSchedule).remaining(after: t0 + 100)
        let first = try #require(todo.windows.first)
        #expect(bounds(first) == [100_000, 101_600])
        #expect(cues(first) == [Cue(101_000, .phaseChange)])
    }

    @Test func aLandingKeepsTheCountdownClearOfItsName() throws {
        var run = session(try timer(work: 20, rest: 5, rounds: 2, restAfterLastRound: false), cues: CuePreferences(countdown: .five))
        run.skip(try progress(run, at: 5).segment, at: t0 + 5)
        let todo = try #require(run.cueSchedule).remaining(after: t0 + 5)
        #expect(cues(todo).prefix(5) == [
            Cue(6000, .phaseChange), Cue(6500, voice("Rest")), Cue(8000, .tick), Cue(9000, .tick), Cue(10_000, .phaseChange),
        ], "the beeps at 5, 6 and 7 s would sound over the tone and the name")
    }
}
