import XCTest

final class RunFlowUITests: XCTestCase {
    /// How long to wait for the app to show something. A wait ends as soon as it is met, so a long
    /// limit costs nothing on a healthy machine. A CI runner has taken over ten seconds to return from one tap.
    private static let patience: TimeInterval = 30

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testRunningAPresetFromStartToFinish() {
        let app = launch("-uiTesting")
        let preset = app.buttons["timerRow-Norwegian 4x4"]
        XCTAssertTrue(preset.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(app.buttons["timerRow-20/20 HIIT"].exists)
        snap(app, "01-library")

        preset.tap()
        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.patience))
        snap(app, "02-detail")
        start.tap()

        let phase = app.staticTexts["phaseTitle"]
        XCTAssertTrue(phase.waitForExistence(timeout: Self.patience))
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
        XCTAssertTrue(undo.waitForExistence(timeout: Self.patience))
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
        XCTAssertTrue(done.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(taps, 8, "rest 1, then work and rest for rounds 2 to 4, then cool-down")
        XCTAssertTrue(undo.exists, "a skip that ends the workout can still be taken back")
        undo.tap()
        waitFor(phase, toRead: "COOL-DOWN")
        skip.tap()
        XCTAssertTrue(done.waitForExistence(timeout: Self.patience))
        let worked = app.staticTexts["timeWorked"].label
        let minutesWorked = Int(worked.split(separator: ":").first ?? "") ?? .max
        XCTAssertLessThan(minutesWorked, 10, "nearly all of a 38:00 timer was skipped, yet time worked read \(worked)")
        snap(app, "07-finished")

        done.tap()
        XCTAssertTrue(preset.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(preset.isHittable)
    }

    func testASavedTimerSurvivesARelaunch() {
        let app = launch("-uiTesting")
        let add = app.buttons["addTimerButton"]
        XCTAssertTrue(add.waitForExistence(timeout: Self.patience))
        add.tap()
        app.buttons["newIntervalTimer"].tap()

        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.patience))
        XCTAssertFalse(app.buttons["saveButton"].isEnabled)
        XCTAssertTrue(app.staticTexts["editorProblem"].exists)
        XCTAssertEqual(app.staticTexts["editorTotal"].label, "20:00", "the total shows before the timer has a name")
        name.tap()
        name.typeText("Test timer")
        snap(app, "08-editor")
        app.buttons["duration-work"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(app.keyboards.count, 0, "the keyboard must not cover the duration wheels")
        snap(app, "08a-editor-wheels")
        app.buttons["saveButton"].tap()

        let row = app.buttons["timerRow-Test timer"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.patience))
        snap(app, "09-saved")

        app.buttons["timerRow-20/20 HIIT"].tap()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: Self.patience))
        app.buttons["Duplicate"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(name.value as? String, "20/20 HIIT copy")
        snap(app, "09a-duplicate-opens-editor")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["timerRow-20/20 HIIT copy"].waitForExistence(timeout: 2))
        app.terminate()

        let relaunched = launch("-uiTestingKeepLibrary")
        XCTAssertTrue(relaunched.buttons["timerRow-Test timer"].waitForExistence(timeout: Self.patience))
    }

    func testAudioCheckRunsInLandscapeAndCanBeEnded() {
        let app = launch("-uiTesting")
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: Self.patience))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: Self.patience))
        snap(app, "10-settings")

        let troubleshooting = app.buttons["troubleshootingLink"]
        for _ in 0..<6 where !troubleshooting.isHittable { app.swipeUp() }
        troubleshooting.tap()
        XCTAssertTrue(app.navigationBars["Troubleshooting"].waitForExistence(timeout: Self.patience))
        snap(app, "10a-troubleshooting")
        app.navigationBars["Troubleshooting"].buttons.firstMatch.tap()

        let check = app.buttons["audioCheckButton"]
        for _ in 0..<6 where !check.isHittable { app.swipeUp() }
        check.tap()

        let phase = app.staticTexts["phaseTitle"]
        XCTAssertTrue(phase.waitForExistence(timeout: Self.patience))
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
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(app.buttons["keepGoingButton"].isHittable)
        snap(app, "12-end-confirmation")
        confirm.tap()
        XCTAssertTrue(app.buttons["timerRow-Norwegian 4x4"].waitForExistence(timeout: Self.patience))
    }

    func testRunningTheStretchPreset() {
        let app = launch("-uiTesting")
        let preset = app.buttons["timerRow-Daily Stretch"]
        XCTAssertTrue(preset.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(preset.label.contains("10 stretches · 3 each side"), preset.label)
        XCTAssertTrue(preset.label.contains("8:21 + reps"), preset.label)
        snap(app, "20-stretch-library")

        preset.tap()
        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(app.staticTexts["detailTotal"].label, "8:21 + reps")
        XCTAssertTrue(app.staticTexts["0:45 each side"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["10 reps"].exists)
        XCTAssertTrue(app.buttons["howTo-Cat-Cow"].exists)
        XCTAssertTrue(app.switches["headphoneControlsToggle"].exists)
        snap(app, "21-stretch-detail")
        start.tap()

        let phase = app.staticTexts["phaseTitle"]
        let caption = app.staticTexts["roundLabel"]
        let clock = app.staticTexts["timeRemaining"]
        let length = app.staticTexts["holdLength"]
        let reps = app.staticTexts["repCount"]
        let prompt = app.staticTexts["waitPrompt"]
        let total = app.staticTexts["totalRemaining"]
        let primary = app.buttons["primaryButton"]
        let skip = app.buttons["skipButton"]
        let restart = app.buttons["restartButton"]
        let howTo = app.buttons["howToButton"]
        XCTAssertTrue(reps.waitForExistence(timeout: Self.patience), "the routine opens on its first stretch, with nothing before it")
        XCTAssertEqual(phase.label, "CAT-COW")
        XCTAssertEqual(reps.label, "10 reps")
        XCTAssertEqual(caption.label, "Stretch 1 of 10")
        waitFor(primary, toRead: "Next")
        XCTAssertEqual(prompt.label, "Tap Next when done")
        XCTAssertTrue(app.staticTexts["Up next: Child's Pose 0:45"].exists)
        XCTAssertFalse(clock.exists, "a stretch counted in reps shows no clock")
        XCTAssertTrue(howTo.exists, "a wait has no Pause, so the how-to chip is offered in it")
        XCTAssertFalse(skip.isEnabled, "while the run waits, the big button is the only Next")
        XCTAssertFalse(restart.isEnabled, "a wait has nothing to restart")
        let smallNext = skip.frame
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
        XCTAssertTrue(length.waitForExistence(timeout: Self.patience), "Next shows the next stretch, and it waits for Start")
        XCTAssertEqual(phase.label, "CHILD'S POSE")
        XCTAssertEqual(caption.label, "Stretch 2 of 10")
        XCTAssertEqual(length.label, "0:45")
        waitFor(primary, toRead: "Start")
        XCTAssertEqual(prompt.label, "Tap Start")
        XCTAssertTrue(app.staticTexts["Up next: Cobra 0:30"].exists)
        XCTAssertTrue(app.buttons["undoButton"].exists)
        XCTAssertTrue(howTo.exists)
        XCTAssertFalse(skip.isEnabled)
        XCTAssertFalse(restart.isEnabled)
        XCTAssertFalse(reps.exists)
        XCTAssertFalse(clock.exists, "nothing counts down until Start")
        let totalBeforeStart = total.label
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(length.label, "0:45", "nothing changes while the run waits for Start")
        XCTAssertEqual(total.label, totalBeforeStart)
        XCTAssertEqual(primary.label, "Start")
        XCTAssertEqual(phase.label, "CHILD'S POSE")
        snap(app, "45-waiting-to-start")
        rotate(app, to: .landscapeLeft)
        let wide = app.windows.firstMatch.frame
        XCTAssertTrue(wide.contains(length.frame) && wide.contains(primary.frame) && wide.contains(prompt.frame))
        XCTAssertFalse(length.frame.intersects(prompt.frame))
        attach(XCUIScreen.main.screenshot(), "45b-waiting-to-start-landscape")
        rotate(app, to: .portrait)

        // The count-in lasts three seconds, so the test does not race it. Paused, a restart puts the
        // run at the start of the count-in whether the pause landed in the count-in or in the hold.
        primary.tap()
        setPaused(true, with: primary)
        restart.tap()
        waitFor(caption, toRead: "Get ready")
        XCTAssertEqual(clock.label, "0:03", "Start leads into a three-second count-in")
        XCTAssertTrue(app.staticTexts["in Child's Pose"].exists)
        XCTAssertTrue(app.staticTexts["Up next: Cobra 0:30"].exists)
        XCTAssertFalse(length.exists)
        setPaused(false, with: primary)
        snap(app, "45a-count-in")

        let hold = expectation(for: NSPredicate(format: "label == %@", "Stretch 2 of 10"), evaluatedWith: caption)
        wait(for: [hold], timeout: Self.patience)
        XCTAssertEqual(phase.label, "CHILD'S POSE", "the count-in ends by itself and the hold starts")
        XCTAssertLessThanOrEqual(seconds(clock.label), 45)
        XCTAssertEqual(primary.label, "Pause")
        XCTAssertTrue(skip.isEnabled)
        XCTAssertEqual(skip.label, "Next")
        XCTAssertFalse(prompt.exists)
        XCTAssertFalse(howTo.exists, "a countdown leaves no time for a video")
        snap(app, "46-hold-running")

        skip.tap()
        XCTAssertTrue(length.waitForExistence(timeout: Self.patience), "Next during a hold ends it, and the next stretch waits")
        waitFor(phase, toRead: "COBRA")
        XCTAssertEqual(length.label, "0:30")
        waitFor(primary, toRead: "Start")

        // Next leaves a stretch from its count-in and from its hold alike, so it does not matter
        // which of the two these taps land in.
        primary.tap()
        waitFor(primary, toRead: "Pause")
        skip.tap()
        waitFor(caption, toRead: "Left side · Stretch 4 of 10")
        XCTAssertEqual(phase.label, "HIP FLEXOR COUCH STRETCH")
        XCTAssertEqual(length.label, "0:45")
        XCTAssertTrue(app.staticTexts["Up next: Right side 0:45"].exists)
        primary.tap()
        waitFor(primary, toRead: "Pause")
        skip.tap()
        waitFor(caption, toRead: "Right side · Stretch 4 of 10")
        waitFor(primary, toRead: "Start")
        XCTAssertEqual(length.label, "0:45", "each side waits for its own Start")
        XCTAssertTrue(app.staticTexts["Up next: Pigeon 0:45"].exists)
        snap(app, "25-right-side-waiting")

        primary.tap()
        Thread.sleep(forTimeInterval: 4.5)
        setPaused(true, with: primary)
        XCTAssertEqual(caption.label, "Right side · Stretch 4 of 10", "the count-in is over and the hold is counting")
        let before = seconds(total.label)
        XCTAssertLessThan(seconds(clock.label), 45)
        restart.tap()
        waitFor(caption, toRead: "Get ready · Right side")
        XCTAssertEqual(clock.label, "0:03", "a restart from a hold goes back to its count-in")
        XCTAssertGreaterThan(seconds(total.label), before + 3)
        XCTAssertEqual(primary.label, "Resume", "a restart keeps a paused run paused")
        let undo = app.buttons["undoButton"]
        XCTAssertTrue(undo.exists)
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: undo)
        wait(for: [gone], timeout: 35)
        XCTAssertEqual(clock.label, "0:03", "Undo goes away on a paused screen, which is not redrawn by the clock")

        app.buttons["endButton"].tap()
        app.buttons["confirmEndButton"].tap()
        XCTAssertTrue(preset.waitForExistence(timeout: Self.patience))
        preset.tap()
        XCTAssertTrue(start.waitForExistence(timeout: Self.patience))
        app.buttons["Duplicate"].tap()
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(name.value as? String, "Daily Stretch copy")
        XCTAssertEqual(app.staticTexts["editorTotal"].label, "8:21 + reps")
        XCTAssertTrue(app.buttons["saveButton"].isEnabled)
        XCTAssertTrue(app.buttons["countInPicker"].exists)
        XCTAssertFalse(app.buttons["duration-getReady"].exists, "a routine has no gaps to set")
        XCTAssertFalse(app.buttons["duration-switchSides"].exists)
        snap(app, "26-routine-editor")

        let pigeon = app.buttons["stretchRow-Pigeon"]
        for _ in 0..<6 where !pigeon.isHittable { app.swipeUp() }
        pigeon.tap()
        let stretchName = app.textFields["stretchNameField"]
        XCTAssertTrue(stretchName.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(stretchName.value as? String, "Pigeon")
        XCTAssertEqual(app.textFields["stretchLinkField"].value as? String, "https://youtu.be/lqCqETr7Q0g")
        snap(app, "27-stretch-editor")
    }

    func testNothingMovesWhenTheRunChangesState() {
        let app = launch("-uiTesting")
        let interval = app.buttons["timerRow-Norwegian 4x4"]
        XCTAssertTrue(interval.waitForExistence(timeout: Self.patience))
        interval.tap()
        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.patience))
        start.tap()

        let phase = app.staticTexts["phaseTitle"]
        let primary = app.buttons["primaryButton"]
        let skip = app.buttons["skipButton"]
        let undo = app.buttons["undoButton"]
        XCTAssertTrue(phase.waitForExistence(timeout: Self.patience))
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
        wait(for: [gone], timeout: 35)
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
        XCTAssertTrue(stretch.waitForExistence(timeout: Self.patience))
        stretch.tap()
        XCTAssertTrue(start.waitForExistence(timeout: Self.patience))
        start.tap()
        let caption = app.staticTexts["roundLabel"]
        let length = app.staticTexts["holdLength"]
        let howTo = app.buttons["howToButton"]
        XCTAssertTrue(app.staticTexts["repCount"].waitForExistence(timeout: Self.patience))
        waitFor(primary, toRead: "Next")
        XCTAssertTrue(howTo.exists)
        XCTAssertTrue(app.staticTexts["waitPrompt"].exists)
        XCTAssertFalse(skip.isEnabled)
        XCTAssertFalse(app.staticTexts["timeRemaining"].exists)
        assertNothingMoved(in: app, since: running, "from an interval timer to a stretch counted in reps, with a How to chip")
        snap(app, "44-wait-with-how-to")

        primary.tap()
        XCTAssertTrue(length.waitForExistence(timeout: Self.patience))
        waitFor(primary, toRead: "Start")
        let waitingToStart = frames(in: app)
        assertNothingMoved(in: app, since: running, "from an interval timer to a stretch that waits for Start")
        rotate(app, to: .landscapeLeft)
        let wideWaiting = frames(in: app)
        assertNothingMoved(in: app, since: wide, "in landscape from an interval timer to a stretch that waits for Start")
        rotate(app, to: .portrait)

        // The count-in ends by itself after three seconds, so it is measured paused at its start.
        primary.tap()
        setPaused(true, with: primary)
        app.buttons["restartButton"].tap()
        waitFor(caption, toRead: "Get ready")
        XCTAssertEqual(phase.label, "PAUSED")
        XCTAssertTrue(app.staticTexts["in Child's Pose"].exists)
        XCTAssertEqual(app.staticTexts["timeRemaining"].label, "0:03")
        assertNothingMoved(in: app, since: waitingToStart, "from waiting for Start to the count-in")
        assertNothingMoved(in: app, since: running, "from an interval timer to a count-in")

        setPaused(false, with: primary)
        waitFor(caption, toRead: "Stretch 2 of 10")
        assertNothingMoved(in: app, since: waitingToStart, "from waiting for Start to the hold")
        setPaused(true, with: primary)
        assertNothingMoved(in: app, since: waitingToStart, "from waiting for Start to a paused hold")
        assertNothingMoved(in: app, since: running, "from an interval timer to a hold")
        rotate(app, to: .landscapeLeft)
        assertNothingMoved(in: app, since: wideWaiting, "in landscape from waiting for Start to the hold")
        assertNothingMoved(in: app, since: wide, "in landscape from an interval timer to a stretch routine")
        rotate(app, to: .portrait)
    }

    func testBuildingARoutineAndRunningItToTheEnd() {
        let app = launch("-uiTesting")
        let add = app.buttons["addTimerButton"]
        XCTAssertTrue(add.waitForExistence(timeout: Self.patience))
        add.tap()
        app.buttons["newStretchRoutine"].tap()

        let name = app.textFields["nameField"]
        let problem = app.staticTexts["editorProblem"]
        let save = app.buttons["saveButton"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(problem.label, "Name the routine to save it.")
        name.tap()
        name.typeText("Test routine")
        XCTAssertEqual(problem.label, "Add a stretch.")
        XCTAssertFalse(save.isEnabled)

        let addStretch = app.buttons["addStretchButton"]
        let stretchName = app.textFields["stretchNameField"]
        let done = app.buttons["stretchDoneButton"]
        addStretch.tap()
        XCTAssertTrue(stretchName.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(app.staticTexts["stretchProblem"].label, "Name stretch 1.")
        stretchName.tap()
        stretchName.typeText("Neck roll")
        app.buttons["duration-hold"].tap()
        let secondsWheel = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(secondsWheel.waitForExistence(timeout: Self.patience))
        secondsWheel.adjust(toPickerWheelValue: "5 s")
        done.tap()
        XCTAssertTrue(app.buttons["stretchRow-Neck roll"].waitForExistence(timeout: Self.patience))
        let editorTotal = app.staticTexts["editorTotal"]
        XCTAssertEqual(editorTotal.label, "0:08", "count-in 0:03, then hold 0:05")
        app.buttons["countInPicker"].tap()
        let fiveSeconds = app.buttons["5 s"]
        XCTAssertTrue(fiveSeconds.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(app.buttons["Off"].exists && app.buttons["3 s"].exists && app.buttons["10 s"].exists)
        fiveSeconds.tap()
        waitFor(editorTotal, toRead: "0:10")

        for _ in 0..<4 where !addStretch.isHittable { app.swipeUp() }
        addStretch.tap()
        XCTAssertTrue(stretchName.waitForExistence(timeout: Self.patience))
        stretchName.tap()
        stretchName.typeText("Side bend")
        app.segmentedControls["amountPicker"].buttons["Reps"].tap()
        XCTAssertTrue(app.steppers["repsStepper"].waitForExistence(timeout: Self.patience))
        XCTAssertFalse(app.buttons["duration-hold"].exists, "reps have a count and no length")
        XCTAssertEqual(app.steppers.count, 1, "reps have a count and no pace")
        let eachSide = app.switches["eachSideToggle"]
        eachSide.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(eachSide.value as? String, "1")
        snap(app, "27a-stretch-editor-reps")
        done.tap()
        XCTAssertTrue(app.buttons["stretchRow-Side bend"].waitForExistence(timeout: Self.patience))
        XCTAssertTrue(app.staticTexts["10 reps each side"].exists)
        XCTAssertEqual(editorTotal.label, "0:10 + reps", "reps add no time and have no count-in")

        for _ in 0..<4 where !addStretch.isHittable { app.swipeUp() }
        addStretch.tap()
        XCTAssertTrue(stretchName.waitForExistence(timeout: Self.patience))
        stretchName.tap()
        stretchName.typeText("Calf stretch")
        let link = app.textFields["stretchLinkField"]
        link.tap()
        link.typeText("https://example.com/calf")
        app.buttons["duration-hold"].tap()
        XCTAssertTrue(secondsWheel.waitForExistence(timeout: Self.patience))
        secondsWheel.adjust(toPickerWheelValue: "5 s")
        done.tap()
        XCTAssertTrue(app.buttons["stretchRow-Calf stretch"].waitForExistence(timeout: Self.patience))
        XCTAssertEqual(editorTotal.label, "0:20 + reps", "0:10, then count-in 0:05 and hold 0:05")
        XCTAssertFalse(problem.exists)
        snap(app, "28-new-routine")
        save.tap()

        let row = app.buttons["timerRow-Test routine"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(row.label.contains("3 stretches · 1 each side"), row.label)
        XCTAssertTrue(row.label.contains("0:20 + reps"), row.label)
        snap(app, "29-routine-saved")

        row.tap()
        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.patience))
        start.tap()
        let phase = app.staticTexts["phaseTitle"]
        let caption = app.staticTexts["roundLabel"]
        let clock = app.staticTexts["timeRemaining"]
        let length = app.staticTexts["holdLength"]
        let reps = app.staticTexts["repCount"]
        let prompt = app.staticTexts["waitPrompt"]
        let primary = app.buttons["primaryButton"]
        let skip = app.buttons["skipButton"]
        let howTo = app.buttons["howToButton"]
        XCTAssertTrue(length.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(phase.label, "NECK ROLL")
        XCTAssertEqual(caption.label, "Stretch 1 of 3")
        XCTAssertEqual(length.label, "0:05")
        waitFor(primary, toRead: "Start")
        XCTAssertEqual(prompt.label, "Tap Start")
        XCTAssertTrue(app.staticTexts["Up next: Side bend 10 reps"].exists)
        XCTAssertFalse(howTo.exists, "a stretch with no link offers no how-to")
        XCTAssertFalse(skip.isEnabled, "while the run waits, the big button is the only way on")
        let waiting = frames(in: app)

        primary.tap()
        XCTAssertTrue(reps.waitForExistence(timeout: Self.patience), "the count-in and the hold run out by themselves, and the next stretch waits")
        XCTAssertEqual(phase.label, "SIDE BEND")
        XCTAssertEqual(reps.label, "10 reps")
        XCTAssertEqual(caption.label, "Left side · Stretch 2 of 3")
        waitFor(primary, toRead: "Next")
        XCTAssertEqual(prompt.label, "Tap Next when done")
        XCTAssertTrue(app.staticTexts["Up next: Right side 10 reps"].exists)
        XCTAssertFalse(clock.exists)
        XCTAssertFalse(length.exists)
        assertNothingMoved(in: app, since: waiting, "from a wait for Start to a stretch counted in reps")
        snap(app, "47-next-stretch-waiting")

        primary.tap()
        waitFor(caption, toRead: "Right side · Stretch 2 of 3")
        XCTAssertTrue(reps.exists, "the right side waits for its own Next")
        XCTAssertTrue(app.staticTexts["Up next: Calf stretch 0:05"].exists)

        primary.tap()
        XCTAssertTrue(length.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(phase.label, "CALF STRETCH")
        XCTAssertEqual(caption.label, "Stretch 3 of 3")
        waitFor(primary, toRead: "Start")
        XCTAssertTrue(app.staticTexts["Up next: Finish"].exists)
        XCTAssertTrue(howTo.exists, "the how-to chip is offered while the run waits")
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertEqual(length.label, "0:05", "the last stretch waits for Start like every other")
        assertNothingMoved(in: app, since: waiting, "from one wait for Start to the next, with a How to chip")
        snap(app, "48-last-stretch-waiting")

        primary.tap()
        XCTAssertTrue(app.staticTexts["Workout complete"].waitForExistence(timeout: Self.patience), "the last hold reaches zero and the workout finishes by itself")
        XCTAssertTrue(app.buttons["doneButton"].exists)
        XCTAssertTrue(app.staticTexts["timeWorked"].label.hasPrefix("0:"), app.staticTexts["timeWorked"].label)
    }

    private func launch(_ argument: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [argument, "-undoWindow", "20"]
        app.launch()
        return app
    }

    private func waitFor(_ element: XCUIElement, toRead label: String) {
        let matches = expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
        wait(for: [matches], timeout: Self.patience)
    }

    private func rotate(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let window = app.windows.firstMatch
        let wantsWide = orientation.isLandscape
        let turned = expectation(for: NSPredicate { _, _ in (window.frame.width > window.frame.height) == wantsWide }, evaluatedWith: nil)
        wait(for: [turned], timeout: Self.patience)
        Thread.sleep(forTimeInterval: 2)
    }

    private static let fixedInPlace = ["phaseTitle", "clock", "totalRemaining", "primaryButton", "skipButton"]

    private func frames(in app: XCUIApplication) -> [String: CGRect] {
        // Every change on the run screen animates for a quarter of a second.
        Thread.sleep(forTimeInterval: 0.6)
        var frames = Dictionary(uniqueKeysWithValues: Self.fixedInPlace.map { identifier in
            (identifier, app.descendants(matching: .any).matching(identifier: identifier).firstMatch.frame)
        })
        // The digits give way to a rep count in a stretch counted in reps. Where they show, counting
        // or waiting for Start, they stay put too.
        for digits in [app.staticTexts["timeRemaining"], app.staticTexts["holdLength"]] where digits.exists {
            frames["digits"] = digits.frame
        }
        return frames
    }

    private func assertNothingMoved(in app: XCUIApplication, since before: [String: CGRect], _ when: String) {
        for (identifier, now) in frames(in: app) {
            guard let was = before[identifier] else { continue }
            // The total is set against the right edge and is as wide as its digits, so "8:21" is narrower than "38:00".
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
