import Foundation
import IntervalCore
import Testing

struct TimelineTests {
    @Test func norwegian4x4HasTenPhases() throws {
        #expect(try steps(of: .norwegian4x4) == [
            Step("warmUp", start: 0, duration: 300),
            Step("work 1/4", start: 300, duration: 240),
            Step("rest 1/4", start: 540, duration: 180),
            Step("work 2/4", start: 720, duration: 240),
            Step("rest 2/4", start: 960, duration: 180),
            Step("work 3/4", start: 1140, duration: 240),
            Step("rest 3/4", start: 1380, duration: 180),
            Step("work 4/4", start: 1560, duration: 240),
            Step("rest 4/4", start: 1800, duration: 180),
            Step("coolDown", start: 1980, duration: 300),
        ])
    }

    @Test func hiit2020HasTwentyPhases() throws {
        let steps = try steps(of: .hiit2020)
        try #require(steps.count == 20)
        #expect(steps[0] == Step("warmUp", start: 0, duration: 300))
        #expect(steps[1] == Step("work 1/9", start: 300, duration: 20))
        #expect(steps[2] == Step("rest 1/9", start: 320, duration: 20))
        #expect(steps[17] == Step("work 9/9", start: 620, duration: 20))
        #expect(steps[18] == Step("rest 9/9", start: 640, duration: 20))
        #expect(steps[19] == Step("coolDown", start: 660, duration: 180))
    }

    @Test func audioCheckIsOneMinuteEndingOnWork() throws {
        #expect(try steps(of: .audioCheck) == [
            Step("warmUp", start: 0, duration: 30),
            Step("work 1/2", start: 30, duration: 10),
            Step("rest 1/2", start: 40, duration: 10),
            Step("work 2/2", start: 50, duration: 10),
        ])
    }

    @Test func workAloneIsOnePhase() throws {
        #expect(try steps(of: try timer(work: 45)) == [Step("work 1/1", start: 0, duration: 45)])
    }

    @Test func roundsWithoutRestRunBackToBack() throws {
        #expect(try steps(of: try timer(work: 30, rounds: 3)) == [
            Step("work 1/3", start: 0, duration: 30),
            Step("work 2/3", start: 30, duration: 30),
            Step("work 3/3", start: 60, duration: 30),
        ])
    }

    @Test func restFollowsTheLastRoundByDefault() throws {
        #expect(try steps(of: try timer(work: 30, rest: 15, rounds: 2, coolDown: 60)) == [
            Step("work 1/2", start: 0, duration: 30),
            Step("rest 1/2", start: 30, duration: 15),
            Step("work 2/2", start: 45, duration: 30),
            Step("rest 2/2", start: 75, duration: 15),
            Step("coolDown", start: 90, duration: 60),
        ])
    }

    @Test func restAfterTheLastRoundCanBeTurnedOff() throws {
        let workout = try timer(work: 30, rest: 15, rounds: 2, coolDown: 60, restAfterLastRound: false)
        #expect(try steps(of: workout) == [
            Step("work 1/2", start: 0, duration: 30),
            Step("rest 1/2", start: 30, duration: 15),
            Step("work 2/2", start: 45, duration: 30),
            Step("coolDown", start: 75, duration: 60),
        ])
    }

    @Test func phaseTitles() throws {
        let run = session()
        #expect(try progress(run, at: 0).phase.title == "Warm-up")
        #expect(try progress(run, at: 300).phase.title == "Work")
        #expect(try progress(run, at: 540).phase.title == "Rest")
        #expect(try progress(run, at: 1980).phase.title == "Cool-down")
    }

    @Test func onlyWorkAndRestCarryARound() throws {
        let run = session()
        #expect(try progress(run, at: 0).phase == .warmUp)
        #expect(try progress(run, at: 0).phase.caption == nil)
        #expect(try progress(run, at: 1980).phase == .coolDown)
        #expect(try progress(run, at: 1980).phase.caption == nil)

        let rest = try progress(run, at: 960).phase
        guard case .rest(let second) = rest else {
            Issue.record("expected a rest, got \(rest)")
            return
        }
        #expect(second.number == 2)
        #expect(second.total == 4)
        #expect(!second.isLast)
        #expect(rest.caption == "Round 2 of 4")

        let work = try progress(run, at: 1560).phase
        guard case .work(let last) = work else {
            Issue.record("expected work, got \(work)")
            return
        }
        #expect(last.number == 4)
        #expect(last.isLast)
        #expect(work.caption == "Round 4 of 4")
    }

    @Test func intervalPhasesHaveNoRepsAndNoHowTo() throws {
        let run = session()
        for offset in [0.0, 300, 540, 1980] {
            let p = try progress(run, at: offset)
            #expect(p.reps == nil)
            #expect(p.phase.howTo == nil)
        }
    }

    @Test func anIntervalTimerNeverWaits() throws {
        for workout in [Workout.norwegian4x4, .hiit2020, .audioCheck] {
            #expect(try steps(of: workout).allSatisfy { !$0.waits })
            let run = session(workout)
            #expect(run.haltDate == t0 + workout.totalDuration)
            #expect(try progress(run, at: workout.totalDuration - 0.5).isWaiting == false)
            #expect(run.snapshot(at: t0 + workout.totalDuration) == .finished(worked: workout.totalDuration))
        }
    }

    @Test func skipIsWhatEndingAnIntervalPhaseIsCalled() throws {
        let run = session()
        #expect(try [0, 300, 540, 1980].map { try progress(run, at: $0).phase.advanceTitle } == [
            "Skip", "Skip", "Skip", "Skip",
        ])
    }

    @Test func intervalTones() throws {
        let run = session()
        #expect(try progress(run, at: 0).phase.tone == .prepare)
        #expect(try progress(run, at: 300).phase.tone == .effort)
        #expect(try progress(run, at: 540).phase.tone == .recover)
        #expect(try progress(run, at: 1980).phase.tone == .cool)
    }
}
