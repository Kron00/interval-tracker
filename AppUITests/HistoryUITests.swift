import XCTest

final class HistoryUITests: XCTestCase {
    /// How long to wait for the app to show something. A wait ends as soon as it is met.
    private static let patience: TimeInterval = 30

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testAFinishedWorkoutIsInHistoryAndAFalseStartIsNot() {
        let app = launch("-uiTesting")
        openHistory(app)
        XCTAssertTrue(app.staticTexts["historyEmpty"].waitForExistence(timeout: Self.patience))
        XCTAssertFalse(app.buttons["clearHistoryButton"].exists)
        snap(app, "61-history-empty")
        goBack(app)

        start("Norwegian 4x4", in: app)
        let done = app.buttons["doneButton"]
        let skip = app.buttons["skipButton"]
        for _ in 0..<12 where !done.exists { skip.tap() }
        XCTAssertTrue(done.waitForExistence(timeout: Self.patience))
        done.tap()

        start("20/20 HIIT", in: app)
        app.buttons["endButton"].tap()
        let confirm = app.buttons["confirmEndButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(app.staticTexts["endHistoryNote"].label, "Under a minute of work, so it won't be saved to History.")
        snap(app, "64-end-not-saved")
        confirm.tap()

        openHistory(app)
        XCTAssertTrue(app.buttons["historyRow-Norwegian 4x4"].waitForExistence(timeout: Self.patience))
        XCTAssertEqual(app.buttons.matching(identifier: "historyRow-Norwegian 4x4").count, 1, "Done after the finish adds no second entry")
        XCTAssertFalse(app.buttons["historyRow-20/20 HIIT"].exists, "a run ended in its first minute is not kept")
        let summary = app.staticTexts["historySummary"].label
        XCTAssertTrue(summary.hasPrefix("This week: 1 workout,"), "the summary was \(summary)")

        let relaunched = launch("-uiTestingKeepLibrary")
        openHistory(relaunched)
        XCTAssertTrue(relaunched.buttons["historyRow-Norwegian 4x4"].waitForExistence(timeout: Self.patience))
    }

    /// The dialog is opened in the first seconds and left open, so the test sees its line change
    /// when the run reaches a minute of work.
    func testTheEndDialogSaysWhenTheRunWillBeSavedAndItIsSaved() {
        let app = launch("-uiTesting")
        start("20/20 HIIT", in: app)
        app.buttons["endButton"].tap()
        let note = app.staticTexts["endHistoryNote"]
        XCTAssertTrue(note.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(note.label, "Under a minute of work, so it won't be saved to History.")

        let saved = expectation(for: NSPredicate(format: "label == %@", "It will be saved to History as ended early."), evaluatedWith: note)
        wait(for: [saved], timeout: 60 + Self.patience)
        snap(app, "65-end-saved")
        app.buttons["confirmEndButton"].tap()

        openHistory(app)
        let row = app.buttons["historyRow-20/20 HIIT"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.patience), "the dialog said the run would be saved")
        XCTAssertTrue(row.label.contains("Ended early"), row.label)
    }

    func testHistoryListsRunsByDayAndDeletesThem() {
        let app = launch("-uiTesting", history: Self.fiveRunsOnFourDays())
        openHistory(app)
        let hiit = app.buttons["historyRow-20/20 HIIT"]
        XCTAssertTrue(hiit.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(app.staticTexts["Today"].exists)
        XCTAssertTrue(app.staticTexts["Yesterday"].exists)
        XCTAssertTrue(app.buttons["historyRow-Norwegian 4x4"].exists)
        XCTAssertTrue(app.buttons["historyRow-Daily Stretch"].exists)
        snap(app, "60-history")

        hiit.tap()
        let startAgain = app.buttons["startAgainButton"]
        XCTAssertTrue(startAgain.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(app.staticTexts["historyWorked"].label, "6:20")
        snap(app, "62-history-entry")

        startAgain.tap()
        let phase = app.staticTexts["phaseTitle"]
        XCTAssertTrue(phase.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(phase.label, "WARM-UP")
        XCTAssertEqual(app.staticTexts["totalRemaining"].label.prefix(2), "13", "20/20 HIIT is 14:00 long")
        app.buttons["endButton"].tap()
        let confirm = app.buttons["confirmEndButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.patience))
        confirm.tap()
        XCTAssertTrue(startAgain.waitForExistence(timeout: Self.patience))
        goBack(app)
        XCTAssertTrue(hiit.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(app.buttons.matching(identifier: "historyRow-20/20 HIIT").count, 1, "the false start added nothing")

        let deleted = app.buttons["historyRow-Morning Mobility"]
        for _ in 0..<4 where !deleted.isHittable { app.swipeUp() }
        deleted.tap()
        XCTAssertTrue(app.staticTexts["workoutGone"].waitForExistence(timeout: Self.patience))
        XCTAssertFalse(startAgain.exists, "a workout that is gone from the library cannot be started")
        snap(app, "62a-history-entry-workout-gone")
        goBack(app)

        XCTAssertTrue(deleted.waitForExistence(timeout: Self.patience))
        deleted.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: Self.patience))
        delete.tap()
        XCTAssertTrue(deleted.waitForNonExistence(timeout: Self.patience))
        XCTAssertTrue(app.buttons["historyRow-Daily Stretch"].exists, "the other entries stay")

        app.buttons["clearHistoryButton"].tap()
        let clear = app.alerts.buttons["Clear all"]
        XCTAssertTrue(clear.waitForExistence(timeout: Self.patience))
        snap(app, "63-history-clear-confirmation")
        clear.tap()
        XCTAssertTrue(app.staticTexts["historyEmpty"].waitForExistence(timeout: Self.patience))
    }

    /// A history file as the app writes it. A date is in seconds since 2001. The two built-in
    /// workouts carry their built-in ids, and Morning Mobility is in no library.
    private static func fiveRunsOnFourDays() -> String {
        let today = Calendar.current.startOfDay(for: .now)
        func run(_ name: String, _ workout: String, _ kind: String, daysAgo: Int, hour: Double,
                 worked: Int, planned: Int, _ outcome: String) -> [String: Any] {
            let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return [
                "id": UUID().uuidString, "startedAt": (day + hour * 3600).timeIntervalSinceReferenceDate,
                "workoutID": workout, "name": name, "kind": kind,
                "worked": worked, "planned": planned, "outcome": outcome,
            ]
        }
        let norwegian = "494E5456-4C43-4000-8000-000000000001"
        let hiit = "494E5456-4C43-4000-8000-000000000002"
        let dailyStretch = "494E5456-4C43-4000-8000-000000000004"
        let file: [String: Any] = ["version": 1, "records": [
            run("Norwegian 4x4", norwegian, "intervals", daysAgo: 0, hour: 7.25, worked: 2280, planned: 2280, "completed"),
            run("Daily Stretch", dailyStretch, "routine", daysAgo: 0, hour: 6.5, worked: 552, planned: 501, "completed"),
            run("20/20 HIIT", hiit, "intervals", daysAgo: 1, hour: 18.5, worked: 380, planned: 840, "endedEarly"),
            run("Morning Mobility", UUID().uuidString, "routine", daysAgo: 3, hour: 7, worked: 720, planned: 720, "completed"),
            run("Norwegian 4x4", norwegian, "intervals", daysAgo: 9, hour: 17.75, worked: 2040, planned: 2280, "completed"),
        ]]
        let json = (try? JSONSerialization.data(withJSONObject: file)) ?? Data()
        return String(decoding: json, as: UTF8.self)
    }

    private func launch(_ argument: String, history: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [argument]
        app.launchEnvironment["UITEST_HISTORY"] = history
        app.launch()
        return app
    }

    private func openHistory(_ app: XCUIApplication) {
        let history = app.buttons["historyButton"]
        XCTAssertTrue(history.waitForExistence(timeout: Self.patience))
        history.tap()
    }

    private func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func start(_ workout: String, in app: XCUIApplication) {
        let row = app.buttons["timerRow-\(workout)"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.patience))
        row.tap()
        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.patience))
        start.tap()
        XCTAssertTrue(app.staticTexts["phaseTitle"].waitForExistence(timeout: Self.patience))
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
