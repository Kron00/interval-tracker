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
        let undo = app.buttons["undoButton"]
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
        app.buttons["newIntervalTimer"].tap()

        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveButton"].isEnabled)
        XCTAssertTrue(app.staticTexts["editorProblem"].exists)
        XCTAssertEqual(app.staticTexts["editorTotal"].label, "20:00", "the total shows before the timer has a name")
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

        rotate(app, to: .landscapeLeft)
        let window = app.windows.firstMatch
        let clock = app.staticTexts["timeRemaining"].frame
        let pause = app.buttons["pauseResumeButton"].frame
        XCTAssertLessThan(clock.maxX, pause.minX, "the clock sits left of the controls in landscape")
        XCTAssertTrue(window.frame.contains(clock) && window.frame.contains(pause))
        XCTAssertTrue(app.buttons["skipButton"].isHittable)
        attach(XCUIScreen.main.screenshot(), "11-landscape")
        attach(window.screenshot(), "11-landscape-window")
        rotate(app, to: .portrait)

        app.buttons["endButton"].tap()
        let confirm = app.buttons["confirmEndButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["keepGoingButton"].isHittable)
        snap(app, "12-end-confirmation")
        confirm.tap()
        XCTAssertTrue(app.buttons["timerRow-Norwegian 4x4"].waitForExistence(timeout: 5))
    }

    func testRunningTheStretchPreset() {
        let app = launch("-uiTesting")
        let preset = app.buttons["timerRow-Daily Stretch"]
        XCTAssertTrue(preset.waitForExistence(timeout: 15))
        XCTAssertTrue(preset.label.contains("10 stretches · 4 each side"), preset.label)
        snap(app, "20-stretch-library")

        preset.tap()
        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0:45 each side"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["10 reps"].exists)
        XCTAssertTrue(app.buttons["howTo-Cat-Cow"].exists)
        XCTAssertTrue(app.switches["headphoneControlsToggle"].exists)
        snap(app, "21-stretch-detail")
        start.tap()

        let phase = app.staticTexts["phaseTitle"]
        let caption = app.staticTexts["roundLabel"]
        let rep = app.staticTexts["repLabel"]
        let skip = app.buttons["skipButton"]
        XCTAssertTrue(phase.waitForExistence(timeout: 5))
        XCTAssertEqual(phase.label, "CAT-COW")
        XCTAssertEqual(caption.label, "Get ready")
        XCTAssertTrue(app.buttons["howToButton"].exists)
        XCTAssertTrue(app.staticTexts["Up next: Cat-Cow 0:50"].exists)
        XCTAssertFalse(rep.exists)
        snap(app, "22-get-ready")

        // A gap lasts a few seconds and ends by itself, so the run is paused while the test moves through
        // it. Then no step depends on how fast the simulator is.
        let pauseResume = app.buttons["pauseResumeButton"]
        setPaused(true, with: pauseResume)
        advance(skip, until: rep)
        XCTAssertEqual(rep.label, "Rep 1 of 10")
        XCTAssertEqual(caption.label, "Stretch 1 of 10")
        XCTAssertTrue(app.staticTexts["in Cat-Cow"].exists)
        setPaused(false, with: pauseResume)
        XCTAssertFalse(app.buttons["howToButton"].exists, "the how-to chip is only offered while getting ready")
        snap(app, "23-reps")
        rotate(app, to: .landscapeLeft)
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(rep.frame) && window.contains(pauseResume.frame) && window.contains(caption.frame))
        attach(XCUIScreen.main.screenshot(), "23a-reps-landscape")
        rotate(app, to: .portrait)

        setPaused(true, with: pauseResume)
        advance(skip, until: caption, toRead: "Stretch 2 of 10")
        XCTAssertFalse(rep.exists)
        setPaused(false, with: pauseResume)
        XCTAssertEqual(phase.label, "CHILD'S POSE")
        snap(app, "24-hold")

        setPaused(true, with: pauseResume)
        advance(skip, until: caption, toRead: "Switch sides · Right side next")
        XCTAssertEqual(app.staticTexts["timeRemaining"].label, "0:05")
        setPaused(false, with: pauseResume)
        XCTAssertEqual(phase.label, "HIP FLEXOR COUCH STRETCH")
        snap(app, "25-switch-sides")

        setPaused(true, with: pauseResume)
        advance(skip, until: caption, toRead: "Right side · Stretch 4 of 10")
        setPaused(false, with: pauseResume)
        Thread.sleep(forTimeInterval: 2)
        setPaused(true, with: pauseResume)
        let before = seconds(app.staticTexts["totalRemaining"].label)
        XCTAssertLessThan(seconds(app.staticTexts["timeRemaining"].label), 45)
        app.buttons["restartButton"].tap()
        waitFor(caption, toRead: "Switch sides · Right side next")
        XCTAssertEqual(app.staticTexts["timeRemaining"].label, "0:05", "a restart from a hold goes back to the gap before it")
        XCTAssertGreaterThan(seconds(app.staticTexts["totalRemaining"].label), before + 5)
        XCTAssertEqual(pauseResume.label, "Resume", "a restart keeps a paused run paused")
        XCTAssertTrue(app.buttons["undoButton"].exists)

        app.buttons["endButton"].tap()
        app.buttons["confirmEndButton"].tap()
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        preset.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        app.buttons["Duplicate"].tap()
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Daily Stretch copy")
        XCTAssertEqual(app.staticTexts["editorTotal"].label, "10:45")
        XCTAssertTrue(app.buttons["saveButton"].isEnabled)
        snap(app, "26-routine-editor")

        let pigeon = app.buttons["stretchRow-Pigeon"]
        for _ in 0..<6 where !pigeon.isHittable { app.swipeUp() }
        pigeon.tap()
        let stretchName = app.textFields["stretchNameField"]
        XCTAssertTrue(stretchName.waitForExistence(timeout: 5))
        XCTAssertEqual(stretchName.value as? String, "Pigeon")
        XCTAssertEqual(app.textFields["stretchLinkField"].value as? String, "https://youtu.be/lqCqETr7Q0g")
        snap(app, "27-stretch-editor")
    }

    func testNothingMovesWhenTheRunChangesState() {
        let app = launch("-uiTesting")
        let interval = app.buttons["timerRow-Norwegian 4x4"]
        XCTAssertTrue(interval.waitForExistence(timeout: 15))
        interval.tap()
        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let phase = app.staticTexts["phaseTitle"]
        let pauseResume = app.buttons["pauseResumeButton"]
        let skip = app.buttons["skipButton"]
        let undo = app.buttons["undoButton"]
        XCTAssertTrue(phase.waitForExistence(timeout: 5))
        let running = frames(in: app)
        snap(app, "30-running")

        setPaused(true, with: pauseResume)
        XCTAssertTrue(app.staticTexts["in Warm-up"].exists)
        assertNothingMoved(in: app, since: running, "after Pause")
        snap(app, "31-paused")
        setPaused(false, with: pauseResume)
        assertNothingMoved(in: app, since: running, "after Resume")

        skip.tap()
        waitFor(phase, toRead: "WORK")
        XCTAssertTrue(undo.exists)
        assertNothingMoved(in: app, since: running, "in Work while Undo is offered")
        snap(app, "32-undo-chip")
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: undo)
        wait(for: [gone], timeout: 10)
        assertNothingMoved(in: app, since: running, "in Work after Undo went away")

        rotate(app, to: .landscapeLeft)
        let wide = frames(in: app)
        setPaused(true, with: pauseResume)
        assertNothingMoved(in: app, since: wide, "in landscape after Pause")
        setPaused(false, with: pauseResume)
        skip.tap()
        waitFor(phase, toRead: "REST")
        XCTAssertTrue(undo.exists)
        assertNothingMoved(in: app, since: wide, "in landscape while Undo is offered")
        attach(XCUIScreen.main.screenshot(), "33-landscape-undo-chip")
        rotate(app, to: .portrait)

        app.buttons["endButton"].tap()
        app.buttons["confirmEndButton"].tap()
        let stretch = app.buttons["timerRow-Daily Stretch"]
        XCTAssertTrue(stretch.waitForExistence(timeout: 5))
        stretch.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(phase.waitForExistence(timeout: 5))
        let howTo = app.buttons["howToButton"]
        XCTAssertTrue(howTo.exists)
        let gettingReady = frames(in: app)
        setPaused(true, with: pauseResume)
        advance(skip, until: app.staticTexts["repLabel"])
        setPaused(false, with: pauseResume)
        XCTAssertFalse(howTo.exists)
        assertNothingMoved(in: app, since: gettingReady, "from get ready with a How to chip to the hold")
        assertNothingMoved(in: app, since: running, "from an interval timer to a stretch routine")
    }

    func testBuildingARoutineInTheEditor() {
        let app = launch("-uiTesting")
        let add = app.buttons["addTimerButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        app.buttons["newStretchRoutine"].tap()

        let name = app.textFields["nameField"]
        let problem = app.staticTexts["editorProblem"]
        let save = app.buttons["saveButton"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(problem.label, "Name the routine to save it.")
        name.tap()
        name.typeText("Test routine")
        XCTAssertEqual(problem.label, "Add a stretch.")
        XCTAssertFalse(save.isEnabled)

        let addStretch = app.buttons["addStretchButton"]
        let stretchName = app.textFields["stretchNameField"]
        let done = app.buttons["stretchDoneButton"]
        addStretch.tap()
        XCTAssertTrue(stretchName.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["stretchProblem"].label, "Name stretch 1.")
        stretchName.tap()
        stretchName.typeText("Neck roll")
        done.tap()
        XCTAssertTrue(app.buttons["stretchRow-Neck roll"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["editorTotal"].label, "0:40", "get ready 0:10, then hold 0:30")

        for _ in 0..<4 where !addStretch.isHittable { app.swipeUp() }
        addStretch.tap()
        XCTAssertTrue(stretchName.waitForExistence(timeout: 5))
        stretchName.tap()
        stretchName.typeText("Side bend")
        let eachSide = app.switches["eachSideToggle"]
        eachSide.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(eachSide.value as? String, "1")
        done.tap()
        XCTAssertTrue(app.buttons["stretchRow-Side bend"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["editorTotal"].label, "1:55", "0:40, then get ready 0:10, 0:30, switch 0:05, 0:30")
        XCTAssertFalse(problem.exists)
        snap(app, "28-new-routine")
        save.tap()

        let row = app.buttons["timerRow-Test routine"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("2 stretches · 1 each side"), row.label)
        XCTAssertTrue(row.label.contains("1:55"), row.label)
        snap(app, "29-routine-saved")
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

    private func rotate(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let window = app.windows.firstMatch
        let wantsWide = orientation.isLandscape
        let turned = expectation(for: NSPredicate { _, _ in (window.frame.width > window.frame.height) == wantsWide }, evaluatedWith: nil)
        wait(for: [turned], timeout: 10)
        Thread.sleep(forTimeInterval: 2)
    }

    private static let fixedInPlace = ["phaseTitle", "timeRemaining", "totalRemaining", "pauseResumeButton", "skipButton"]

    private func frames(in app: XCUIApplication) -> [String: CGRect] {
        // Every change on the run screen animates for a quarter of a second.
        Thread.sleep(forTimeInterval: 0.6)
        return Dictionary(uniqueKeysWithValues: Self.fixedInPlace.map { identifier in
            (identifier, app.descendants(matching: .any).matching(identifier: identifier).firstMatch.frame)
        })
    }

    private func assertNothingMoved(in app: XCUIApplication, since before: [String: CGRect], _ when: String) {
        for (identifier, now) in frames(in: app) {
            let was = before[identifier] ?? .null
            let moved = [now.minX - was.minX, now.minY - was.minY, now.width - was.width, now.height - was.height]
                .map(abs).max() ?? .infinity
            XCTAssertLessThanOrEqual(moved, 0.5, "\(identifier) moved \(when): \(was) became \(now)")
        }
    }

    private func setPaused(_ paused: Bool, with button: XCUIElement) {
        let wanted = paused ? "Resume" : "Pause"
        if button.label != wanted { button.tap() }
        waitFor(button, toRead: wanted)
    }

    private func advance(_ skip: XCUIElement, until element: XCUIElement, toRead label: String? = nil) {
        for _ in 0..<12 {
            if element.exists, label == nil || element.label == label { return }
            skip.tap()
        }
        XCTFail("\(element) never read \(label ?? "anything")")
    }

    private func seconds(_ clock: String) -> Int {
        clock.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
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
