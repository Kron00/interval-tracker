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
        XCTAssertEqual(skip.label, "Skip")
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

        let pauseResume = app.buttons["primaryButton"]
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
        let pause = app.buttons["primaryButton"].frame
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
        XCTAssertTrue(preset.label.contains("9:55 + reps"), preset.label)
        snap(app, "20-stretch-library")

        preset.tap()
        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detailTotal"].label, "9:55 + reps")
        XCTAssertTrue(app.staticTexts["0:45 each side"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["10 reps"].exists)
        XCTAssertTrue(app.buttons["howTo-Cat-Cow"].exists)
        XCTAssertTrue(app.switches["headphoneControlsToggle"].exists)
        snap(app, "21-stretch-detail")
        start.tap()

        let phase = app.staticTexts["phaseTitle"]
        let caption = app.staticTexts["roundLabel"]
        let clock = app.staticTexts["timeRemaining"]
        let reps = app.staticTexts["repCount"]
        let prompt = app.staticTexts["waitPrompt"]
        let primary = app.buttons["primaryButton"]
        let skip = app.buttons["skipButton"]
        XCTAssertTrue(phase.waitForExistence(timeout: 5))
        XCTAssertEqual(phase.label, "CAT-COW")
        XCTAssertEqual(caption.label, "Get ready")
        XCTAssertTrue(app.buttons["howToButton"].exists)
        XCTAssertTrue(app.staticTexts["Up next: Cat-Cow 10 reps"].exists)
        XCTAssertEqual(primary.label, "Pause")
        XCTAssertEqual(skip.label, "Next")
        XCTAssertTrue(skip.isEnabled)
        XCTAssertFalse(reps.exists)
        XCTAssertFalse(prompt.exists)
        let smallNext = skip.frame
        snap(app, "22-get-ready")

        XCTAssertTrue(reps.waitForExistence(timeout: 12), "the get-ready gap ends by itself")
        XCTAssertEqual(reps.label, "10 reps")
        XCTAssertEqual(phase.label, "CAT-COW")
        XCTAssertEqual(caption.label, "Stretch 1 of 10")
        waitFor(primary, toRead: "Next")
        XCTAssertEqual(prompt.label, "Tap Next when done")
        XCTAssertFalse(clock.exists, "a stretch counted in reps shows no clock")
        let howTo = app.buttons["howToButton"]
        XCTAssertTrue(howTo.exists, "a wait has no Pause, so the how-to chip is offered in it")
        XCTAssertFalse(skip.isEnabled, "while the run waits, the big button is the only Next")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: smallNext.midX, dy: smallNext.midY)).tap()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(phase.label, "CAT-COW", "a stretch counted in reps never moves on by itself")
        XCTAssertEqual(caption.label, "Stretch 1 of 10")
        XCTAssertTrue(reps.exists)
        snap(app, "40-reps-waiting")
        rotate(app, to: .landscapeLeft)
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(reps.frame) && window.contains(primary.frame) && window.contains(caption.frame))
        XCTAssertTrue(window.contains(prompt.frame) && window.contains(howTo.frame))
        XCTAssertFalse(prompt.frame.intersects(howTo.frame), "the prompt and the how-to chip each have their own place")
        XCTAssertFalse(reps.frame.intersects(prompt.frame))
        attach(XCUIScreen.main.screenshot(), "40a-reps-waiting-landscape")
        rotate(app, to: .portrait)

        primary.tap()
        waitFor(caption, toRead: "Get ready")
        XCTAssertEqual(phase.label, "CHILD'S POSE")
        waitFor(primary, toRead: "Pause")
        XCTAssertTrue(app.buttons["undoButton"].exists)
        XCTAssertFalse(reps.exists)
        let hold = expectation(for: NSPredicate(format: "label == %@", "Stretch 2 of 10"), evaluatedWith: caption)
        wait(for: [hold], timeout: 12)
        XCTAssertEqual(phase.label, "CHILD'S POSE", "one tap of Next runs the get-ready gap and then starts the hold")
        XCTAssertLessThanOrEqual(seconds(clock.label), 45)
        XCTAssertEqual(primary.label, "Pause")
        XCTAssertFalse(prompt.exists)
        snap(app, "24-hold")

        // A gap lasts a few seconds and ends by itself, so the run is paused while the test moves through
        // it. Then no step depends on how fast the simulator is.
        setPaused(true, with: primary)
        advance(skip, until: caption, toRead: "Switch sides · Right side next")
        XCTAssertEqual(clock.label, "0:05")
        setPaused(false, with: primary)
        XCTAssertEqual(phase.label, "HIP FLEXOR COUCH STRETCH")
        snap(app, "25-switch-sides")

        setPaused(true, with: primary)
        advance(skip, until: caption, toRead: "Right side · Stretch 4 of 10")
        setPaused(false, with: primary)
        Thread.sleep(forTimeInterval: 2)
        setPaused(true, with: primary)
        let before = seconds(app.staticTexts["totalRemaining"].label)
        XCTAssertLessThan(seconds(clock.label), 45)
        app.buttons["restartButton"].tap()
        waitFor(caption, toRead: "Switch sides · Right side next")
        XCTAssertEqual(clock.label, "0:05", "a restart from a hold goes back to the gap before it")
        XCTAssertGreaterThan(seconds(app.staticTexts["totalRemaining"].label), before + 5)
        XCTAssertEqual(primary.label, "Resume", "a restart keeps a paused run paused")
        let undo = app.buttons["undoButton"]
        XCTAssertTrue(undo.exists)
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: undo)
        wait(for: [gone], timeout: 10)
        XCTAssertEqual(clock.label, "0:05", "Undo goes away on a paused screen, which is not redrawn by the clock")

        app.buttons["endButton"].tap()
        app.buttons["confirmEndButton"].tap()
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        preset.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        app.buttons["Duplicate"].tap()
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Daily Stretch copy")
        XCTAssertEqual(app.staticTexts["editorTotal"].label, "9:55 + reps")
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
        let primary = app.buttons["primaryButton"]
        let skip = app.buttons["skipButton"]
        let undo = app.buttons["undoButton"]
        XCTAssertTrue(phase.waitForExistence(timeout: 5))
        let running = frames(in: app)
        snap(app, "30-running")

        setPaused(true, with: primary)
        XCTAssertTrue(app.staticTexts["in Warm-up"].exists)
        assertNothingMoved(in: app, since: running, "after Pause")
        snap(app, "31-paused")
        setPaused(false, with: primary)
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
        setPaused(true, with: primary)
        assertNothingMoved(in: app, since: wide, "in landscape after Pause")
        setPaused(false, with: primary)
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
        // The get-ready gap ends by itself after 8 seconds, so the run is paused while it is measured.
        setPaused(true, with: primary)
        let gettingReady = frames(in: app)
        assertNothingMoved(in: app, since: running, "from an interval timer to a stretch routine")

        skip.tap()
        XCTAssertTrue(app.staticTexts["repCount"].waitForExistence(timeout: 5))
        primary.tap()
        waitFor(primary, toRead: "Next")
        XCTAssertTrue(howTo.exists)
        XCTAssertTrue(app.staticTexts["waitPrompt"].exists)
        XCTAssertFalse(skip.isEnabled)
        XCTAssertFalse(app.staticTexts["timeRemaining"].exists)
        assertNothingMoved(in: app, since: gettingReady, "from get ready to a wait, both with a How to chip")
        assertNothingMoved(in: app, since: running, "from an interval timer to a wait with a How to chip")
        snap(app, "44-wait-with-how-to")

        rotate(app, to: .landscapeLeft)
        let wideWaiting = frames(in: app)
        assertNothingMoved(in: app, since: wide, "in landscape from an interval timer to a wait with a How to chip")
        primary.tap()
        waitFor(primary, toRead: "Pause")
        setPaused(true, with: primary)
        XCTAssertEqual(phase.label, "PAUSED")
        XCTAssertTrue(app.staticTexts["in Child's Pose"].exists)
        assertNothingMoved(in: app, since: wideWaiting, "in landscape from a wait to the next get-ready gap")
        assertNothingMoved(in: app, since: wide, "in landscape from an interval timer to a stretch routine")
        rotate(app, to: .portrait)
        assertNothingMoved(in: app, since: gettingReady, "after Next, in the get-ready gap of the next stretch")
    }

    func testBuildingARoutineAndRunningItToTheEnd() {
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
        app.buttons["duration-hold"].tap()
        let secondsWheel = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(secondsWheel.waitForExistence(timeout: 5))
        secondsWheel.adjust(toPickerWheelValue: "5 s")
        done.tap()
        XCTAssertTrue(app.buttons["stretchRow-Neck roll"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["editorTotal"].label, "0:15", "get ready 0:10, then hold 0:05")

        for _ in 0..<4 where !addStretch.isHittable { app.swipeUp() }
        addStretch.tap()
        XCTAssertTrue(stretchName.waitForExistence(timeout: 5))
        stretchName.tap()
        stretchName.typeText("Side bend")
        app.segmentedControls["amountPicker"].buttons["Reps"].tap()
        XCTAssertTrue(app.steppers["repsStepper"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["duration-hold"].exists, "reps have a count and no length")
        XCTAssertEqual(app.steppers.count, 1, "reps have a count and no pace")
        let eachSide = app.switches["eachSideToggle"]
        eachSide.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(eachSide.value as? String, "1")
        snap(app, "27a-stretch-editor-reps")
        done.tap()
        XCTAssertTrue(app.buttons["stretchRow-Side bend"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["10 reps each side"].exists)
        XCTAssertEqual(app.staticTexts["editorTotal"].label, "0:30 + reps", "0:15, then get ready 0:10 and switch 0:05")

        for _ in 0..<4 where !addStretch.isHittable { app.swipeUp() }
        addStretch.tap()
        XCTAssertTrue(stretchName.waitForExistence(timeout: 5))
        stretchName.tap()
        stretchName.typeText("Calf stretch")
        let link = app.textFields["stretchLinkField"]
        link.tap()
        link.typeText("https://example.com/calf")
        app.buttons["duration-hold"].tap()
        XCTAssertTrue(secondsWheel.waitForExistence(timeout: 5))
        secondsWheel.adjust(toPickerWheelValue: "5 s")
        done.tap()
        XCTAssertTrue(app.buttons["stretchRow-Calf stretch"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["editorTotal"].label, "0:45 + reps", "0:30, then get ready 0:10 and hold 0:05")
        XCTAssertFalse(problem.exists)
        snap(app, "28-new-routine")
        save.tap()

        let row = app.buttons["timerRow-Test routine"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("3 stretches · 1 each side"), row.label)
        XCTAssertTrue(row.label.contains("0:45 + reps"), row.label)
        snap(app, "29-routine-saved")

        row.tap()
        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let phase = app.staticTexts["phaseTitle"]
        let caption = app.staticTexts["roundLabel"]
        let clock = app.staticTexts["timeRemaining"]
        let holdDone = app.staticTexts["holdDone"]
        let reps = app.staticTexts["repCount"]
        let prompt = app.staticTexts["waitPrompt"]
        let primary = app.buttons["primaryButton"]
        let skip = app.buttons["skipButton"]
        let howTo = app.buttons["howToButton"]
        XCTAssertTrue(phase.waitForExistence(timeout: 5))
        XCTAssertEqual(phase.label, "NECK ROLL")
        XCTAssertEqual(caption.label, "Get ready")

        setPaused(true, with: primary)
        skip.tap()
        waitFor(caption, toRead: "Stretch 1 of 3")
        XCTAssertEqual(clock.label, "0:05")
        let counting = frames(in: app)
        setPaused(false, with: primary)

        XCTAssertTrue(holdDone.waitForExistence(timeout: 10), "the hold counts down to zero by itself")
        waitFor(primary, toRead: "Next")
        XCTAssertEqual(prompt.label, "Tap Next to continue")
        XCTAssertFalse(clock.exists, "a hold that ran out shows no clock stopped at 0:00")
        XCTAssertEqual(phase.label, "NECK ROLL")
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertTrue(holdDone.exists, "a hold that ran out waits")
        XCTAssertEqual(caption.label, "Stretch 1 of 3")
        XCTAssertTrue(app.staticTexts["Up next: Side bend 10 reps"].exists)
        XCTAssertFalse(howTo.exists, "a stretch with no link offers no how-to")
        XCTAssertFalse(skip.isEnabled, "while the run waits, the big button is the only Next")
        assertNothingMoved(in: app, since: counting, "when a hold runs out and the run waits, with no How to chip")
        snap(app, "41-hold-done")

        primary.tap()
        waitFor(caption, toRead: "Get ready · Left side")
        XCTAssertEqual(phase.label, "SIDE BEND")
        XCTAssertFalse(holdDone.exists)
        skip.tap()
        XCTAssertTrue(reps.waitForExistence(timeout: 5))
        XCTAssertEqual(reps.label, "10 reps")
        XCTAssertEqual(caption.label, "Left side · Stretch 2 of 3")
        waitFor(primary, toRead: "Next")
        XCTAssertTrue(app.staticTexts["Up next: Right side 10 reps"].exists)
        assertNothingMoved(in: app, since: counting, "from a hold to a stretch counted in reps")
        snap(app, "42-next-prominent")

        primary.tap()
        waitFor(caption, toRead: "Switch sides · Right side next")
        let rightSide = expectation(for: NSPredicate(format: "label == %@", "Right side · Stretch 2 of 3"), evaluatedWith: caption)
        wait(for: [rightSide], timeout: 10)
        XCTAssertTrue(reps.exists, "the switch-sides gap ends by itself and the right side waits")
        XCTAssertTrue(app.staticTexts["Up next: Calf stretch 0:05"].exists)

        primary.tap()
        waitFor(caption, toRead: "Get ready")
        XCTAssertEqual(phase.label, "CALF STRETCH")
        setPaused(true, with: primary)
        skip.tap()
        waitFor(caption, toRead: "Stretch 3 of 3")
        XCTAssertEqual(clock.label, "0:05")
        setPaused(false, with: primary)

        XCTAssertTrue(holdDone.waitForExistence(timeout: 10), "the last hold counts down to zero by itself")
        waitFor(primary, toRead: "Next")
        XCTAssertEqual(prompt.label, "Tap Next to finish")
        XCTAssertTrue(app.staticTexts["Up next: Finish"].exists)
        XCTAssertTrue(howTo.exists, "the how-to chip is offered while the run waits")
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertTrue(holdDone.exists, "the last hold waits too")
        XCTAssertFalse(app.staticTexts["Workout complete"].exists, "nothing in a routine finishes by itself")
        assertNothingMoved(in: app, since: counting, "when the last hold runs out and the run waits, with a How to chip")
        snap(app, "43-last-hold-done")

        primary.tap()
        XCTAssertTrue(app.staticTexts["Workout complete"].waitForExistence(timeout: 5), "Next on the last Done finishes the routine")
        XCTAssertTrue(app.buttons["doneButton"].exists)
        XCTAssertTrue(app.staticTexts["timeWorked"].label.hasPrefix("0:"), app.staticTexts["timeWorked"].label)
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

    private static let fixedInPlace = ["phaseTitle", "clock", "totalRemaining", "primaryButton", "skipButton"]

    private func frames(in app: XCUIApplication) -> [String: CGRect] {
        // Every change on the run screen animates for a quarter of a second.
        Thread.sleep(forTimeInterval: 0.6)
        var frames = Dictionary(uniqueKeysWithValues: Self.fixedInPlace.map { identifier in
            (identifier, app.descendants(matching: .any).matching(identifier: identifier).firstMatch.frame)
        })
        // The digits give way to a rep count or to "Done" while the run waits. Where they show, they stay put too.
        let digits = app.staticTexts["timeRemaining"]
        if digits.exists { frames["timeRemaining"] = digits.frame }
        return frames
    }

    private func assertNothingMoved(in app: XCUIApplication, since before: [String: CGRect], _ when: String) {
        for (identifier, now) in frames(in: app) {
            guard let was = before[identifier] else { continue }
            // The total is set against the right edge and is as wide as its digits, so "9:55" is narrower than "38:00".
            let leftEdge = identifier == "totalRemaining" ? 0 : now.minX - was.minX
            let moved = [leftEdge, now.maxX - was.maxX, now.minY - was.minY, now.height - was.height]
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
