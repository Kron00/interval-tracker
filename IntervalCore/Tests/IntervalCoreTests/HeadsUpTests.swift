import Foundation
import IntervalCore
import Testing

private let thirty = voice("Get ready. Thirty seconds.")
private let ten = voice("Get ready. Ten seconds.")

private func headsUps(in plan: CueSchedule) -> [Int] {
    cues(plan).filter { $0.sound == thirty || $0.sound == ten }.map(\.ms)
}

struct HeadsUpCueTests {
    /// Norwegian 4x4 is a 5:00 warm-up, then 4:00 of work and 3:00 of rest four times, then a cool-down.
    @Test func theDefaultSpeaksThirtySecondsBeforeEveryWorkRound() throws {
        let plan = try #require(session().cueSchedule)
        #expect(headsUps(in: plan) == [270_000, 690_000, 1_110_000, 1_530_000])
        #expect(plan.windows.map { ms($0.start) } == [
            0, 269_500, 296_500, 536_500, 689_500, 716_500, 956_500, 1_109_500, 1_136_500,
            1_376_500, 1_529_500, 1_556_500, 1_796_500, 1_976_500, 2_276_500,
        ])
        #expect(cues(plan).count == 55)
        #expect(spoken(plan) == [
            "Warm up", "Get ready. Thirty seconds.", "Round one",
            "Rest", "Get ready. Thirty seconds.", "Round two",
            "Rest", "Get ready. Thirty seconds.", "Round three",
            "Rest", "Get ready. Thirty seconds.", "Last round",
            "Rest", "Cool down", "Workout complete",
        ])
    }

    @Test func theHeadsUpDipsTheMusicOnceAndLeavesTheBoundaryAsItWas() throws {
        let plan = try schedule(headsUp: .thirty)
        #expect(bounds(plan.windows[1]) == [269_500, 272_200])
        #expect(cues(plan.windows[1]) == [Cue(270_000, thirty)])
        #expect(plan.windows[2] == (try schedule().windows[1]))
    }

    @Test func tenSecondsStillEndsBeforeAFiveSecondCountdown() throws {
        let plan = try schedule(countdown: .five, headsUp: .ten)
        #expect(bounds(plan.windows[1]) == [289_500, 292_000])
        #expect(cues(plan.windows[1]) == [Cue(290_000, ten)])
        #expect(plan.windows[2] == (try schedule(countdown: .five).windows[1]))
    }

    @Test func twentySecondRestsGetNoneSoOnlyTheWarmUpOfTwentyTwentySpeaks() throws {
        let plan = try #require(session(.hiit2020).cueSchedule)
        #expect(headsUps(in: plan) == [270_000])
        #expect(plan.windows.count == 22)
        #expect(cues(plan).count == 102)
    }

    @Test func theAudioCheckSpeaksTenSecondsBeforeItsFirstRound() throws {
        let plan = try schedule(.audioCheck, headsUp: .ten)
        #expect(plan.windows.map(bounds) == [
            [0, 2200], [19_500, 22_000], [26_500, 32_200], [36_500, 42_200], [46_500, 52_200], [56_500, 62_700],
        ])
        #expect(headsUps(in: plan) == [20_000])
        #expect(try schedule(.audioCheck, headsUp: .thirty) == (try schedule(.audioCheck)), "a 30-second warm-up is too short for 30 seconds of notice")
    }

    /// Work is 5 s, so the rest runs from 0:05.
    @Test(arguments: [
        (HeadsUp.thirty, 45, [20_000]), (.thirty, 44, []), (.thirty, 600, [575_000]),
        (.ten, 25, [20_000]), (.ten, 24, []),
        (.off, 600, []),
    ])
    func aPhaseGetsOneOnlyWhenItIsFifteenSecondsLongerThanTheNotice(headsUp: HeadsUp, rest: Int, at: [Int]) throws {
        let workout = try timer(work: 5, rest: rest, rounds: 2, restAfterLastRound: false)
        #expect(headsUps(in: try schedule(workout, headsUp: headsUp)) == at)
    }

    @Test func aRestThatNoWorkFollowsGetsNone() throws {
        let beforeTheFinish = try timer(work: 60, rest: 60, rounds: 2)
        #expect(headsUps(in: try schedule(beforeTheFinish, headsUp: .thirty)) == [90_000])

        let beforeTheCoolDown = try timer(work: 60, rest: 60, rounds: 1, coolDown: 60)
        #expect(headsUps(in: try schedule(beforeTheCoolDown, headsUp: .thirty)).isEmpty)
    }

    @Test func workThatFollowsWorkGetsNone() throws {
        let workout = try timer(work: 60, rounds: 3)
        #expect(headsUps(in: try schedule(workout, headsUp: .thirty)).isEmpty)
        #expect(!(try progress(session(workout), at: 45).isHeadsUp))
    }

    @Test func withVoiceCuesOffNothingIsSpoken() throws {
        #expect(try schedule(voice: false, headsUp: .thirty) == (try schedule(voice: false)))
    }

    /// A 30-second count-in is long enough for 10 seconds of notice, and a 60-second hold for 30.
    /// Neither is followed by work.
    @Test(arguments: [HeadsUp.ten, .thirty])
    func aStretchRoutineGetsNone(headsUp: HeadsUp) throws {
        let long = try routine(countIn: 30, [try stretch("Calf", try hold(60), .each)])
        for workout in [.dailyStretch, long] {
            #expect(try legs(workout, headsUp: headsUp) == (try legs(workout)))
        }
        var run = session(long, cues: CuePreferences(headsUp: headsUp))
        #expect(!(try progress(run, at: 100).isHeadsUp), "the left side waits for Start")
        run.perform(.play, at: t0 + 100)
        for second in [100.0, 120, 129.9, 130, 160, 189.9] {
            #expect(!(try progress(run, at: second).isHeadsUp), "\(second)")
        }
        #expect(!(try progress(run, at: 190).isHeadsUp), "the right side waits for Start")
    }

    @Test func thePhrasesGetSlotsLongEnoughToSayThem() {
        #expect(thirty.slot == 2.0)
        #expect(ten.slot == 1.8)
    }

    @Test func theVocabularyHoldsThePhraseOnce() {
        #expect(session().vocabulary.filter { $0 == thirty }.count == 1)
        #expect(session(cues: CuePreferences(headsUp: .ten)).vocabulary.contains(ten))
        #expect(!session(cues: CuePreferences(headsUp: .off)).vocabulary.contains(thirty))
        #expect(!session(.dailyStretch).vocabulary.contains(thirty))
    }
}

struct HeadsUpProgressTests {
    @Test func itLastsFromTheNoticeToTheEndOfThePhase() throws {
        let run = session()
        #expect(!(try progress(run, at: 0).isHeadsUp))
        #expect(!(try progress(run, at: 269.9).isHeadsUp))
        #expect(try progress(run, at: 270).isHeadsUp)
        #expect(try progress(run, at: 299.9).isHeadsUp)
        #expect(!(try progress(run, at: 300).isHeadsUp), "work has begun")
        #expect(!(try progress(run, at: 689.9).isHeadsUp))
        #expect(try progress(run, at: 690).isHeadsUp, "30 seconds before the first rest ends")
        #expect(!(try progress(run, at: 1979).isHeadsUp), "the cool-down follows the last rest")
        #expect(!(try progress(run, at: 2279).isHeadsUp))
    }

    @Test func theCaptionSaysGetReadyDuringIt() throws {
        let run = session()
        #expect(try progress(run, at: 100).caption == nil)
        #expect(try progress(run, at: 270).caption == "Get ready")
        #expect(try progress(run, at: 600).caption == "Round 1 of 4")
        #expect(try progress(run, at: 700).caption == "Get ready")

        var stretches = session(.dailyStretch)
        #expect(try progress(stretches, at: 0).caption == "Stretch 1 of 10")
        stretches.perform(.next, at: t0)
        stretches.perform(.play, at: t0)
        #expect(try progress(stretches, at: 1).caption == "Get ready", "a stretch's count-in keeps its own caption")
    }

    @Test(arguments: [(HeadsUp.ten, 289.9, 290.0), (.thirty, 269.9, 270.0)])
    func itFollowsTheSetting(headsUp: HeadsUp, before: TimeInterval, from: TimeInterval) throws {
        let run = session(cues: CuePreferences(headsUp: headsUp))
        #expect(!(try progress(run, at: before).isHeadsUp))
        #expect(try progress(run, at: from).isHeadsUp)
    }

    @Test func offNeverReportsOne() throws {
        let run = session(cues: CuePreferences(headsUp: .off))
        for second in [0.0, 270, 299, 690, 719] {
            #expect(!(try progress(run, at: second).isHeadsUp), "\(second)")
        }
        #expect(try progress(run, at: 700).caption == "Round 1 of 4")
    }

    @Test func itDoesNotDependOnVoiceCues() throws {
        let run = session(cues: CuePreferences(voice: false))
        #expect(try progress(run, at: 280).isHeadsUp)
    }

    @Test func aPauseKeepsItAndGoingBackEndsIt() throws {
        var run = session()
        run.pause(at: t0 + 280)
        let paused = try progress(run, at: 5000)
        #expect(paused.isPaused)
        #expect(paused.isHeadsUp)

        run.back(paused.segment, at: t0 + 5000)
        #expect(!(try progress(run, at: 5000).isHeadsUp))
    }

    @Test func skippingIntoAPhaseStartsBeforeItsHeadsUp() throws {
        var run = session()
        run.skip(try progress(run, at: 280).segment, at: t0 + 280)
        run.skip(try progress(run, at: 280).segment, at: t0 + 280)
        let rest = try progress(run, at: 280)
        #expect(rest.phase.title == "Rest")
        #expect(!rest.isHeadsUp)
        #expect(try progress(run, at: 280 + 150).isHeadsUp)
    }
}
