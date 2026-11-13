import Foundation
import IntervalCore
import Testing

private func libraryJSON(version: Int = 2, workouts: String) -> Data {
    Data(#"{"version": \#(version), "cues": {"countdown": 3, "voice": true}, "workouts": [\#(workouts)]}"#.utf8)
}

private func timerJSON(_ fields: String) -> String {
    #"""
    {"id": "0B8E7C52-6A1D-4F0E-9B33-5D2C4A7E9F10", "name": "Hills",
     "intervals": {"restAfterLastRound": true, \#(fields)}}
    """#
}

private let pigeonJSON = #"""
    {"id": "5A0C1D2E-3F40-4152-8364-758697A8B9C0", "name": "Pigeon",
     "amount": {"hold": 45}, "sides": "each", "howTo": "https://youtu.be/lqCqETr7Q0g"}
    """#

private func routineJSON(getReady: Int = 10, switchSides: Int = 5, stretches: String = pigeonJSON) -> String {
    #"""
    {"id": "9C1B2A3D-4E5F-4061-8273-8495A6B7C8D9", "name": "Evening",
     "routine": {"getReady": \#(getReady), "switchSides": \#(switchSides), "stretches": [\#(stretches)]}}
    """#
}

private func stretchJSON(name: String = "Pigeon", amount: String = #"{"hold": 45}"#, sides: String = "each",
                         howTo: String? = nil) -> String {
    let link = howTo.map { #", "howTo": "\#($0)""# } ?? ""
    return #"""
        {"id": "5A0C1D2E-3F40-4152-8364-758697A8B9C0", "name": "\#(name)",
         "amount": \#(amount), "sides": "\#(sides)"\#(link)}
        """#
}

struct LibraryTests {
    @Test func aNewLibraryIsEmptyWithDefaultCues() {
        let library = Library()
        #expect(library.workouts.isEmpty)
        #expect(library.cues == CuePreferences(countdown: .three, voice: true))
    }

    @Test func roundTripsThroughJSON() throws {
        var library = Library()
        library.cues = CuePreferences(countdown: .five, voice: false)
        library.save(try timer(warmUp: 600, work: 90, rest: 60, rounds: 8, coolDown: 300))
        library.save(try routine(getReady: 12, switchSides: 4, [
            try stretch("Cat-Cow", try reps(10)),
            try stretch("Pigeon", try hold(45), .each, howTo: "https://youtu.be/lqCqETr7Q0g"),
        ]))
        library.save(try timer(work: 20, rest: 10, rounds: 8, restAfterLastRound: false))
        library.save(.dailyStretch)

        let reloaded = try Library(json: try library.json())
        #expect(reloaded == library)
        #expect(reloaded.workouts.count == 4)
    }

    /// App version 1.1 wrote this file. It paced reps, so its rep amount carries an `every` value.
    @Test func decodesAFileWrittenByAppVersionOnePointOne() throws {
        let json = Data("""
            {
              "version": 2,
              "cues": { "countdown": 5, "voice": false },
              "workouts": [
                {
                  "id": "0B8E7C52-6A1D-4F0E-9B33-5D2C4A7E9F10",
                  "name": "Hills",
                  "intervals": {
                    "warmUp": 600, "work": 90, "rest": 60, "rounds": 8, "coolDown": 300,
                    "restAfterLastRound": true
                  }
                },
                {
                  "id": "9C1B2A3D-4E5F-4061-8273-8495A6B7C8D9",
                  "name": "Evening",
                  "routine": {
                    "getReady": 10,
                    "switchSides": 5,
                    "stretches": [
                      {
                        "id": "5A0C1D2E-3F40-4152-8364-758697A8B9C0",
                        "name": "  Pigeon ",
                        "amount": { "hold": 45 },
                        "sides": "each",
                        "howTo": "https://youtu.be/lqCqETr7Q0g"
                      },
                      {
                        "id": "6B1D2E3F-4051-4263-9475-8697A8B9C0D1",
                        "name": "Cat-Cow",
                        "amount": { "reps": 10, "every": 5 },
                        "sides": "once"
                      }
                    ]
                  }
                },
                {
                  "id": "7D4F2A91-3C5E-4B6A-8F01-9E2D3C4B5A6F",
                  "name": "Tabata",
                  "intervals": { "work": 20, "rest": 10, "rounds": 8, "restAfterLastRound": false }
                }
              ]
            }
            """.utf8)

        let library = try Library(json: json)
        #expect(library.cues == CuePreferences(countdown: .five, voice: false))
        try #require(library.workouts.count == 3)

        let hills = library.workouts[0]
        #expect(hills.id == UUID(uuidString: "0B8E7C52-6A1D-4F0E-9B33-5D2C4A7E9F10"))
        #expect(hills.name == "Hills")
        #expect(hills.plan == .intervals(Intervals(
            warmUp: try span(600), work: try span(90), rest: try span(60),
            rounds: try count(8), coolDown: try span(300), restAfterLastRound: true)))

        let evening = library.workouts[1]
        #expect(evening.id == UUID(uuidString: "9C1B2A3D-4E5F-4061-8273-8495A6B7C8D9"))
        #expect(evening.name == "Evening")
        guard case .routine(let routine) = evening.plan else {
            Issue.record("expected a routine, got \(evening.plan)")
            return
        }
        #expect(routine.getReady.seconds == 10)
        #expect(routine.switchSides.seconds == 5)
        try #require(routine.stretches.count == 2)
        let pigeon = routine.stretches[0]
        #expect(pigeon.id == UUID(uuidString: "5A0C1D2E-3F40-4152-8364-758697A8B9C0"))
        #expect(pigeon.name == "Pigeon")
        #expect(pigeon.amount == (try hold(45)))
        #expect(pigeon.sides == .each)
        #expect(pigeon.howTo == URL(string: "https://youtu.be/lqCqETr7Q0g"))
        let catCow = routine.stretches[1]
        #expect(catCow.name == "Cat-Cow")
        #expect(catCow.amount == (try reps(10)))
        #expect(catCow.sides == .once)
        #expect(catCow.howTo == nil)
        #expect(evening.totalDuration == 115)

        let tabata = library.workouts[2]
        #expect(tabata.name == "Tabata")
        #expect(tabata.plan == .intervals(Intervals(
            warmUp: nil, work: try span(20), rest: try span(10),
            rounds: try count(8), coolDown: nil, restAfterLastRound: false)))
    }

    @Test func thePlanKeyNamesTheKindInTheFile() throws {
        var library = Library()
        library.save(try timer(work: 30))
        library.save(try routine([
            try stretch("Pigeon", try hold(45), .each, howTo: "https://youtu.be/lqCqETr7Q0g"),
            try stretch("Cat-Cow", try reps(10)),
        ]))

        let file = try #require(try JSONSerialization.jsonObject(with: try library.json()) as? [String: Any])
        #expect(file["version"] as? Int == 2)
        let workouts = try #require(file["workouts"] as? [[String: Any]])
        try #require(workouts.count == 2)
        #expect(Set(workouts[0].keys) == ["id", "name", "intervals"])
        #expect(Set(workouts[1].keys) == ["id", "name", "routine"])

        let routine = try #require(workouts[1]["routine"] as? [String: Any])
        #expect(routine["getReady"] as? Int == 10)
        #expect(routine["switchSides"] as? Int == 5)
        let stretches = try #require(routine["stretches"] as? [[String: Any]])
        try #require(stretches.count == 2)
        #expect(stretches[0]["name"] as? String == "Pigeon")
        #expect(stretches[0]["amount"] as? [String: Int] == ["hold": 45])
        #expect(stretches[0]["sides"] as? String == "each")
        #expect(stretches[0]["howTo"] as? String == "https://youtu.be/lqCqETr7Q0g")
        #expect(stretches[1]["amount"] as? [String: Int] == ["reps": 10])
        #expect(stretches[1]["sides"] as? String == "once")
        #expect(stretches[1]["howTo"] == nil)
    }

    @Test func aVersionOneFileThrows() {
        let json = Data("""
            {
              "version": 1,
              "cues": { "countdown": 5, "voice": false },
              "timers": [
                {
                  "id": "0B8E7C52-6A1D-4F0E-9B33-5D2C4A7E9F10",
                  "name": "Hills",
                  "warmUp": 600, "work": 90, "rest": 60, "rounds": 8, "coolDown": 300,
                  "restAfterLastRound": true
                }
              ]
            }
            """.utf8)
        #expect(throws: DecodingError.self) { try Library(json: json) }
    }

    @Test func anUnknownVersionThrows() {
        let workouts = timerJSON(#""work": 90, "rounds": 8"#)
        #expect(throws: Never.self) { try Library(json: libraryJSON(version: 2, workouts: workouts)) }
        #expect(throws: DecodingError.self) { try Library(json: libraryJSON(version: 1, workouts: workouts)) }
        #expect(throws: DecodingError.self) { try Library(json: libraryJSON(version: 3, workouts: workouts)) }
        #expect(throws: DecodingError.self) { try Library(json: libraryJSON(version: 0, workouts: workouts)) }
    }

    @Test func aFileWithoutAVersionThrows() {
        #expect(throws: (any Error).self) {
            try Library(json: Data(#"{"cues": {"countdown": 3, "voice": true}, "workouts": []}"#.utf8))
        }
    }

    @Test(arguments: [
        #""work": 0, "rounds": 8"#,
        #""work": 90, "rounds": 0"#,
        #""work": 90, "rounds": 100"#,
        #""work": 90, "rounds": 8, "warmUp": 0"#,
        #""work": 90, "rounds": 8, "rest": -10"#,
        #""work": 90, "rounds": 8, "coolDown": 86401"#,
        #""rounds": 8"#,
    ])
    func anInvalidTimerThrows(_ fields: String) {
        #expect(throws: (any Error).self) {
            try Library(json: libraryJSON(workouts: timerJSON(fields)))
        }
    }

    @Test func aRoutineWithTheShortestGapsDecodes() throws {
        let library = try Library(json: libraryJSON(workouts: routineJSON(getReady: 5, switchSides: 3)))
        #expect(library.workouts.map(\.totalDuration) == [98])
    }

    @Test(arguments: [
        stretchJSON(),
        stretchJSON(name: String(repeating: "a", count: 40)),
        stretchJSON(howTo: "http://example.com/pigeon"),
        stretchJSON(howTo: "HTTPS://example.com/pigeon"),
        stretchJSON(amount: #"{"reps": 99}"#, sides: "once"),
        stretchJSON(amount: #"{"reps": 1}"#),
        stretchJSON(amount: #"{"reps": 99, "every": 1}"#, sides: "once"),
    ])
    func aValidStretchDecodes(_ stretch: String) throws {
        let library = try Library(json: libraryJSON(workouts: routineJSON(stretches: stretch)))
        #expect(library.workouts.count == 1)
    }

    @Test(arguments: [
        routineJSON(getReady: 4),
        routineJSON(switchSides: 2),
        routineJSON(stretches: ""),
        routineJSON(stretches: Array(repeating: pigeonJSON, count: 100).joined(separator: ",")),
        routineJSON(stretches: stretchJSON(name: "")),
        routineJSON(stretches: stretchJSON(name: "   ")),
        routineJSON(stretches: stretchJSON(name: String(repeating: "a", count: 41))),
        routineJSON(stretches: stretchJSON(howTo: "ftp://example.com/pigeon")),
        routineJSON(stretches: stretchJSON(howTo: "youtu.be/lqCqETr7Q0g")),
        routineJSON(stretches: stretchJSON(howTo: "")),
        routineJSON(stretches: stretchJSON(amount: #"{"hold": 0}"#)),
        routineJSON(stretches: stretchJSON(amount: #"{"reps": 0}"#)),
        routineJSON(stretches: stretchJSON(amount: #"{"reps": 100}"#)),
        routineJSON(stretches: stretchJSON(amount: #"{"reps": 0, "every": 5}"#)),
        routineJSON(stretches: stretchJSON(amount: #"{"every": 5}"#)),
        routineJSON(stretches: stretchJSON(amount: #"{"reps": 10, "every": 5, "hold": 45}"#)),
        routineJSON(stretches: stretchJSON(amount: "{}")),
        routineJSON(stretches: stretchJSON(amount: "45")),
        routineJSON(stretches: stretchJSON(sides: "both")),
    ])
    func anInvalidRoutineThrows(_ workout: String) {
        #expect(throws: DecodingError.self) {
            try Library(json: libraryJSON(workouts: workout))
        }
    }

    @Test func aRepAmountFromVersionOnePointOneIsSavedAgainAsABareCount() throws {
        let old = try Library(json: libraryJSON(workouts: routineJSON(
            stretches: stretchJSON(amount: #"{"reps": 10, "every": 5}"#, sides: "once"))))
        #expect(old.workouts.first?.totalDuration == 10)

        let file = try #require(try JSONSerialization.jsonObject(with: try old.json()) as? [String: Any])
        let workouts = try #require(file["workouts"] as? [[String: Any]])
        let routine = try #require(workouts.first?["routine"] as? [String: Any])
        let stretches = try #require(routine["stretches"] as? [[String: Any]])
        #expect(stretches.first?["amount"] as? [String: Int] == ["reps": 10])
        #expect(try Library(json: try old.json()) == old)
    }

    @Test func ninetyNineStretchesDecode() throws {
        let stretches = Array(repeating: pigeonJSON, count: 99).joined(separator: ",")
        let library = try Library(json: libraryJSON(workouts: routineJSON(stretches: stretches)))
        #expect(library.workouts.first?.outline.count == 99 * 4)
    }

    @Test(arguments: [
        #"{"id": "0B8E7C52-6A1D-4F0E-9B33-5D2C4A7E9F10", "name": "Neither"}"#,
        #"""
        {"id": "0B8E7C52-6A1D-4F0E-9B33-5D2C4A7E9F10", "name": "Both",
         "intervals": {"work": 90, "rounds": 8, "restAfterLastRound": true},
         "routine": {"getReady": 10, "switchSides": 5, "stretches": [\#(pigeonJSON)]}}
        """#,
    ])
    func aWorkoutNeedsExactlyOnePlan(_ workout: String) {
        #expect(throws: DecodingError.self) {
            try Library(json: libraryJSON(workouts: workout))
        }
    }

    @Test func anUnknownCountdownThrows() {
        #expect(throws: (any Error).self) {
            try Library(json: Data(#"{"version": 2, "cues": {"countdown": 4, "voice": true}, "workouts": []}"#.utf8))
        }
    }

    @Test func saveAppendsNewWorkoutsInOrder() throws {
        var library = Library()
        let first = try timer(work: 30)
        let second = try routine([try stretch("Cobra", try hold(30))])
        #expect(library.save(first) == first)
        library.save(second)
        #expect(library.workouts == [first, second])
    }

    @Test func saveReplacesByIDInPlace() throws {
        var library = Library()
        let first = try timer(work: 30)
        let second = try timer(work: 60)
        library.save(first)
        library.save(second)

        var edited = try editing(first) { $0.work = try span(45) }
        edited.name = "Renamed"
        library.save(edited)

        #expect(library.workouts == [edited, second])
    }

    @Test func savingABuiltInForksItUnderAFreshID() throws {
        var library = Library()
        var tweaked = try editing(.norwegian4x4) { $0.rounds = try count(5) }
        tweaked.name = "My 4x4"

        let fork = library.save(tweaked)

        #expect(fork.id != Workout.norwegian4x4.id)
        #expect(!Workout.builtIn.map(\.id).contains(fork.id))
        #expect(fork.name == "My 4x4")
        #expect(fork.plan == tweaked.plan)
        #expect(fork.totalDuration == 2700)
        #expect(library.workouts == [fork])

        var renamed = fork
        renamed.name = "Mine"
        library.save(renamed)
        #expect(library.workouts == [renamed])
    }

    @Test func savingDailyStretchForksItWithTheSamePlan() {
        var library = Library()
        var mine = Workout.dailyStretch
        mine.name = "My stretches"

        let fork = library.save(mine)

        #expect(fork.id != Workout.dailyStretch.id)
        #expect(!Workout.builtIn.map(\.id).contains(fork.id))
        #expect(fork.name == "My stretches")
        #expect(fork.plan == Workout.dailyStretch.plan)
        #expect(fork.totalDuration == 595)
        #expect(library.workouts == [fork])

        let second = library.save(.dailyStretch)
        #expect(second.id != fork.id)
        #expect(library.workouts == [fork, second])
    }

    @Test func deleteRemovesByID() throws {
        var library = Library()
        let first = try timer(work: 30)
        let second = try timer(work: 60)
        library.save(first)
        library.save(second)

        library.delete(first.id)
        #expect(library.workouts == [second])

        library.delete(first.id)
        #expect(library.workouts == [second])
    }
}
