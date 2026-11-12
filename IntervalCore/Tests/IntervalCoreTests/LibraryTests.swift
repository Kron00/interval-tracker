import Foundation
import IntervalCore
import Testing

private func libraryJSON(version: Int = 1, timers: String) -> Data {
    Data(#"{"version": \#(version), "cues": {"countdown": 3, "voice": true}, "timers": [\#(timers)]}"#.utf8)
}

private func timerJSON(_ fields: String) -> String {
    #"{"id": "0B8E7C52-6A1D-4F0E-9B33-5D2C4A7E9F10", "name": "Hills", "restAfterLastRound": true, \#(fields)}"#
}

struct LibraryTests {
    @Test func aNewLibraryIsEmptyWithDefaultCues() {
        let library = Library()
        #expect(library.timers.isEmpty)
        #expect(library.cues == CuePreferences(countdown: .three, voice: true))
    }

    @Test func roundTripsThroughJSON() throws {
        var library = Library()
        library.cues = CuePreferences(countdown: .five, voice: false)
        library.save(try timer(warmUp: 600, work: 90, rest: 60, rounds: 8, coolDown: 300))
        library.save(try timer(work: 20, rest: 10, rounds: 8, restAfterLastRound: false))

        #expect(try Library(json: try library.json()) == library)
    }

    @Test func decodesAVersionOneFile() throws {
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
                },
                {
                  "id": "7D4F2A91-3C5E-4B6A-8F01-9E2D3C4B5A6F",
                  "name": "Tabata",
                  "work": 20, "rest": 10, "rounds": 8, "restAfterLastRound": false
                }
              ]
            }
            """.utf8)

        let library = try Library(json: json)
        #expect(library.cues == CuePreferences(countdown: .five, voice: false))
        try #require(library.timers.count == 2)

        let hills = library.timers[0]
        #expect(hills.id == UUID(uuidString: "0B8E7C52-6A1D-4F0E-9B33-5D2C4A7E9F10"))
        #expect(hills.name == "Hills")
        #expect(hills.warmUp?.seconds == 600)
        #expect(hills.work.seconds == 90)
        #expect(hills.rest?.seconds == 60)
        #expect(hills.rounds.value == 8)
        #expect(hills.coolDown?.seconds == 300)

        let tabata = library.timers[1]
        #expect(tabata.name == "Tabata")
        #expect(tabata.warmUp == nil)
        #expect(tabata.coolDown == nil)
        #expect(!tabata.restAfterLastRound)
    }

    @Test func anUnknownVersionThrows() {
        let timers = timerJSON(#""work": 90, "rounds": 8"#)
        #expect(throws: Never.self) { try Library(json: libraryJSON(version: 1, timers: timers)) }
        #expect(throws: (any Error).self) { try Library(json: libraryJSON(version: 2, timers: timers)) }
        #expect(throws: (any Error).self) { try Library(json: libraryJSON(version: 0, timers: timers)) }
    }

    @Test func aFileWithoutAVersionThrows() {
        #expect(throws: (any Error).self) {
            try Library(json: Data(#"{"cues": {"countdown": 3, "voice": true}, "timers": []}"#.utf8))
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
            try Library(json: libraryJSON(timers: timerJSON(fields)))
        }
    }

    @Test func anUnknownCountdownThrows() {
        #expect(throws: (any Error).self) {
            try Library(json: Data(#"{"version": 1, "cues": {"countdown": 4, "voice": true}, "timers": []}"#.utf8))
        }
    }

    @Test func saveAppendsNewTimersInOrder() throws {
        var library = Library()
        let first = try timer(work: 30)
        let second = try timer(work: 60)
        #expect(library.save(first) == first)
        library.save(second)
        #expect(library.timers == [first, second])
    }

    @Test func saveReplacesByIDInPlace() throws {
        var library = Library()
        let first = try timer(work: 30)
        let second = try timer(work: 60)
        library.save(first)
        library.save(second)

        var edited = first
        edited.name = "Renamed"
        edited.work = try #require(Span(seconds: 45))
        library.save(edited)

        #expect(library.timers == [edited, second])
    }

    @Test func savingABuiltInForksItUnderAFreshID() throws {
        var library = Library()
        var tweaked = TimerDefinition.norwegian4x4
        tweaked.name = "My 4x4"
        tweaked.rounds = try #require(RoundCount(5))

        let fork = library.save(tweaked)

        #expect(fork.id != TimerDefinition.norwegian4x4.id)
        #expect(!TimerDefinition.builtIn.map(\.id).contains(fork.id))
        #expect(fork.name == "My 4x4")
        #expect(fork.rounds.value == 5)
        #expect(fork.totalDuration == 2700)
        #expect(library.timers == [fork])

        var renamed = fork
        renamed.name = "Mine"
        library.save(renamed)
        #expect(library.timers == [renamed])
    }

    @Test func deleteRemovesByID() throws {
        var library = Library()
        let first = try timer(work: 30)
        let second = try timer(work: 60)
        library.save(first)
        library.save(second)

        library.delete(first.id)
        #expect(library.timers == [second])

        library.delete(first.id)
        #expect(library.timers == [second])
    }
}
