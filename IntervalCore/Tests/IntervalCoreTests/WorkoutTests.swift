import Foundation
import IntervalCore
import Testing

struct WorkoutTests {
    @Test func presetTotals() {
        #expect(Workout.norwegian4x4.totalDuration == 2280)
        #expect(Workout.hiit2020.totalDuration == 840)
        #expect(Workout.audioCheck.totalDuration == 60)
        #expect(Workout.dailyStretch.totalDuration == 645)
    }

    @Test func presetsWithoutTheRestAfterTheLastRound() throws {
        let rower = try editing(.norwegian4x4) { $0.restAfterLastRound = false }
        #expect(rower.totalDuration == 2100)

        let bike = try editing(.hiit2020) { $0.restAfterLastRound = false }
        #expect(bike.totalDuration == 820)
    }

    @Test func builtInsAreTheThreePresets() {
        #expect(Workout.builtIn == [.norwegian4x4, .hiit2020, .dailyStretch])
        #expect(Workout.builtIn.map(\.name) == ["Norwegian 4x4", "20/20 HIIT", "Daily Stretch"])
    }

    @Test func codeConstantsHaveDistinctIDs() {
        let ids = [Workout.norwegian4x4, .hiit2020, .audioCheck, .dailyStretch].map(\.id)
        #expect(Set(ids).count == 4)
    }

    @Test func codeConstantsKeepTheirIDs() {
        #expect([Workout.norwegian4x4, .hiit2020, .audioCheck, .dailyStretch].map(\.id.uuidString) == [
            "494E5456-4C43-4000-8000-000000000001",
            "494E5456-4C43-4000-8000-000000000002",
            "494E5456-4C43-4000-8000-000000000003",
            "494E5456-4C43-4000-8000-000000000004",
        ])
    }

    @Test func aForkKeepsEverythingButTheID() {
        let fork = Workout.dailyStretch.forked()
        #expect(fork.id != Workout.dailyStretch.id)
        #expect(fork.name == "Daily Stretch")
        #expect(fork.plan == Workout.dailyStretch.plan)
        #expect(fork.forked().id != fork.id)
    }

    @Test(arguments: [-1, 0, 86_401])
    func spanRejects(seconds: Int) {
        #expect(Span(seconds: seconds) == nil)
    }

    @Test(arguments: [1, 240, 86_400])
    func spanAccepts(seconds: Int) {
        #expect(Span(seconds: seconds)?.seconds == seconds)
    }

    @Test func spanFromMinutesAndSeconds() {
        #expect(Span(minutes: 4, seconds: 30)?.seconds == 270)
        #expect(Span(minutes: 0, seconds: 0) == nil)
    }

    @Test func spansOrderByLength() throws {
        let short = try #require(Span(seconds: 20))
        let long = try #require(Span(minutes: 1, seconds: 0))
        #expect(short < long)
    }

    @Test(arguments: [-3, 0, 100])
    func countRejects(value: Int) {
        #expect(Count(value) == nil)
    }

    @Test(arguments: [1, 99])
    func countAccepts(value: Int) {
        #expect(Count(value)?.value == value)
    }

    @Test func scalarsAreBareIntegersInJSON() throws {
        let span = try #require(Span(seconds: 240))
        let count = try #require(Count(4))
        #expect(String(decoding: try JSONEncoder().encode([span]), as: UTF8.self) == "[240]")
        #expect(String(decoding: try JSONEncoder().encode([count]), as: UTF8.self) == "[4]")
        #expect(try JSONDecoder().decode([Span].self, from: Data("[240]".utf8)) == [span])
        #expect(try JSONDecoder().decode([Count].self, from: Data("[4]".utf8)) == [count])
    }

    @Test(arguments: ["[0]", "[86401]", "[-5]", "[1.5]", "[\"240\"]"])
    func spanRejectsJSON(_ json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([Span].self, from: Data(json.utf8))
        }
    }

    @Test(arguments: ["[0]", "[100]"])
    func countRejectsJSON(_ json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([Count].self, from: Data(json.utf8))
        }
    }

    @Test func theOutlineListsEveryPhaseInOrder() {
        let outline = Workout.audioCheck.outline
        #expect(outline.map { describe($0.phase) } == ["warmUp", "work 1/2", "rest 1/2", "work 2/2"])
        #expect(outline.map(\.duration) == [30, 10, 10, 10])
        #expect(Workout.norwegian4x4.outline.count == 10)
    }
}
