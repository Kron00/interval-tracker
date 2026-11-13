import XCTest

/// Every launch here passes `-hrStub`, so the app talks to a stand-in monitor and never to Bluetooth.
/// Once connected, the stand-in sends one heart rate a second, from 100 up to 187 and back.
final class HeartRateUITests: XCTestCase {
    /// How long to wait for the app to show something. A wait ends as soon as it is met.
    private static let patience: TimeInterval = 30
    private static let beats = NSPredicate(format: "label MATCHES %@", "[0-9]+ beats per minute")
    private static let zone = NSPredicate(format: "label MATCHES %@", "ZONE [1-5]|BELOW ZONE 1")

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testSettingsFindsAMonitorShowsItsReadingAndSetsTheMaxHeartRate() {
        let app = launch("-uiTesting", "-hrStub", "new")
        openSettings(app)
        let none = app.staticTexts["noMonitor"]
        let find = app.buttons["findMonitorButton"]
        scroll(app, to: find)
        XCTAssertTrue(none.exists, "no monitor is remembered yet")
        XCTAssertTrue(app.staticTexts["190 bpm"].exists, "the max heart rate starts at 190")

        let stepper = app.steppers["maxHeartRateStepper"]
        stepper.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["191 bpm"].waitForExistence(timeout: Self.patience))
        stepper.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["190 bpm"].waitForExistence(timeout: Self.patience))

        find.tap()
        let standIn = app.buttons["foundMonitor-Stand-in strap"]
        XCTAssertTrue(standIn.waitForExistence(timeout: Self.patience), "the scan lists the stand-in")
        XCTAssertTrue(app.staticTexts["Strong"].exists, "with its signal strength")
        snap(app, "80a-find-a-monitor")
        standIn.tap()

        let reading = app.staticTexts["monitorReading"]
        XCTAssertTrue(reading.waitForExistence(timeout: Self.patience))
        let live = NSPredicate(format: "label MATCHES %@", "[0-9]+ bpm · (Zone [1-5]|Below zone 1)")
        wait(for: [expectation(for: live, evaluatedWith: reading)], timeout: Self.patience)
        XCTAssertEqual(app.staticTexts["rememberedMonitor"].label, "Stand-in strap")
        XCTAssertFalse(none.exists)
        scroll(app, to: app.buttons["forgetMonitorButton"])
        snap(app, "80-settings-heart-rate")

        app.buttons["forgetMonitorButton"].tap()
        XCTAssertTrue(none.waitForExistence(timeout: Self.patience), "Forget takes the monitor away")
    }

    func testARunShowsTheHeartRateAndItsZoneAndSoDoesTheLockScreen() throws {
        let app = launch("-uiTesting", "-hrStub", "remembered")
        start("Norwegian 4x4", in: app)
        let bpm = app.staticTexts["heartRateBPM"]
        wait(for: [expectation(for: Self.beats, evaluatedWith: bpm)], timeout: Self.patience)
        XCTAssertTrue(Self.zone.evaluate(with: app.staticTexts["heartRateZone"]), app.staticTexts["heartRateZone"].label)
        snap(app, "81-run-heart-rate")

        try showLockScreen()
        let card = springboard.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Norwegian 4x4")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.patience), "the lock screen shows the workout")
        allowLiveActivities()
        let heartRate = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", "Heart rate [0-9]+")).firstMatch
        XCTAssertTrue(heartRate.waitForExistence(timeout: Self.patience), "the card shows the heart rate")
        Thread.sleep(forTimeInterval: 1)
        attach(XCUIScreen.main.screenshot(), "82-lock-screen-heart-rate")

        app.activate()
        XCTAssertTrue(app.buttons["endButton"].waitForExistence(timeout: Self.patience))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 4)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 1)
        attach(XCUIScreen.main.screenshot(), "82a-dynamic-island-heart-rate")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
        app.activate()
    }

    /// Twenty seconds of readings make four points of the graph and reach three zones.
    func testAFinishedWorkoutKeepsItsHeartRateInHistory() {
        let app = launch("-uiTesting", "-hrStub", "remembered")
        start("Norwegian 4x4", in: app)
        wait(for: [expectation(for: Self.beats, evaluatedWith: app.staticTexts["heartRateBPM"])], timeout: Self.patience)
        Thread.sleep(forTimeInterval: 20)
        let done = app.buttons["doneButton"]
        let skip = app.buttons["skipButton"]
        for _ in 0..<12 where !done.exists { skip.tap() }
        XCTAssertTrue(done.waitForExistence(timeout: Self.patience))
        done.tap()

        let history = app.buttons["historyButton"]
        XCTAssertTrue(history.waitForExistence(timeout: Self.patience))
        history.tap()
        let row = app.buttons["historyRow-Norwegian 4x4"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(row.label.contains("average"), "the list card shows the average heart rate: \(row.label)")
        row.tap()

        let average = app.staticTexts["heartRateAverage"]
        XCTAssertTrue(average.waitForExistence(timeout: Self.patience))
        let figure = NSPredicate(format: "label MATCHES %@", "(Average|Maximum) [0-9]+ bpm")
        XCTAssertTrue(figure.evaluate(with: average), average.label)
        XCTAssertTrue(figure.evaluate(with: app.staticTexts["heartRateMaximum"]), app.staticTexts["heartRateMaximum"].label)
        XCTAssertTrue(app.descendants(matching: .any)["zoneBar"].exists)
        XCTAssertTrue(app.staticTexts["Zone 3"].exists, "each zone has its line")
        let graph = app.descendants(matching: .any)["heartRateGraph"]
        XCTAssertTrue(graph.exists)
        for _ in 0..<4 where !graph.isHittable { app.swipeUp() }
        snap(app, "83-history-heart-rate")
    }

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: Self.patience))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: Self.patience))
    }

    /// A Form draws its rows lazily, so a row below the screen does not exist until it is scrolled to.
    private func scroll(_ app: XCUIApplication, to element: XCUIElement) {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.isHittable, "\(element) is on the screen")
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

    /// Locks the simulator and wakes its screen, which leaves it on the lock screen.
    private func showLockScreen() throws {
        let lock = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: lock) else {
            throw XCTSkip("This Xcode cannot lock the simulator, so the lock screen cannot be shown.")
        }
        addTeardownBlock { XCUIApplication().activate() }
        XCUIDevice.shared.perform(lock)
        Thread.sleep(forTimeInterval: 1.5)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func allowLiveActivities() {
        for answer in ["Allow", "Always Allow"] {
            let button = springboard.buttons[answer]
            if button.waitForExistence(timeout: 2) { button.tap() }
        }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        attach(app.screenshot(), name)
    }

    private func attach(_ screenshot: XCUIScreenshot, _ name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
