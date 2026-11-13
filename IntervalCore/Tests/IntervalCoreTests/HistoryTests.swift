import Foundation
import IntervalCore
import Testing

private func calendar(utcOffsetHours: Int = 0, weekStartsOn firstWeekday: Int = 2) throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: utcOffsetHours * 3600))
    calendar.firstWeekday = firstWeekday
    return calendar
}

/// A moment in March 2026, in UTC. The 1st, the 8th and the 15th are Sundays.
private func march(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) throws -> Date {
    let parts = DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute)
    return try #require(try calendar().date(from: parts))
}

private func record(_ name: String = "Test", at start: Date, worked: TimeInterval = 600,
                    _ outcome: WorkoutRecord.Outcome = .completed) -> WorkoutRecord {
    WorkoutRecord(startedAt: start, workoutID: Workout.norwegian4x4.id, name: name, kind: .intervals,
                  worked: worked, planned: 2280, outcome: outcome)
}

private func history(_ records: [WorkoutRecord]) -> History {
    var history = History()
    for record in records { history.add(record) }
    return history
}

struct HistoryTests {
    @Test func theNewestRunComesFirstWhateverTheOrderOfAdding() throws {
        let history = history([
            record("Second", at: try march(10)),
            record("Newest", at: try march(12)),
            record("Oldest", at: try march(9)),
            record("Third", at: try march(10, 7)),
        ])
        #expect(history.records.map(\.name) == ["Newest", "Second", "Third", "Oldest"])
    }

    @Test func aRunEndedEarlyIsKeptOnlyAfterSixtySecondsOfWork() throws {
        let history = history([
            record("59 s", at: try march(9), worked: 59.9, .endedEarly),
            record("60 s", at: try march(10), worked: 60, .endedEarly),
            record("Skipped to the end", at: try march(11), worked: 3, .completed),
        ])
        #expect(history.records.map(\.name) == ["Skipped to the end", "60 s"])
    }

    @Test func whatIsKeptCanBeAskedBeforeARunIsOver() {
        #expect(!History.keeps(.endedEarly, worked: 59.9))
        #expect(History.keeps(.endedEarly, worked: 60))
        #expect(History.keeps(.completed, worked: 3))
    }

    @Test func onlyTheNewestThousandAreKept() throws {
        let first = try march(1)
        var history = History()
        for hour in 0...1004 {
            history.add(record("Run \(hour)", at: first + TimeInterval(hour) * 3600))
        }
        #expect(history.records.count == 1000)
        #expect(history.records.first?.name == "Run 1004")
        #expect(history.records.last?.name == "Run 5")

        history.add(record("Older than all of them", at: first - 3600))
        #expect(history.records.count == 1000)
        #expect(history.records.last?.name == "Run 5")
    }

    @Test func aDayIsADayInTheCalendarOfTheUser() throws {
        let lateEvening = record("Late", at: try march(10, 23, 30))
        let afterMidnight = record("Early", at: try march(11, 0, 30))
        let history = history([lateEvening, afterMidnight, record("Before", at: try march(9, 8))])

        let inUTC = history.days(in: try calendar())
        #expect(inUTC.map(\.date) == [try march(11, 0), try march(10, 0), try march(9, 0)])
        #expect(inUTC.map { $0.records.map(\.name) } == [["Early"], ["Late"], ["Before"]])

        let twoHoursEast = history.days(in: try calendar(utcOffsetHours: 2))
        #expect(twoHoursEast.map(\.date) == [try march(10, 22), try march(8, 22)])
        #expect(twoHoursEast.map { $0.records.map(\.name) } == [["Early", "Late"], ["Before"]])

        #expect(History().days(in: try calendar()).isEmpty)
    }

    @Test func theSummaryCoversTheWeekTheCalendarDefines() throws {
        let history = history([
            record(at: try march(7), worked: 2400),
            record(at: try march(8, 10), worked: 1200),
            record(at: try march(9), worked: 600, .endedEarly),
            record(at: try march(11, 8), worked: 1800),
            record(at: try march(15, 0), worked: 300),
        ])
        let wednesday = try march(11)

        let mondayFirst = history.summary(ofWeekContaining: wednesday, in: try calendar(weekStartsOn: 2))
        #expect(mondayFirst.workouts == 3)
        #expect(mondayFirst.worked == 600 + 1800 + 300)

        let sundayFirst = history.summary(ofWeekContaining: wednesday, in: try calendar(weekStartsOn: 1))
        #expect(sundayFirst.workouts == 3)
        #expect(sundayFirst.worked == 1200 + 600 + 1800, "the next Sunday begins the next week, at midnight exactly")

        let nothing = History().summary(ofWeekContaining: wednesday, in: try calendar())
        #expect(nothing.workouts == 0)
        #expect(nothing.worked == 0)
    }

    @Test func deleteRemovesOneEntryAndClearRemovesThemAll() throws {
        let kept = record("Kept", at: try march(10))
        let deleted = record("Deleted", at: try march(11))
        var history = history([kept, deleted])

        history.delete(deleted.id)
        #expect(history.records == [kept])

        history.clear()
        #expect(history.records.isEmpty)
        #expect(history == History())
    }

    @Test func jsonRoundTrip() throws {
        let history = history([
            record("Norwegian 4x4", at: try march(10) + 0.123456, worked: 1234.5678),
            WorkoutRecord(startedAt: try march(11), workoutID: Workout.dailyStretch.id, name: "Daily Stretch",
                          kind: .routine, worked: 312.25, planned: 501, outcome: .endedEarly),
        ])
        #expect(try History(json: history.json()) == history)
        #expect(try History(json: History().json()) == History())
    }

    @Test func readsAFileThatVersionOneWrote() throws {
        let json = """
        {"version": 1, "records": [
          {"id": "11111111-2222-3333-4444-555555555555", "startedAt": 794793600, "workoutID": "494E5456-4C43-4000-8000-000000000004",
           "name": "Daily Stretch", "kind": "routine", "worked": 312.5, "planned": 501, "outcome": "endedEarly"},
          {"id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", "startedAt": 794880000, "workoutID": "494E5456-4C43-4000-8000-000000000001",
           "name": "Norwegian 4x4", "kind": "intervals", "worked": 2280, "planned": 2280, "outcome": "completed"}
        ]}
        """
        let history = try History(json: Data(json.utf8))
        #expect(history.records == [
            WorkoutRecord(id: try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")),
                          startedAt: try march(11, 0), workoutID: Workout.norwegian4x4.id, name: "Norwegian 4x4",
                          kind: .intervals, worked: 2280, planned: 2280, outcome: .completed),
            WorkoutRecord(id: try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555")),
                          startedAt: try march(10, 0), workoutID: Workout.dailyStretch.id, name: "Daily Stretch",
                          kind: .routine, worked: 312.5, planned: 501, outcome: .endedEarly),
        ])
    }

    @Test func aFileWithANumberThatIsNoLengthOrNoDateIsRefused() {
        func file(worked: String = "600", planned: String = "600", startedAt: String = "794793600") -> Data {
            Data("""
            {"version": 1, "records": [{"id": "11111111-2222-3333-4444-555555555555", "startedAt": \(startedAt),
             "workoutID": "494E5456-4C43-4000-8000-000000000004", "name": "Daily Stretch", "kind": "routine",
             "worked": \(worked), "planned": \(planned), "outcome": "completed"}]}
            """.utf8)
        }
        #expect((try? History(json: file()))?.records.count == 1)
        // The screen turns a length into whole seconds, and a number this large has none.
        #expect(throws: DecodingError.self) { try History(json: file(worked: "1e100")) }
        #expect(throws: DecodingError.self) { try History(json: file(worked: "-1")) }
        #expect(throws: DecodingError.self) { try History(json: file(planned: "1e100")) }
        #expect(throws: DecodingError.self) { try History(json: file(planned: "-1")) }
        #expect(throws: DecodingError.self) { try History(json: file(startedAt: "1e300")) }
        #expect(throws: DecodingError.self) { try History(json: file(startedAt: "-1")) }
    }

    @Test func aRunIsNeverRecordedAsLongerThanAWeek() throws {
        let record = WorkoutRecord(startedAt: try march(10, 0), workoutID: Workout.dailyStretch.id, name: "Daily Stretch",
                                   kind: .routine, worked: 30 * 24 * 3600, planned: -5, outcome: .endedEarly)
        #expect(record.worked == 7 * 24 * 3600)
        #expect(record.planned == 0)
        var history = History()
        history.add(record)
        #expect(try History(json: try history.json()) == history, "what the app writes, it reads back")
    }

    @Test func anUnknownVersionThrows() {
        #expect(throws: DecodingError.self) {
            try History(json: Data(#"{"version": 2, "records": []}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try History(json: Data(#"{"records": []}"#.utf8))
        }
    }
}

struct WorkoutRecordTests {
    @Test func aFinishedRunIsCompletedWithTheTimeTheFinishScreenShows() throws {
        var run = session()
        run.skip(try progress(run, at: 100).segment, at: t0 + 100)
        let finish = t0 + 100 + 1980
        #expect(run.snapshot(at: finish) == .finished(worked: 2080))

        let record = WorkoutRecord(run, startedAt: t0, endedAt: finish + 30)
        #expect(record.outcome == .completed)
        #expect(record.worked == 2080)
        #expect(record.planned == 2280)
        #expect(record.startedAt == t0)
        #expect(record.workoutID == Workout.norwegian4x4.id)
        #expect(record.name == "Norwegian 4x4")
        #expect(record.kind == .intervals)
    }

    @Test func aRunEndedPartWayIsEndedEarlyWithTheTimeWorkedSoFar() throws {
        var run = session()
        #expect(WorkoutRecord(run, startedAt: t0, endedAt: t0 + 75).worked == 75)

        run.skip(try progress(run, at: 100).segment, at: t0 + 100)
        run.pause(at: t0 + 130)
        let record = WorkoutRecord(run, startedAt: t0, endedAt: t0 + 900)
        #expect(record.outcome == .endedEarly)
        #expect(record.worked == 130, "the skipped 200 s of warm-up and the paused time are not work")
        #expect(record.planned == 2280)

        run.resume(at: t0 + 900)
        run.restart(try progress(run, at: 910).segment, at: t0 + 910)
        #expect(WorkoutRecord(run, startedAt: t0, endedAt: t0 + 915).worked == 145, "the restarted 40 s count twice")
    }

    @Test func aRoutineCountsRepsInProgressAndNotAWaitForStart() throws {
        var run = session(try routine([try stretch("Cat-Cow", try reps(10)), try stretch("Cobra", try hold(30))]))
        #expect(run.worked(at: t0 + 40) == 40, "the reps are 40 s in")

        run.perform(.next, at: t0 + 40)
        #expect(run.worked(at: t0 + 100) == 40, "Cobra waits for Start")

        run.perform(.next, at: t0 + 100)
        let record = WorkoutRecord(run, startedAt: t0, endedAt: t0 + 110)
        #expect(record.worked == 50, "the count-in and 7 s of the hold")
        #expect(record.outcome == .endedEarly)
        #expect(record.kind == .routine)
        #expect(record.planned == 33)
    }
}
