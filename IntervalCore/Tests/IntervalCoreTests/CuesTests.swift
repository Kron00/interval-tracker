import Foundation
import IntervalCore
import Testing

private func schedule(_ definition: TimerDefinition = .norwegian4x4,
                      countdown: Countdown = .three, voice: Bool = true) throws -> CueSchedule {
    try #require(session(definition, cues: CuePreferences(countdown: countdown, voice: voice)).cueSchedule)
}

private func bounds(_ window: DuckWindow) -> [Int] {
    [ms(window.start), ms(window.end)]
}

struct CueScheduleTests {
    @Test func startBurstOfNorwegian4x4() throws {
        let first = try #require(try schedule().windows.first)
        #expect(bounds(first) == [0, 2200])
        #expect(cues(first) == [Cue(0, .phaseChange), Cue(500, .voice(.warmUp))])
    }

    @Test func firstBoundaryOfNorwegian4x4() throws {
        let window = try schedule().windows[1]
        #expect(bounds(window) == [296_500, 302_200])
        #expect(cues(window) == [
            Cue(297_000, .tick), Cue(298_000, .tick), Cue(299_000, .tick),
            Cue(300_000, .phaseChange), Cue(300_500, .voice(.round(1))),
        ])
    }

    @Test func finishOfNorwegian4x4() throws {
        let plan = try schedule()
        let last = try #require(plan.windows.last)
        #expect(bounds(last) == [2_276_500, 2_282_700])
        #expect(cues(last) == [
            Cue(2_277_000, .tick), Cue(2_278_000, .tick), Cue(2_279_000, .tick),
            Cue(2_280_000, .finish), Cue(2_281_000, .voice(.done)),
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
        let spoken = cues(try schedule()).compactMap { cue -> Phrase? in
            if case .voice(let phrase) = cue.sound { phrase } else { nil }
        }
        #expect(spoken == [
            .warmUp, .round(1), .rest, .round(2), .rest, .round(3), .rest,
            .lastRound, .rest, .coolDown, .done,
        ])
    }

    @Test func aSingleRoundIsAnnouncedByNumber() throws {
        #expect(cues(try schedule(try timer(work: 60))) == [
            Cue(0, .phaseChange), Cue(500, .voice(.round(1))),
            Cue(57_000, .tick), Cue(58_000, .tick), Cue(59_000, .tick),
            Cue(60_000, .finish), Cue(61_000, .voice(.done)),
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
            Cue(320_000, .phaseChange), Cue(320_500, .voice(.rest)),
        ])
        #expect(cues(plan.windows[17]).last == Cue(620_500, .voice(.lastRound)))
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
            Cue(0, .phaseChange), Cue(500, .voice(.round(1))),
            Cue(2000, .tick), Cue(3000, .tick),
            Cue(4000, .phaseChange), Cue(4500, .voice(.rest)),
            Cue(6000, .tick), Cue(7000, .tick),
            Cue(8000, .phaseChange), Cue(8500, .voice(.lastRound)),
            Cue(10_000, .tick), Cue(11_000, .tick),
            Cue(12_000, .finish), Cue(13_000, .voice(.done)),
        ])
    }

    @Test func aTwoSecondPhaseHasNoTicks() throws {
        #expect(cues(try schedule(try timer(work: 2))) == [
            Cue(0, .phaseChange), Cue(500, .voice(.round(1))),
            Cue(2000, .finish), Cue(3000, .voice(.done)),
        ])
    }

    @Test func aThreeSecondPhaseKeepsOnlyTheLastTick() throws {
        #expect(cues(try schedule(try timer(work: 3), countdown: .five)) == [
            Cue(0, .phaseChange), Cue(500, .voice(.round(1))),
            Cue(2000, .tick),
            Cue(3000, .finish), Cue(4000, .voice(.done)),
        ])
    }

    @Test func countdownOffGivesNoTicks() throws {
        let plan = try schedule(countdown: .off)
        #expect(!plan.vocabulary.contains(.tick))
        #expect(bounds(plan.windows[1]) == [299_500, 302_200])
        #expect(cues(plan.windows[1]) == [Cue(300_000, .phaseChange), Cue(300_500, .voice(.round(1)))])
        #expect(cues(plan).count == 22)
    }

    @Test func countdownFiveStartsTwoSecondsEarlier() throws {
        let window = try schedule(countdown: .five).windows[1]
        #expect(bounds(window) == [294_500, 302_200])
        #expect(cues(window) == [
            Cue(295_000, .tick), Cue(296_000, .tick), Cue(297_000, .tick),
            Cue(298_000, .tick), Cue(299_000, .tick),
            Cue(300_000, .phaseChange), Cue(300_500, .voice(.round(1))),
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
        #expect(plan.vocabulary == [.tick, .phaseChange, .finish])
    }

    @Test func vocabularyListsEveryDistinctSound() throws {
        #expect(try schedule().vocabulary == [
            .tick, .phaseChange, .finish,
            .voice(.warmUp), .voice(.round(1)), .voice(.round(2)), .voice(.round(3)),
            .voice(.lastRound), .voice(.rest), .voice(.coolDown), .voice(.done),
        ])
    }

    @Test func windowsAreSortedDisjointAndHoldTheirSounds() throws {
        let definitions = [
            .norwegian4x4, .hiit2020, .audioCheck,
            try timer(work: 1, rest: 1, rounds: 5),
            try timer(warmUp: 3, work: 4, rest: 4, rounds: 3, coolDown: 2),
            try timer(work: 7, rest: 5, rounds: 4, restAfterLastRound: false),
        ]
        for definition in definitions {
            for countdown in Countdown.allCases {
                for voice in [true, false] {
                    let plan = try schedule(definition, countdown: countdown, voice: voice)
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
            Cue(299_000, .tick), Cue(300_000, .phaseChange), Cue(300_500, .voice(.round(1))),
        ])
    }

    @Test(arguments: [298.1, 298.25])
    func aSoundWithinTheGraceKeepsItsPastTime(now: TimeInterval) throws {
        let todo = try schedule().remaining(after: t0 + now)
        #expect(ms(todo.windows[0].start) == Int(now * 1000))
        #expect(cues(todo.windows[0]) == [
            Cue(298_000, .tick), Cue(299_000, .tick),
            Cue(300_000, .phaseChange), Cue(300_500, .voice(.round(1))),
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

    @Test func afterASkipTheNewPhaseSoundsAtOnce() throws {
        var run = session()
        let now = t0 + 100
        run.skip(try progress(run, at: 100).segment, at: now)

        let todo = try #require(run.cueSchedule).remaining(after: now)
        let first = try #require(todo.windows.first)
        #expect(first.start == now)
        #expect(first.sounds.first?.at == now)
        #expect(cues(first) == [Cue(100_000, .phaseChange), Cue(100_500, .voice(.round(1)))])
        #expect(ms(first.end) == 102_200)
        #expect(todo.isDucked(at: now))
    }

    @Test func skippingTheLastPhaseSoundsTheFinishAtOnce() throws {
        var run = session()
        let now = t0 + 2000
        run.skip(try progress(run, at: 2000).segment, at: now)

        let todo = try #require(run.cueSchedule).remaining(after: now)
        #expect(cues(todo) == [Cue(2_000_000, .finish), Cue(2_001_000, .voice(.done))])
        #expect(ms(try #require(todo.end)) == 2_002_700)
    }

    @Test func resumingShiftsThePlanByThePausedTime() throws {
        var run = session()
        run.pause(at: t0 + 100)
        run.resume(at: t0 + 1000)

        let todo = try #require(run.cueSchedule).remaining(after: t0 + 1000)
        let next = try #require(todo.windows.first)
        #expect(bounds(next) == [1_196_500, 1_202_200])
        #expect(cues(next).last == Cue(1_200_500, .voice(.round(1))))
    }
}

struct PhraseTests {
    @Test(arguments: [
        (Phrase.warmUp, "Warm up"),
        (.round(3), "Round three"),
        (.round(21), "Round twenty-one"),
        (.lastRound, "Last round"),
        (.rest, "Rest"),
        (.coolDown, "Cool down"),
        (.done, "Workout complete"),
    ])
    func spokenText(_ phrase: Phrase, reads text: String) {
        #expect(phrase.spokenText == text)
    }
}
