import Foundation
import IntervalCore
import Testing

private let tabataJSON = #"""
    {"kind": "intervals", "name": "Bike Tabata", "note": null, "stretches": null,
     "intervals": {"warmUpSeconds": 300, "workSeconds": 20, "restSeconds": 10, "rounds": 8,
                   "coolDownSeconds": null, "restAfterLastRound": false}}
    """#

private let hipsJSON = #"""
    {"kind": "routine", "name": "Hip Mobility", "note": "I kept it to two stretches.", "intervals": null,
     "stretches": [
       {"name": "Leg Swings", "holdSeconds": null, "reps": 12, "eachSide": true},
       {"name": "Pigeon", "holdSeconds": 60, "reps": null, "eachSide": false}
     ]}
    """#

private func intervalsJSON(_ fields: String, name: String = "Hills") -> String {
    #"{"kind": "intervals", "name": "\#(name)", "intervals": {\#(fields)}}"#
}

private func routineJSON(_ stretches: String) -> String {
    #"{"kind": "routine", "name": "Evening", "stretches": [\#(stretches)]}"#
}

private func built(_ json: String) throws(BlueprintError) -> Workout {
    try WorkoutBlueprint(modelOutput: json).workout()
}

private func intervals(_ workout: Workout) throws -> Intervals {
    guard case .intervals(let intervals) = workout.plan else { throw NotAnIntervalTimer() }
    return intervals
}

private struct NotARoutine: Error {}

private func stretches(_ workout: Workout) throws -> [Stretch] {
    guard case .routine(let routine) = workout.plan else { throw NotARoutine() }
    return routine.stretches
}

private func failure(_ json: String) -> BlueprintError? {
    do {
        _ = try built(json)
        return nil
    } catch {
        return error
    }
}

struct BlueprintTests {
    @Test func anIntervalAnswerBecomesAnIntervalTimer() throws {
        let workout = try built(tabataJSON)
        #expect(workout.name == "Bike Tabata")
        #expect(try intervals(workout) == Intervals(
            warmUp: try span(300), work: try span(20), rest: try span(10), rounds: try count(8),
            coolDown: nil, restAfterLastRound: false))
        #expect(workout.totalDuration == 530, "5:00, then 8 × 0:20 with 7 rests of 0:10")
    }

    /// The third example in Describe a workout. One work length and one rest length can say it.
    @Test func aRunOfOneMinuteHardAndTwoEasyFillsItsThirtyMinutes() throws {
        let workout = try built(intervalsJSON(
            #""warmUpSeconds": null, "workSeconds": 60, "restSeconds": 120, "rounds": 10, "coolDownSeconds": null, "restAfterLastRound": true"#))
        #expect(workout.totalDuration == 30 * 60, "ten rounds of 1:00 and 2:00")
    }

    @Test func aRoutineAnswerBecomesAStretchRoutine() throws {
        let blueprint = try WorkoutBlueprint(modelOutput: hipsJSON)
        #expect(blueprint.note == "I kept it to two stretches.")
        let made = try stretches(blueprint.workout())
        #expect(made.map(\.name) == ["Leg Swings", "Pigeon"])
        #expect(made.map(\.amount) == [try reps(12), try hold(60)])
        #expect(made.map(\.sides) == [.each, .once])
        #expect(made.allSatisfy { $0.howTo == nil })
    }

    /// The model has no say over the count-in, even when it sends one.
    @Test func aGeneratedRoutineHasTheCountInOfANewRoutineInTheEditor() throws {
        let json = #"""
            {"kind": "routine", "name": "Evening", "countIn": 60, "getReady": 60,
             "stretches": [{"name": "Pigeon", "holdSeconds": 45, "eachSide": true, "countInSeconds": 60}]}
            """#
        guard case .routine(let routine) = try built(json).plan else { throw NotARoutine() }
        #expect(routine.countIn?.seconds == 3)
    }

    @Test func twoAnswersWithTheSameContentGetDifferentIDs() throws {
        #expect(try built(tabataJSON).id != built(tabataJSON).id)
    }

    @Test func anAnswerWrappedInACodeFenceIsRead() throws {
        let fenced = "Here is your workout:\n```json\n\(tabataJSON)\n```\nEnjoy."
        #expect(try built(fenced).name == "Bike Tabata")
    }

    @Test func aFieldLeftOutCountsAsNull() throws {
        let made = try intervals(built(intervalsJSON(#""workSeconds": 90, "rounds": 6"#)))
        #expect(made == Intervals(warmUp: nil, work: try span(90), rest: nil, rounds: try count(6), coolDown: nil))
    }

    @Test func numbersAboveALimitBecomeTheLimit() throws {
        let timer = try intervals(built(intervalsJSON(
            #""warmUpSeconds": 100000, "workSeconds": 90000, "restSeconds": 86401, "rounds": 500, "coolDownSeconds": 86400"#)))
        #expect([timer.warmUp, timer.work, timer.rest, timer.coolDown].map { $0?.seconds } == [86_400, 86_400, 86_400, 86_400])
        #expect(timer.rounds.value == 99)

        let made = try stretches(built(routineJSON(
            #"{"name": "Squat", "reps": 250}, {"name": "Plank", "holdSeconds": 999999}"#)))
        #expect(made.map(\.amount) == [try reps(99), try hold(86_400)])
    }

    @Test func aLengthOfZeroOrLessMeansThePhaseIsAbsent() throws {
        let timer = try intervals(built(intervalsJSON(
            #""warmUpSeconds": 0, "workSeconds": 30, "restSeconds": -5, "rounds": 3, "coolDownSeconds": 0"#)))
        #expect(timer == Intervals(warmUp: nil, work: try span(30), rest: nil, rounds: try count(3), coolDown: nil))
    }

    @Test func aWorkoutNameIsTrimmedAndCutToThirtyCharacters() throws {
        #expect(try built(intervalsJSON(#""workSeconds": 30, "rounds": 4"#, name: "  Hills  ")).name == "Hills")
        let long = String(repeating: "Hill sprints ", count: 400)
        // Thirty characters end after "Hill sprints Hill sprints Hill", and the cut leaves no space at the end.
        #expect(try built(intervalsJSON(#""workSeconds": 30, "rounds": 4"#, name: long)).name == "Hill sprints Hill sprints Hill")
        let name = try built(#"{"kind": "routine", "name": "\#(String(repeating: "x", count: 5000))", "stretches": [{"name": "Pigeon", "holdSeconds": 30}]}"#).name
        #expect(name.count == 30)
    }

    @Test func aStretchNameIsTrimmedAndCutToFortyCharacters() throws {
        let long = String(repeating: "Stretch ", count: 8)
        let made = try stretches(built(routineJSON(
            #"{"name": "  Pigeon \n", "holdSeconds": 30}, {"name": "\#(long)", "holdSeconds": 30}"#)))
        #expect(made[0].name == "Pigeon")
        #expect(made[1].name == "Stretch Stretch Stretch Stretch Stretch")
        #expect(made[1].name.count <= 40)
    }

    @Test func aRoutineKeepsItsFirstNinetyNineStretches() throws {
        let many = (1...120).map { #"{"name": "Stretch \#($0)", "holdSeconds": 30}"# }.joined(separator: ",")
        let made = try stretches(built(routineJSON(many)))
        #expect(made.count == 99)
        #expect(made.last?.name == "Stretch 99")
    }

    @Test func aStretchWithAHoldAndRepsIsCountedInReps() throws {
        let made = try stretches(built(routineJSON(#"{"name": "Bird Dog", "holdSeconds": 5, "reps": 10}"#)))
        #expect(made.map(\.amount) == [try reps(10)])
    }

    @Test func aZeroInTheUnusedAmountIsIgnored() throws {
        let made = try stretches(built(routineJSON(
            #"{"name": "Pigeon", "holdSeconds": 45, "reps": 0}, {"name": "Cat-Cow", "holdSeconds": 0, "reps": 10}"#)))
        #expect(made.map(\.amount) == [try hold(45), try reps(10)])
    }

    @Test func textThatIsNotTheAnswerIsUnreadable() {
        for text in ["", "I cannot help with that.", "{", "}{", #"{"kind": "yoga", "name": "Flow"}"#, #"{"name": "Flow"}"#, "[1, 2]"] {
            #expect(throws: BlueprintError.unreadable, "\(text)") { try WorkoutBlueprint(modelOutput: text) }
        }
    }

    @Test func anAnswerThatLeavesNothingToRunIsRejected() {
        #expect(failure(intervalsJSON(#""workSeconds": 30, "rounds": 4"#, name: "  ")) == .unnamed)
        #expect(failure(#"{"kind": "routine", "stretches": [{"name": "Pigeon", "holdSeconds": 30}]}"#) == .unnamed)
        #expect(failure(#"{"kind": "intervals", "name": "Hills", "stretches": [{"name": "Pigeon", "holdSeconds": 30}]}"#) == .noIntervals)
        #expect(failure(intervalsJSON(#""workSeconds": 0, "rounds": 4"#)) == .noWork)
        #expect(failure(intervalsJSON(#""rounds": 4"#)) == .noWork)
        #expect(failure(intervalsJSON(#""workSeconds": 30, "rounds": 0"#)) == .noRounds)
        #expect(failure(intervalsJSON(#""workSeconds": 30"#)) == .noRounds)
        #expect(failure(routineJSON("")) == .noStretches)
        #expect(failure(#"{"kind": "routine", "name": "Evening", "intervals": {"workSeconds": 30, "rounds": 4}}"#) == .noStretches)
        #expect(failure(routineJSON(#"{"name": "Pigeon", "holdSeconds": 30}, {"name": " ", "holdSeconds": 30}"#))
            == .stretchUnnamed(number: 2))
        #expect(failure(routineJSON(#"{"name": "Pigeon", "holdSeconds": null, "reps": null}"#))
            == .stretchWithoutAmount(number: 1, name: "Pigeon"))
        #expect(failure(routineJSON(#"{"name": "Pigeon", "holdSeconds": -1, "reps": 0}"#))
            == .stretchWithoutAmount(number: 1, name: "Pigeon"))
    }

    @Test func everyRejectionSaysWhatWasWrong() {
        let errors: [BlueprintError] = [
            .unreadable, .unnamed, .noIntervals, .noWork, .noRounds, .noStretches,
            .stretchUnnamed(number: 3), .stretchWithoutAmount(number: 2, name: "Pigeon"),
        ]
        #expect(Set(errors.map(\.reason)).count == errors.count)
        #expect(BlueprintError.stretchUnnamed(number: 3).reason.contains("3"))
        #expect(BlueprintError.stretchWithoutAmount(number: 2, name: "Pigeon").reason.contains("Pigeon"))
    }
}

struct BlueprintSchemaTests {
    private func schema() throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(WorkoutBlueprint.schema.utf8)) as? [String: Any])
    }

    /// Every object in the schema, the root included.
    private func objects(in node: [String: Any]) -> [[String: Any]] {
        let properties = (node["properties"] as? [String: [String: Any]] ?? [:]).values
        let items = (node["items"] as? [String: Any]).map { [$0] } ?? []
        return (node["properties"] == nil ? [] : [node]) + (Array(properties) + items).flatMap(objects)
    }

    /// One value that the schema allows at `node`, with every property present and nothing null.
    private func sample(_ node: [String: Any], kind: String) throws -> Any {
        if let allowed = node["enum"] as? [String] {
            return try #require(allowed.first { $0 == kind })
        }
        let types = try (node["type"] as? [String]) ?? [#require(node["type"] as? String)]
        switch try #require(types.first { $0 != "null" }) {
        case "object":
            let properties = try #require(node["properties"] as? [String: [String: Any]])
            return try properties.mapValues { try sample($0, kind: kind) }
        case "array": return [try sample(try #require(node["items"] as? [String: Any]), kind: kind)]
        case "string": return "Side Bend"
        case "integer": return 7
        case "boolean": return true
        case let other:
            Issue.record("the sample has no value for the type \(other)")
            return NSNull()
        }
    }

    @Test func theSchemaIsInTheStrictFormStructuredOutputTakes() throws {
        let all = objects(in: try schema())
        #expect(all.count == 3, "the answer, its intervals and one stretch")
        for object in all {
            let properties = try #require(object["properties"] as? [String: Any])
            #expect(object["additionalProperties"] as? Bool == false)
            #expect(Set(try #require(object["required"] as? [String])) == Set(properties.keys))
        }
    }

    /// An answer built from the schema's own property names fills every field the decoder reads, so
    /// the schema names all of them.
    @Test func anAnswerThatFollowsTheSchemaFillsEveryFieldTheDecoderReads() throws {
        for kind in ["intervals", "routine"] {
            let answer = try JSONSerialization.data(withJSONObject: try sample(try schema(), kind: kind))
            let blueprint = try WorkoutBlueprint(modelOutput: String(decoding: answer, as: UTF8.self))
            #expect(blueprint.kind.rawValue == kind)
            #expect(blueprint.name == "Side Bend")
            #expect(blueprint.note == "Side Bend")
            let timer = try #require(blueprint.intervals)
            #expect([timer.warmUpSeconds, timer.workSeconds, timer.restSeconds, timer.rounds, timer.coolDownSeconds]
                == [7, 7, 7, 7, 7])
            #expect(timer.restAfterLastRound == true)
            let stretch = try #require(blueprint.stretches?.first)
            #expect(stretch.name == "Side Bend")
            #expect([stretch.holdSeconds, stretch.reps] == [7, 7])
            #expect(stretch.eachSide == true)
            _ = try blueprint.workout()
        }
    }

    @Test func theFallbackInstructionsCarryTheSchema() {
        #expect(WorkoutBlueprint.instructionsWithSchema.hasPrefix(WorkoutBlueprint.instructions))
        #expect(WorkoutBlueprint.instructionsWithSchema.hasSuffix(WorkoutBlueprint.schema))
    }
}
