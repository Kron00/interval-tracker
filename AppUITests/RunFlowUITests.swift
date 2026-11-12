import XCTest

final class RunFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testRunningAPresetFromStartToFinish() {
        let app = launch("-uiTesting")
        let preset = app.buttons["timerRow-Norwegian 4x4"]
        XCTAssertTrue(preset.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["timerRow-20/20 HIIT"].exists)
        snap(app, "01-library")

        preset.tap()
        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        snap(app, "02-detail")
        start.tap()

        let phase = app.staticTexts["phaseTitle"]
        XCTAssertTrue(phase.waitForExistence(timeout: 5))
        XCTAssertEqual(phase.label, "WARM-UP")
        XCTAssertFalse(app.staticTexts["roundLabel"].exists)
        let total = app.staticTexts["totalRemaining"].label
        XCTAssertTrue(total == "38:00" || total.hasPrefix("37:"), "total left was \(total)")
        snap(app, "03-warmup")

        let skip = app.buttons["skipButton"]
        skip.tap()
        waitFor(phase, toRead: "WORK")
        let undo = app.buttons["undoSkipButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        snap(app, "04a-undo-offered")
        undo.tap()
        waitFor(phase, toRead: "WARM-UP")
        XCTAssertFalse(undo.exists)
        skip.tap()
        waitFor(phase, toRead: "WORK")
        XCTAssertEqual(app.staticTexts["roundLabel"].label, "Round 1 of 4")
        let workLeft = app.staticTexts["timeRemaining"].label
        XCTAssertTrue(workLeft == "4:00" || workLeft.hasPrefix("3:5"), "work time left was \(workLeft)")
        snap(app, "04-work")

        let pauseResume = app.buttons["pauseResumeButton"]
        XCTAssertEqual(pauseResume.label, "Pause")
        pauseResume.tap()
        waitFor(pauseResume, toRead: "Resume")
        XCTAssertEqual(phase.label, "PAUSED")
        XCTAssertTrue(app.staticTexts["in Work"].exists)
        let frozen = app.staticTexts["timeRemaining"].label
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertEqual(app.staticTexts["timeRemaining"].label, frozen)
        snap(app, "05-paused")
        pauseResume.tap()
        waitFor(pauseResume, toRead: "Pause")

        skip.tap()
        waitFor(phase, toRead: "REST")
        XCTAssertEqual(app.staticTexts["roundLabel"].label, "Round 1 of 4")
        snap(app, "06-rest")

        let done = app.buttons["doneButton"]
        var taps = 0
        while !done.exists, taps < 12 {
            if skip.exists { skip.tap() }
            taps += 1
        }
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(taps, 8, "rest 1, then work and rest for rounds 2 to 4, then cool-down")
        XCTAssertTrue(undo.exists, "a skip that ends the workout can still be taken back")
        undo.tap()
        waitFor(phase, toRead: "COOL-DOWN")
        skip.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let worked = app.staticTexts["timeWorked"].label
        XCTAssertTrue(worked.hasPrefix("0:"), "nearly everything was skipped, yet time worked read \(worked)")
        snap(app, "07-finished")

        done.tap()
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        XCTAssertTrue(preset.isHittable)
    }

    func testASavedTimerSurvivesARelaunch() {
        let app = launch("-uiTesting")
        let add = app.buttons["addTimerButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()

        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveButton"].isEnabled)
        XCTAssertTrue(app.staticTexts["editorProblem"].exists)
        name.tap()
        name.typeText("Test timer")
        snap(app, "08-editor")
        app.buttons["duration-work"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.keyboards.count, 0, "the keyboard must not cover the duration wheels")
        snap(app, "08a-editor-wheels")
        app.buttons["saveButton"].tap()

        let row = app.buttons["timerRow-Test timer"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        snap(app, "09-saved")

        app.buttons["timerRow-20/20 HIIT"].tap()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 5))
        app.buttons["Duplicate"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "20/20 HIIT copy")
        snap(app, "09a-duplicate-opens-editor")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["timerRow-20/20 HIIT copy"].waitForExistence(timeout: 2))
        app.terminate()

        let relaunched = launch("-uiTestingKeepLibrary")
        XCTAssertTrue(relaunched.buttons["timerRow-Test timer"].waitForExistence(timeout: 15))
    }

    func testAudioCheckRunsInLandscapeAndCanBeEnded() {
        let app = launch("-uiTesting")
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        snap(app, "10-settings")

        let troubleshooting = app.buttons["troubleshootingLink"]
        for _ in 0..<6 where !troubleshooting.isHittable { app.swipeUp() }
        troubleshooting.tap()
        XCTAssertTrue(app.navigationBars["Troubleshooting"].waitForExistence(timeout: 5))
        snap(app, "10a-troubleshooting")
        app.navigationBars["Troubleshooting"].buttons.firstMatch.tap()

        let check = app.buttons["audioCheckButton"]
        for _ in 0..<6 where !check.isHittable { app.swipeUp() }
        check.tap()

        let phase = app.staticTexts["phaseTitle"]
        XCTAssertTrue(phase.waitForExistence(timeout: 5))
        XCTAssertEqual(phase.label, "WARM-UP")

        XCUIDevice.shared.orientation = .landscapeLeft
        let window = app.windows.firstMatch
        let isWide = expectation(for: NSPredicate { _, _ in window.frame.width > window.frame.height }, evaluatedWith: nil)
        wait(for: [isWide], timeout: 10)
        Thread.sleep(forTimeInterval: 2)
        let clock = app.staticTexts["timeRemaining"].frame
        let pause = app.buttons["pauseResumeButton"].frame
        XCTAssertLessThan(clock.maxX, pause.minX, "the clock sits left of the controls in landscape")
        XCTAssertTrue(window.frame.contains(clock) && window.frame.contains(pause))
        XCTAssertTrue(app.buttons["skipButton"].isHittable)
        attach(XCUIScreen.main.screenshot(), "11-landscape")
        attach(window.screenshot(), "11-landscape-window")
        XCUIDevice.shared.orientation = .portrait
        let isTall = expectation(for: NSPredicate { _, _ in window.frame.height > window.frame.width }, evaluatedWith: nil)
        wait(for: [isTall], timeout: 10)

        app.buttons["endButton"].tap()
        let confirm = app.buttons["End workout"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["timerRow-Norwegian 4x4"].waitForExistence(timeout: 5))
    }

    private func launch(_ argument: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [argument]
        app.launch()
        return app
    }

    private func waitFor(_ element: XCUIElement, toRead label: String) {
        let matches = expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
        wait(for: [matches], timeout: 5)
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
