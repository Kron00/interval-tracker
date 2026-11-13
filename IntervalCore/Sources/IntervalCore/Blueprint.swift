import Foundation

/// A workout as a language model describes it: the JSON that `schema` asks for, decoded and not yet
/// checked. `workout()` is the only place that knows how it maps to a `Workout`.
public struct WorkoutBlueprint: Decodable, Equatable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case intervals, routine
    }

    public struct IntervalFields: Decodable, Equatable, Sendable {
        public var warmUpSeconds: Int?
        public var workSeconds: Int?
        public var restSeconds: Int?
        public var rounds: Int?
        public var coolDownSeconds: Int?
        public var restAfterLastRound: Bool?
    }

    public struct StretchFields: Decodable, Equatable, Sendable {
        public var name: String?
        public var holdSeconds: Int?
        public var reps: Int?
        public var eachSide: Bool?
    }

    public var kind: Kind
    public var name: String?
    /// What the model wants the user to know about its answer, in one sentence.
    public var note: String?
    public var intervals: IntervalFields?
    public var stretches: [StretchFields]?

    /// Reads the model's answer. A model that was not held to the schema may wrap the JSON in a code
    /// fence or a sentence, so this reads from the first brace to the last.
    public init(modelOutput text: String) throws(BlueprintError) {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let blueprint = try? JSONDecoder().decode(WorkoutBlueprint.self, from: Data(text[start...end].utf8))
        else { throw .unreadable }
        self = blueprint
    }

    /// The workout this blueprint describes. A number above the package's limit becomes the limit. A
    /// length of zero or less means the phase is absent. Anything that leaves no workout to run is an error.
    public func workout() throws(BlueprintError) -> Workout {
        let name = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .unnamed }
        switch kind {
        case .intervals:
            guard let fields = intervals else { throw .noIntervals }
            guard let work = Self.span(fields.workSeconds) else { throw .noWork }
            guard let rounds = Self.count(fields.rounds) else { throw .noRounds }
            var plan = Intervals(
                warmUp: Self.span(fields.warmUpSeconds), work: work, rest: Self.span(fields.restSeconds),
                rounds: rounds, coolDown: Self.span(fields.coolDownSeconds))
            if let restAfterLastRound = fields.restAfterLastRound { plan.restAfterLastRound = restAfterLastRound }
            return Workout(name: name, plan: .intervals(plan))
        case .routine:
            var built: [Stretch] = []
            for (index, fields) in (stretches ?? []).prefix(Routine.maximumStretches).enumerated() {
                built.append(try Self.stretch(fields, number: index + 1))
            }
            // The model never chooses the gaps. A generated routine gets the ones a new routine has in the editor.
            guard let getReady = Span(seconds: Self.getReadySeconds),
                  let switchSides = Span(seconds: Self.switchSidesSeconds),
                  let routine = Routine(getReady: getReady, switchSides: switchSides, stretches: built)
            else { throw .noStretches }
            return Workout(name: name, plan: .routine(routine))
        }
    }

    private static let getReadySeconds = 10
    private static let switchSidesSeconds = 5

    /// A stretch that names both a hold and reps is counted in reps, as a paced-reps stretch from app
    /// version 1.1 is.
    private static func stretch(_ fields: StretchFields, number: Int) throws(BlueprintError) -> Stretch {
        let name = String((fields.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Stretch.maximumNameLength))
        guard !name.isEmpty else { throw .stretchUnnamed(number: number) }
        guard let amount = count(fields.reps).map(Amount.reps) ?? span(fields.holdSeconds).map(Amount.hold),
              let stretch = Stretch(name: name, amount: amount, sides: fields.eachSide == true ? .each : .once, howTo: nil)
        else { throw .stretchWithoutAmount(number: number, name: name) }
        return stretch
    }

    private static func span(_ seconds: Int?) -> Span? {
        seconds.flatMap { $0 > 0 ? Span(seconds: min($0, Span.range.upperBound)) : nil }
    }

    private static func count(_ value: Int?) -> Count? {
        value.flatMap { $0 > 0 ? Count(min($0, Count.range.upperBound)) : nil }
    }
}

public enum BlueprintError: Error, Equatable, Sendable {
    /// The text is not the JSON that `WorkoutBlueprint.schema` describes.
    case unreadable
    case unnamed
    /// The kind is intervals and the interval fields are missing.
    case noIntervals
    case noWork
    case noRounds
    case noStretches
    case stretchUnnamed(number: Int)
    case stretchWithoutAmount(number: Int, name: String)

    /// What was wrong, as the end of a sentence that starts "The answer ...".
    public var reason: String {
        switch self {
        case .unreadable: "was not in the form the app asked for"
        case .unnamed: "had no name"
        case .noIntervals: "was a timer with no lengths"
        case .noWork: "had no work time"
        case .noRounds: "had no rounds"
        case .noStretches: "was a routine with no stretches"
        case .stretchUnnamed(let number): "left stretch \(number) without a name"
        case .stretchWithoutAmount(_, let name): "gave \(name) no hold time and no reps"
        }
    }
}

extension WorkoutBlueprint {
    /// The system text for the model. It states the limits `workout()` enforces, so a model that
    /// follows it is never clamped.
    public static let instructions = """
        You build workouts for Intervals, an iPhone timer app. Turn the user's description into one \
        workout and answer with one JSON object and nothing else.

        The app has two kinds of workout.

        "intervals" is a timer that runs by itself: an optional warm-up, then one work length and one \
        rest length repeated for a number of rounds, then an optional cool-down. Every round has the \
        same lengths. Use it for running, cycling, rowing, HIIT, Tabata and other conditioning.
        - Lengths are whole seconds from \(Span.range.lowerBound) to \(Span.range.upperBound). \
        Rounds are \(Count.range.lowerBound) to \(Count.range.upperBound).
        - Use null for a warm-up, a rest or a cool-down that the workout does not have.
        - restAfterLastRound says whether a rest follows the final round.

        "routine" is a list of 1 to \(Routine.maximumStretches) stretches or exercises done in order. \
        The app waits for the user after each one. Use it for stretching, mobility, yoga, rehab and \
        strength exercises.
        - Each stretch has a name of at most \(Stretch.maximumNameLength) characters. The app speaks \
        the name aloud, so write plain words, with no side, time or rep count in it.
        - Each stretch has either holdSeconds, a timed hold, or reps, a count done at the user's own \
        pace. Set the other one to null.
        - eachSide is true when the stretch is done on the left side and then on the right side. \
        holdSeconds and reps are then for one side.
        - The app adds a pause of about \(getReadySeconds) seconds before each stretch by itself. Do \
        not add pauses or rests as stretches.

        Set "kind", fill the part that matches it, and set the other part to null.
        "name" is a short title of at most 30 characters.
        When the description asks for a total time, choose lengths that add up close to it. In a \
        routine, count the pause before each stretch, and count an each-side stretch two times.
        "note" is one short sentence for the user when you had to change or assume something, for \
        example when rounds of different lengths became rounds of one length. Otherwise it is null.
        """

    /// The instructions for a server that does not accept a schema with the request.
    public static let instructionsWithSchema = instructions
        + "\n\nThe JSON object must match this JSON Schema:\n" + schema

    /// The JSON Schema of the answer, in the strict form OpenAI's structured output takes: every
    /// property is required, an absent value is null, and no other property is allowed.
    public static let schema = """
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["kind", "name", "note", "intervals", "stretches"],
          "properties": {
            "kind": {"type": "string", "enum": ["intervals", "routine"]},
            "name": {"type": "string"},
            "note": {"type": ["string", "null"]},
            "intervals": {
              "type": ["object", "null"],
              "additionalProperties": false,
              "required": ["warmUpSeconds", "workSeconds", "restSeconds", "rounds", "coolDownSeconds", "restAfterLastRound"],
              "properties": {
                "warmUpSeconds": {"type": ["integer", "null"]},
                "workSeconds": {"type": "integer"},
                "restSeconds": {"type": ["integer", "null"]},
                "rounds": {"type": "integer"},
                "coolDownSeconds": {"type": ["integer", "null"]},
                "restAfterLastRound": {"type": "boolean"}
              }
            },
            "stretches": {
              "type": ["array", "null"],
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["name", "holdSeconds", "reps", "eachSide"],
                "properties": {
                  "name": {"type": "string"},
                  "holdSeconds": {"type": ["integer", "null"]},
                  "reps": {"type": ["integer", "null"]},
                  "eachSide": {"type": "boolean"}
                }
              }
            }
          }
        }
        """
}
