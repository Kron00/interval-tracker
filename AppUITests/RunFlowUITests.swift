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
        XCTAssertFalse(app.buttons["undoButton"].exists, "a skip is taken back with the back button, and there is no Undo")
        let back = app.buttons["backButton"]
        XCTAssertEqual(back.label, "Back")
        back.tap()
        waitFor(phase, toRead: "WARM-UP")
        snap(app, "04a-back-to-warm-up")
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
        back.tap()
        waitFor(phase, toRead: "WORK")
        XCTAssertEqual(app.staticTexts["roundLabel"].label, "Round 1 of 4", "back from a rest goes to the work before it")
        let workAgain = app.staticTexts["timeRemaining"].label
        XCTAssertTrue(workAgain == "4:00" || workAgain.hasPrefix("3:5"), "the round starts from the top, and it read \(workAgain)")
        snap(app, "06a-back-to-work")
        skip.tap()
        waitFor(phase, toRead: "REST")

        let done = app.buttons["doneButton"]
        var taps = 0
        while !done.exists, taps < 12 {
            if skip.exists { skip.tap() }
            taps += 1
        }
        XCTAssertTrue(done.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(taps, 8, "rest 1, then work and rest for rounds 2 to 4, then cool-down")
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
        XCTAssertFalse(app.staticTexts["endHistoryNote"].exists, "the audio check is never in History, so the dialog does not speak of it")
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
        let back = app.buttons["backButton"]
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
        XCTAssertTrue(skip.isEnabled, "a wait can skip its stretch")
        XCTAssertEqual(skip.label, "Skip stretch")
        XCTAssertTrue(back.isEnabled, "the back button stays lit in a wait")
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
        XCTAssertTrue(howTo.exists)
        XCTAssertTrue(skip.isEnabled)
        XCTAssertEqual(skip.label, "Skip stretch")
        XCTAssertTrue(back.isEnabled)
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

        // The count-in lasts three seconds, and a slow machine can take longer than that between
        // two taps. So the pause lands in the count-in or early in the hold, both of Child's Pose.
        primary.tap()
        setPaused(true, with: primary)
        XCTAssertTrue(["Get ready", "Stretch 2 of 10"].contains(caption.label), "Start leads into the count-in, and it read \(caption.label)")
        XCTAssertTrue(app.staticTexts["in Child's Pose"].exists)
        XCTAssertTrue(app.staticTexts["Up next: Cobra 0:30"].exists)
        XCTAssertFalse(length.exists)
        snap(app, "45a-count-in")
        setPaused(false, with: primary)

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

        // Skip stretch leaves a wait without Start, one side at a time, and back goes the other way the same way.
        waitFor(primary, toRead: "Start")
        XCTAssertEqual(skip.label, "Skip stretch")
        skip.tap()
        waitFor(caption, toRead: "Right side · Stretch 4 of 10")
        waitFor(primary, toRead: "Start")
        skip.tap()
        waitFor(phase, toRead: "PIGEON")
        waitFor(caption, toRead: "Left side · Stretch 5 of 10")
        waitFor(primary, toRead: "Start")
        XCTAssertEqual(length.label, "0:45", "nothing counted in")
        XCTAssertEqual(prompt.label, "Tap Start")
        XCTAssertTrue(skip.isEnabled)
        XCTAssertEqual(skip.label, "Skip stretch")
        XCTAssertTrue(back.isEnabled)
        snap(app, "47a-skip-stretch-from-wait")
        back.tap()
        waitFor(phase, toRead: "HIP FLEXOR COUCH STRETCH")
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
        back.tap()
        waitFor(caption, toRead: "Left side · Stretch 4 of 10")
        XCTAssertEqual(length.label, "0:45", "back from a hold goes to the side before, which waits for Start again")
        XCTAssertFalse(clock.exists)
        XCTAssertGreaterThan(seconds(total.label), before + 45)
        XCTAssertEqual(primary.label, "Resume", "going back keeps a paused run paused")
        snap(app, "47b-back-from-a-hold")

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

    /// With a heart-rate monitor remembered, so the readout's slot is measured in every state too.
    func testNothingMovesWhenTheRunChangesState() {
        let app = launch("-uiTesting", "-hrStub", "remembered")
        let interval = app.buttons["timerRow-Norwegian 4x4"]
        XCTAssertTrue(interval.waitForExistence(timeout: Self.patience))
        interval.tap()
        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.patience))
        start.tap()

        let phase = app.staticTexts["phaseTitle"]
        let primary = app.buttons["primaryButton"]
        let skip = app.buttons["skipButton"]
        let back = app.buttons["backButton"]
        XCTAssertTrue(phase.waitForExistence(timeout: Self.patience))
        let running = frames(in: app)
        XCTAssertNotNil(running["heartRate"], "the stand-in monitor is remembered, so the readout has its slot")
        snap(app, "30-running")

        setPaused(true, with: primary)
        XCTAssertTrue(app.staticTexts["in Warm-up"].exists)
        assertNothingMoved(in: app, since: running, "after Pause")
        snap(app, "31-paused")
        setPaused(false, with: primary)
        assertNothingMoved(in: app, since: running, "after Resume")

        skip.tap()
        waitFor(phase, toRead: "WORK")
        assertNothingMoved(in: app, since: running, "in Work after a skip")
        snap(app, "32-work-after-skip")
        back.tap()
        waitFor(phase, toRead: "WARM-UP")
        assertNothingMoved(in: app, since: running, "in the warm-up after going back")
        skip.tap()
        waitFor(phase, toRead: "WORK")

        rotate(app, to: .landscapeLeft)
        let wide = frames(in: app)
        setPaused(true, with: primary)
        assertNothingMoved(in: app, since: wide, "in landscape after Pause")
        setPaused(false, with: primary)
        skip.tap()
        waitFor(phase, toRead: "REST")
        assertNothingMoved(in: app, since: wide, "in landscape after a skip")
        attach(XCUIScreen.main.screenshot(), "33-landscape-rest")
        rotate(app, to: .portrait)

        app.buttons["endButton"].tap()
        XCTAssertTrue(app.staticTexts["endHistoryNote"].waitForExistence(timeout: Self.patience))
        app.buttons["keepGoingButton"].tap()
        XCTAssertTrue(app.buttons["keepGoingButton"].waitForNonExistence(timeout: Self.patience))
        assertNothingMoved(in: app, since: running, "after the End dialog and its line about History")

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
        XCTAssertEqual(skip.label, "Skip stretch")
        XCTAssertFalse(app.staticTexts["timeRemaining"].exists)
        assertNothingMoved(in: app, since: running, "from an interval timer to a stretch counted in reps, with a How to chip")
        snap(app, "44-wait-with-how-to")

        primary.tap()
        XCTAssertTrue(length.waitForExistence(timeout: Self.patience))
        waitFor(primary, toRead: "Start")
        let waitingToStart = frames(in: app)
        assertNothingMoved(in: app, since: running, "from an interval timer to a stretch that waits for Start")
        skip.tap()
        waitFor(phase, toRead: "COBRA")
        waitFor(primary, toRead: "Start")
        assertNothingMoved(in: app, since: waitingToStart, "after Skip stretch from a wait")
        back.tap()
        waitFor(phase, toRead: "CHILD'S POSE")
        waitFor(primary, toRead: "Start")
        assertNothingMoved(in: app, since: waitingToStart, "after going back to a wait")
        rotate(app, to: .landscapeLeft)
        let wideWaiting = frames(in: app)
        assertNothingMoved(in: app, since: wide, "in landscape from an interval timer to a stretch that waits for Start")
        rotate(app, to: .portrait)

        // The count-in ends by itself after three seconds, so it is measured paused, and a slow
        // machine may pause it early in the hold instead.
        primary.tap()
        setPaused(true, with: primary)
        XCTAssertEqual(phase.label, "PAUSED")
        XCTAssertTrue(app.staticTexts["in Child's Pose"].exists)
        XCTAssertTrue(app.staticTexts["timeRemaining"].exists)
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

        app.buttons["endButton"].tap()
        app.buttons["confirmEndButton"].tap()
        startAudioCheck(in: app)
        XCTAssertFalse(caption.exists, "a warm-up has no caption until its heads-up")
        assertNothingMoved(in: app, since: running, "in the warm-up of the audio check")
        XCTAssertTrue(caption.waitForExistence(timeout: Self.patience), "ten seconds before work the caption says to get ready")
        // The heads-up lasts ten seconds, and a slow machine can take longer than that over a
        // screenshot and the checks. A pause keeps the heads-up, so they are made on a run that
        // cannot move on.
        setPaused(true, with: primary)
        XCTAssertEqual(caption.label, "Get ready")
        snap(app, "34-heads-up")
        XCTAssertTrue(app.staticTexts["in Warm-up"].exists)
        assertNothingMoved(in: app, since: running, "when the heads-up begins")
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
        XCTAssertEqual(skip.label, "Skip stretch", "a wait can skip its stretch")
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

    /// The simulator draws the lock screen, so this shows that the Live Activity starts, follows the
    /// run and ends. It cannot show that a locked phone lights up for the heads-up.
    func testTheLockScreenFollowsARunToItsEnd() throws {
        let app = launch("-uiTesting")
        startAudioCheck(in: app)

        try showLockScreen()
        let card = springboard.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Audio check")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.patience), "the lock screen shows the workout")
        allowLiveActivities()
        snapLockScreen("50-lock-screen")

        XCTAssertTrue(springboard.staticTexts["GET READY"].waitForExistence(timeout: Self.patience), "ten seconds before work the card says to get ready")
        snapLockScreen("52-heads-up")
        XCTAssertTrue(springboard.staticTexts["WORK"].waitForExistence(timeout: Self.patience), "the card follows the run into the next phase")
        snapLockScreen("50a-lock-screen-work")
        XCTAssertTrue(springboard.staticTexts["WORKOUT COMPLETE"].waitForExistence(timeout: 60), "the card shows the finish while the phone stays locked")
        XCTAssertTrue(springboard.staticTexts["TIME WORKED"].exists)
        XCTAssertTrue(springboard.staticTexts["1:00"].exists)
        snapLockScreen("55-finished-lock-screen")

        app.activate()
        let done = app.buttons["doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.patience))
        done.tap()
        try showLockScreen()
        XCTAssertTrue(card.waitForNonExistence(timeout: Self.patience), "Done takes a finished workout off the lock screen")
    }

    func testTheDynamicIslandShowsTheRunAndOpensForTheHeadsUp() throws {
        let app = launch("-uiTesting")
        startAudioCheck(in: app)
        let started = Date.now

        XCUIDevice.shared.press(.home)
        // The Dynamic Island takes a few seconds to draw an app's first activity.
        Thread.sleep(forTimeInterval: 6)
        attach(XCUIScreen.main.screenshot(), "51-dynamic-island")
        expandTheDynamicIsland()
        attach(XCUIScreen.main.screenshot(), "51a-dynamic-island-expanded")
        collapseTheDynamicIsland()

        // The heads-up comes 20 seconds into the check. Its alert opens the island with no touch.
        Thread.sleep(until: started + 21)
        attach(XCUIScreen.main.screenshot(), "52a-heads-up-dynamic-island")
        Thread.sleep(until: started + 27)
        attach(XCUIScreen.main.screenshot(), "52b-heads-up-compact")

        // A force quit leaves the activity behind. The next launch has to clear it.
        app.terminate()
        try showLockScreen()
        let card = springboard.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Audio check")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.patience), "the activity outlives the app")
        app.launch()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: Self.patience))
        try showLockScreen()
        XCTAssertTrue(card.waitForNonExistence(timeout: Self.patience), "a launch clears the activity of a run that no longer exists")
    }

    func testTheLockScreenShowsAPausedRunAndARoutineThatWaits() throws {
        let app = launch("-uiTesting")
        let end = app.buttons["endButton"]
        let primary = app.buttons["primaryButton"]
        let skip = app.buttons["skipButton"]

        startAudioCheck(in: app)
        setPaused(true, with: primary)
        skip.tap()
        XCTAssertTrue(app.staticTexts["in Work"].waitForExistence(timeout: Self.patience))
        // iOS starts an activity only for an app that is on the screen. On a busy simulator that
        // takes seconds, and a lock that comes sooner leaves no card.
        Thread.sleep(forTimeInterval: 4)
        try showLockScreen()
        XCTAssertTrue(springboard.staticTexts["PAUSED"].waitForExistence(timeout: Self.patience), "the card shows the paused run")
        allowLiveActivities()
        XCTAssertTrue(springboard.staticTexts["WORK"].exists)
        XCTAssertTrue(springboard.staticTexts["0:10"].exists)
        XCTAssertFalse(springboard.staticTexts["WORKOUT COMPLETE"].exists)
        snapLockScreen("53-paused-lock-screen")

        app.activate()
        XCTAssertTrue(end.waitForExistence(timeout: Self.patience))
        end.tap()
        app.buttons["confirmEndButton"].tap()
        let stretch = app.buttons["timerRow-Daily Stretch"]
        XCTAssertTrue(stretch.waitForExistence(timeout: Self.patience))
        stretch.tap()
        app.buttons["startButton"].tap()
        XCTAssertTrue(app.staticTexts["repCount"].waitForExistence(timeout: Self.patience))
        waitFor(primary, toRead: "Next")
        try showLockScreen()
        let next = springboard.buttons["Next"]
        let startOnTheCard = springboard.buttons["Start"]
        XCTAssertTrue(next.waitForExistence(timeout: Self.patience), "a stretch counted in reps has its Next on the card")
        XCTAssertTrue(springboard.staticTexts["CAT-COW"].exists)
        XCTAssertTrue(springboard.staticTexts["10 reps"].exists)
        XCTAssertTrue(springboard.staticTexts["Up next: Child's Pose 0:45"].exists)
        XCTAssertFalse(startOnTheCard.exists)
        snapLockScreen("54-waiting-for-next-lock-screen")

        showDynamicIsland(of: app)
        attach(XCUIScreen.main.screenshot(), "54a-waiting-for-next-dynamic-island")
        expandTheDynamicIsland()
        attach(XCUIScreen.main.screenshot(), "54b-waiting-for-next-dynamic-island-expanded")
        collapseTheDynamicIsland()

        try showLockScreen()
        XCTAssertTrue(next.waitForExistence(timeout: Self.patience))
        next.tap()
        XCTAssertTrue(startOnTheCard.waitForExistence(timeout: Self.patience), "Next on the lock screen moves on, and the next stretch waits there too")
        XCTAssertTrue(springboard.staticTexts["CHILD'S POSE"].exists)
        XCTAssertTrue(springboard.staticTexts["Up next: Cobra 0:30"].exists)
        XCTAssertFalse(next.exists)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(springboard.staticTexts["0:45"].exists, "the card shows the length of the hold, and nothing counts until Start")
        snapLockScreen("56-waiting-for-start-lock-screen")

        app.activate()
        XCTAssertTrue(end.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(app.staticTexts["phaseTitle"].label, "CHILD'S POSE", "the app is where the lock screen left the run")
        waitFor(primary, toRead: "Start")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 4)
        attach(XCUIScreen.main.screenshot(), "56a-waiting-for-start-dynamic-island")
        expandTheDynamicIsland()
        attach(XCUIScreen.main.screenshot(), "56b-waiting-for-start-dynamic-island-expanded")
        XCTAssertTrue(startOnTheCard.exists, "the opened island has the button too")
        startOnTheCard.tap()
        // The count-in lasts three seconds and the hold 45, so the screenshots are for looking at:
        // the island two seconds after the tap, then the hold twice. The simulator has taken up to
        // three seconds to hand a tap to the app, so the island may still show the wait.
        Thread.sleep(forTimeInterval: 2)
        attach(XCUIScreen.main.screenshot(), "57-after-start-dynamic-island")
        try showLockScreen()
        XCTAssertTrue(startOnTheCard.waitForNonExistence(timeout: Self.patience), "a hold that counts has no button")
        snapLockScreen("58-hold-lock-screen")
        Thread.sleep(forTimeInterval: 2)
        attach(XCUIScreen.main.screenshot(), "58a-hold-lock-screen-later")

        app.activate()
        XCTAssertTrue(end.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(primary.label, "Pause", "Start in the island began the stretch")
        XCTAssertEqual(app.staticTexts["phaseTitle"].label, "CHILD'S POSE")

        // The longest name in Daily Stretch takes two lines on the card, which is the tallest it gets.
        skip.tap()
        waitFor(primary, toRead: "Start")
        primary.tap()
        waitFor(primary, toRead: "Pause")
        skip.tap()
        waitFor(app.staticTexts["phaseTitle"], toRead: "HIP FLEXOR COUCH STRETCH")
        try showLockScreen()
        XCTAssertTrue(startOnTheCard.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(startOnTheCard.isHittable)
        XCTAssertTrue(springboard.staticTexts["Up next: Right side 0:45"].exists)
        snapLockScreen("56c-two-line-name-waiting-lock-screen")

        app.activate()
        XCTAssertTrue(end.waitForExistence(timeout: Self.patience))
        end.tap()
        app.buttons["confirmEndButton"].tap()
        XCTAssertTrue(stretch.waitForExistence(timeout: Self.patience))
        try showLockScreen()
        XCTAssertTrue(springboard.staticTexts["HIP FLEXOR COUCH STRETCH"].waitForNonExistence(timeout: Self.patience), "ending the workout takes the activity off the lock screen")
        snapLockScreen("59-ended-lock-screen")
    }

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// Locks the simulator and wakes its screen, which leaves it on the lock screen.
    private func showLockScreen() throws {
        let lock = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: lock) else {
            throw XCTSkip("This Xcode cannot lock the simulator, so the lock screen cannot be shown.")
        }
        // A test that fails on the lock screen would leave the simulator locked, and the next test
        // run could not bring its app to the front.
        addTeardownBlock { XCUIApplication().activate() }
        XCUIDevice.shared.perform(lock)
        Thread.sleep(forTimeInterval: 1.5)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// Under an app's first activity iOS asks whether to allow it, and then whether to always allow
    /// it. Each test that goes to the lock screen answers, so none depends on another having run first.
    private func allowLiveActivities() {
        for answer in ["Allow", "Always Allow"] {
            let button = springboard.buttons[answer]
            if button.waitForExistence(timeout: 2) { button.tap() }
        }
    }

    /// The card cross-fades from one state to the next, and its new text can be read before the fade is over.
    private func snapLockScreen(_ name: String) {
        Thread.sleep(forTimeInterval: 1)
        attach(XCUIScreen.main.screenshot(), name)
    }

    /// Leaves the app for the home screen, where its activity shows in the Dynamic Island.
    private func showDynamicIsland(of app: XCUIApplication) {
        app.activate()
        XCTAssertTrue(app.buttons["endButton"].waitForExistence(timeout: Self.patience))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 4)
    }

    private func expandTheDynamicIsland() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 1)
    }

    private func collapseTheDynamicIsland() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
    }

    private func startAudioCheck(in app: XCUIApplication) {
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: Self.patience))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: Self.patience))
        let check = app.buttons["audioCheckButton"]
        for _ in 0..<6 where !check.isHittable { app.swipeUp() }
        check.tap()
        XCTAssertTrue(app.staticTexts["phaseTitle"].waitForExistence(timeout: Self.patience))
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
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
        // The heart-rate readout has a slot only while a monitor is remembered.
        let heartRate = app.descendants(matching: .any)["heartRate"]
        if heartRate.exists { frames["heartRate"] = heartRate.frame }
        return frames
    }

    private func assertNothingMoved(in app: XCUIApplication, since before: [String: CGRect], _ when: String) {
        let after = frames(in: app)
        XCTAssertEqual(before["heartRate"] == nil, after["heartRate"] == nil, "the heart-rate readout came or went \(when)")
        for (identifier, now) in after {
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
