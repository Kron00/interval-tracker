import Foundation
import IntervalCore
import Testing

struct TimerDefinitionTests {
    @Test func presetTotals() {
        #expect(TimerDefinition.norwegian4x4.totalDuration == 2280)
        #expect(TimerDefinition.hiit2020.totalDuration == 840)
        #expect(TimerDefinition.audioCheck.totalDuration == 60)
    }

    @Test func presetsWithoutTheRestAfterTheLastRound() {
        var rower = TimerDefinition.norwegian4x4
        rower.restAfterLastRound = false
        #expect(rower.totalDuration == 2100)

        var bike = TimerDefinition.hiit2020
        bike.restAfterLastRound = false
        #expect(bike.totalDuration == 820)
    }

    @Test func builtInsAreTheTwoPresets() {
        #expect(TimerDefinition.builtIn == [.norwegian4x4, .hiit2020])
        #expect(TimerDefinition.builtIn.map(\.name) == ["Norwegian 4x4", "20/20 HIIT"])
    }

    @Test func codeConstantsHaveDistinctIDs() {
        let ids = [TimerDefinition.norwegian4x4, .hiit2020, .audioCheck].map(\.id)
        #expect(Set(ids).count == 3)
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
    func roundCountRejects(value: Int) {
        #expect(RoundCount(value) == nil)
    }

    @Test(arguments: [1, 99])
    func roundCountAccepts(value: Int) {
        #expect(RoundCount(value)?.value == value)
    }

    @Test func scalarsAreBareIntegersInJSON() throws {
        let span = try #require(Span(seconds: 240))
        let count = try #require(RoundCount(4))
        #expect(String(decoding: try JSONEncoder().encode([span]), as: UTF8.self) == "[240]")
        #expect(String(decoding: try JSONEncoder().encode([count]), as: UTF8.self) == "[4]")
        #expect(try JSONDecoder().decode([Span].self, from: Data("[240]".utf8)) == [span])
        #expect(try JSONDecoder().decode([RoundCount].self, from: Data("[4]".utf8)) == [count])
    }

    @Test(arguments: ["[0]", "[86401]", "[-5]", "[1.5]", "[\"240\"]"])
    func spanRejectsJSON(_ json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([Span].self, from: Data(json.utf8))
        }
    }

    @Test(arguments: ["[0]", "[100]"])
    func roundCountRejectsJSON(_ json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([RoundCount].self, from: Data(json.utf8))
        }
    }
}
