import Foundation
import IntervalCore
import Testing

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func maximum(_ value: Int) throws -> MaxHeartRate {
    try #require(MaxHeartRate(value))
}

/// Readings at seconds after `start`.
private func readings(_ beats: [(second: TimeInterval, bpm: Int)]) throws -> [HeartRateReading] {
    try beats.map { try #require(HeartRateReading(bpm: $0.bpm, at: start + $0.second)) }
}

private func summary(_ beats: [(second: TimeInterval, bpm: Int)], max value: Int = 200) throws -> HeartRateSummary {
    try #require(HeartRateSummary(try readings(beats), maxHeartRate: try maximum(value), startedAt: start))
}

struct HeartRateTests {
    @Test func eachZoneBeginsAtItsShareOfTheMaximum() throws {
        let max200 = try maximum(200)
        #expect(max200.zone(of: 99) == .belowOne)
        #expect(max200.zone(of: 100) == .one, "50%")
        #expect(max200.zone(of: 119) == .one)
        #expect(max200.zone(of: 120) == .two, "60%")
        #expect(max200.zone(of: 139) == .two)
        #expect(max200.zone(of: 140) == .three, "70%")
        #expect(max200.zone(of: 159) == .three)
        #expect(max200.zone(of: 160) == .four, "80%")
        #expect(max200.zone(of: 179) == .four)
        #expect(max200.zone(of: 180) == .five, "90%")
        #expect(max200.zone(of: 250) == .five, "above the maximum is still zone 5")

        // 50% of 187 is 93.5, so zone 1 begins at 94.
        let max187 = try maximum(187)
        #expect(max187.zone(of: 93) == .belowOne)
        #expect(max187.zone(of: 94) == .one)
        #expect(max187.floor(of: .one) == 94)
        #expect(max187.floor(of: .five) == 169, "90% of 187 is 168.3")

        let standard = MaxHeartRate.standard
        #expect(standard.value == 190)
        #expect(HeartRateZone.allCases.map(standard.floor) == [0, 95, 114, 133, 152, 171])
        for zone in HeartRateZone.allCases.dropFirst() {
            #expect(standard.zone(of: standard.floor(of: zone)) == zone)
            #expect(standard.zone(of: standard.floor(of: zone) - 1) < zone)
        }
    }

    @Test func theMaximumHeartRateIsBetween120And220() {
        #expect(MaxHeartRate(119) == nil)
        #expect(MaxHeartRate(120)?.value == 120)
        #expect(MaxHeartRate(220)?.value == 220)
        #expect(MaxHeartRate(221) == nil)
    }

    @Test func aReadingIsBetween25And250AndFreshForFiveSeconds() throws {
        #expect(HeartRateReading(bpm: 0, at: start) == nil, "a strap that lost skin contact sends 0")
        #expect(HeartRateReading(bpm: 24, at: start) == nil)
        #expect(HeartRateReading(bpm: 25, at: start)?.bpm == 25)
        #expect(HeartRateReading(bpm: 250, at: start)?.bpm == 250)
        #expect(HeartRateReading(bpm: 251, at: start) == nil)

        let reading = try #require(HeartRateReading(bpm: 120, at: start))
        #expect(reading.isFresh(at: start + 5))
        #expect(!reading.isFresh(at: start + 5.01))
    }

    @Test func theSummaryHasTheAverageAndTheMaximum() throws {
        let summary = try summary([(0, 100), (1, 110), (2, 121), (3, 150)])
        #expect(summary.average == 120, "120.25 rounds to 120")
        #expect(summary.maximum == 150)
        #expect(summary.maxHeartRate.value == 200)
        #expect(HeartRateSummary([], maxHeartRate: .standard, startedAt: start) == nil, "no reading, no summary")
    }

    /// With a maximum of 200, zone 1 begins at 100, zone 2 at 120 and zone 3 at 140.
    @Test func timeInAZoneRunsFromOneReadingToTheNext() throws {
        let summary = try summary([(0, 90), (1, 105), (3, 125), (4, 125), (6.5, 145), (7, 105)])
        #expect(summary.seconds(in: .belowOne) == 1)
        #expect(summary.seconds(in: .one) == 2)
        #expect(summary.seconds(in: .two) == 3.5)
        #expect(summary.seconds(in: .three) == 0.5)
        #expect(summary.seconds(in: .four) == 0)
        #expect(summary.seconds(in: .five) == 0)
        #expect(summary.secondsInZone.reduce(0, +) == 7, "the last reading has no next one, so it adds nothing")
    }

    @Test func aGapOfMoreThanTenSecondsCountsForNothing() throws {
        let summary = try summary([(0, 125), (10, 125), (20.5, 145), (21, 145), (60, 105), (61, 105)])
        #expect(summary.seconds(in: .two) == 10, "a gap of exactly 10 seconds counts")
        #expect(summary.seconds(in: .three) == 0.5, "10.5 seconds to the next reading count for nothing")
        #expect(summary.seconds(in: .one) == 1, "39 seconds without a reading count for nothing, and the last reading adds nothing")
        #expect(summary.secondsInZone.reduce(0, +) == 11.5)
    }

    @Test func theTraceHasAtMostOnePointEveryFiveSeconds() throws {
        var beats: [(second: TimeInterval, bpm: Int)] = []
        for second in 0..<12 { beats.append((TimeInterval(second), 100 + second)) }
        beats.append((40.2, 150))
        let summary = try summary(beats)
        #expect(summary.trace == [
            HeartRateSummary.Point(second: 0, bpm: 102),
            HeartRateSummary.Point(second: 5, bpm: 107),
            HeartRateSummary.Point(second: 10, bpm: 111),
            HeartRateSummary.Point(second: 40, bpm: 150),
        ], "each point is the mean of its five seconds, and a gap leaves no point")
    }

    @Test func readingsInAnyOrderGiveTheSameSummary() throws {
        let beats: [(second: TimeInterval, bpm: Int)] = [(0, 100), (1, 130), (2, 150), (7, 120)]
        #expect(try summary(beats.reversed()) == summary(beats))
    }
}

struct HeartRateHistoryTests {
    private static func file(heartRate: String?) -> Data {
        let field = heartRate.map { #", "heartRate": \#($0)"# } ?? ""
        return Data("""
        {"version": 1, "records": [{"id": "11111111-2222-3333-4444-555555555555", "startedAt": 794793600,
         "workoutID": "494E5456-4C43-4000-8000-000000000001", "name": "Norwegian 4x4", "kind": "intervals",
         "worked": 2280, "planned": 2280, "outcome": "completed"\(field)}]}
        """.utf8)
    }

    private static let valid = """
        {"average": 142, "maximum": 171, "maxHeartRate": 190, "secondsInZone": [60, 120, 300, 900, 600, 300],
         "trace": [[0, 98], [5, 104], [10, 112]]}
        """

    @Test func aFileThatTheReleasedVersionWroteHasNoHeartRateAndLoads() throws {
        let history = try History(json: Self.file(heartRate: nil))
        #expect(history.records.count == 1)
        #expect(history.records.first?.heartRate == nil)
    }

    @Test func aRecordWithItsHeartRateReadsBackAsItWasWritten() throws {
        let heartRate = try summary([(0, 98), (1, 120), (2, 141), (6, 175), (13, 160)], max: 190)
        var history = History()
        history.add(WorkoutRecord(startedAt: start, workoutID: Workout.norwegian4x4.id, name: "Norwegian 4x4",
                                  kind: .intervals, worked: 2280, planned: 2280, outcome: .completed, heartRate: heartRate))
        let json = try history.json()
        #expect(try History(json: json) == history)
        #expect(try History(json: json).records.first?.heartRate?.maxHeartRate.value == 190)

        let written = try #require(String(data: json, encoding: .utf8))
        #expect(!written.contains("\"second\""), "a point of the graph is a pair of numbers, not an object")
    }

    @Test func aFileWithItsHeartRateWrittenByHandLoads() throws {
        let heartRate = try #require(try History(json: Self.file(heartRate: Self.valid)).records.first?.heartRate)
        #expect(heartRate.average == 142)
        #expect(heartRate.maximum == 171)
        #expect(heartRate.seconds(in: .three) == 900)
        #expect(heartRate.trace.last == HeartRateSummary.Point(second: 10, bpm: 112))
    }

    @Test func aDamagedHeartRateRefusesTheFile() {
        func damaged(_ from: String, _ to: String) -> Data {
            Self.file(heartRate: Self.valid.replacingOccurrences(of: from, with: to))
        }
        #expect(throws: DecodingError.self) { try History(json: damaged("\"average\": 142", "\"average\": 0")) }
        #expect(throws: DecodingError.self) { try History(json: damaged("\"maximum\": 171", "\"maximum\": 999")) }
        #expect(throws: DecodingError.self) { try History(json: damaged("\"maximum\": 171", "\"maximum\": 130")) }
        #expect(throws: DecodingError.self) { try History(json: damaged("\"maxHeartRate\": 190", "\"maxHeartRate\": 300")) }
        #expect(throws: DecodingError.self) { try History(json: damaged("[60, 120, 300, 900, 600, 300]", "[60, 120, 300, 900, 600]")) }
        #expect(throws: DecodingError.self) { try History(json: damaged("[60, 120,", "[-60, 120,")) }
        #expect(throws: DecodingError.self) { try History(json: damaged("[60, 120,", "[1e100, 120,")) }
        #expect(throws: DecodingError.self) { try History(json: damaged("[5, 104]", "[5, 4]")) }
        #expect(throws: DecodingError.self) { try History(json: damaged("[5, 104]", "[-5, 104]")) }
        #expect(throws: DecodingError.self) { try History(json: damaged("[5, 104]", "[5]")) }
        #expect(throws: DecodingError.self) { try History(json: damaged("\"trace\"", "\"graph\"")) }
    }
}
