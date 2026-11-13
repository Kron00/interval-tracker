import XCTest

/// The app is launched with `-aiStub`, so OpenAI is a stand-in inside the app and no test here
/// reaches the network or needs an account.
final class DescribeFlowUITests: XCTestCase {
    private static let patience: TimeInterval = 30

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testDescribingAWorkoutBuildsItAndSaveKeepsIt() {
        let app = launch(signedIn: true)
        openDescribe(app)

        let field = element(app, "describeField")
        let generate = app.buttons["generateButton"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.patience))
        waitFor(element(app, "accountLine"), toRead: "Using your ChatGPT plan")
        XCTAssertTrue(app.staticTexts["Only the text you type is sent to OpenAI."].exists)
        XCTAssertFalse(generate.isEnabled, "there is nothing to send yet")
        snap(app, "70-describe")

        app.buttons["example-1"].tap()
        XCTAssertEqual(field.value as? String, "15-minute hip mobility routine")
        XCTAssertTrue(generate.isEnabled)
        snap(app, "70a-described")
        generate.tap()

        let cancel = app.buttons["cancelGenerationButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(app.staticTexts["generatingTitle"].exists)
        XCTAssertTrue(app.staticTexts["15-minute hip mobility routine"].exists, "the waiting screen says what was asked for")
        XCTAssertFalse(generate.exists)
        snap(app, "71-generating")
        cancel.tap()
        XCTAssertTrue(generate.waitForExistence(timeout: Self.patience), "Cancel goes back to the description")
        XCTAssertEqual(field.value as? String, "15-minute hip mobility routine")

        generate.tap()
        let save = app.buttons["saveGeneratedButton"]
        XCTAssertTrue(save.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(app.navigationBars["Hip Mobility"].exists)
        XCTAssertEqual(app.staticTexts["detailTotal"].label, "11:57 + reps")
        XCTAssertTrue(app.staticTexts["Hip Circles"].exists)
        XCTAssertTrue(app.staticTexts["10 reps each side"].exists)
        XCTAssertTrue(app.staticTexts["1:30 each side"].exists)
        XCTAssertTrue(app.staticTexts["generationNote"].label.contains("counted in reps"))
        XCTAssertTrue(app.buttons["editGeneratedButton"].exists)
        XCTAssertTrue(app.buttons["tryAgainButton"].exists)
        snap(app, "72-result")

        app.buttons["rewordButton"].tap()
        XCTAssertTrue(generate.waitForExistence(timeout: Self.patience), "Reword goes back to the description")
        XCTAssertEqual(field.value as? String, "15-minute hip mobility routine")
        generate.tap()
        XCTAssertTrue(save.waitForExistence(timeout: Self.patience))
        save.tap()

        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.patience), "Save opens the workout, ready to start")
        XCTAssertTrue(app.navigationBars["Hip Mobility"].exists)
        XCTAssertEqual(app.staticTexts["detailTotal"].label, "11:57 + reps")
        XCTAssertTrue(app.staticTexts["Hip Circles"].exists)
        XCTAssertFalse(save.exists, "the result has closed")
        XCTAssertFalse(app.staticTexts["generationNote"].exists)
        snap(app, "74-generated-saved")
        app.buttons["Close"].tap()

        let row = app.buttons["timerRow-Hip Mobility"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(row.label.contains("8 stretches · 4 each side"), row.label)
        XCTAssertTrue(row.label.contains("11:57 + reps"), row.label)
        app.terminate()

        let relaunched = launch(signedIn: true, keepLibrary: true)
        XCTAssertTrue(relaunched.buttons["timerRow-Hip Mobility"].waitForExistence(timeout: Self.patience))
    }

    /// The third example. An interval timer has one work length and one rest length, and this
    /// description needs no more than that.
    func testTryAgainKeepsTheAnswerUntilANewOneArrives() {
        let app = launch(signedIn: true, replies: "answer never busy answer")
        openDescribe(app)
        let field = element(app, "describeField")
        XCTAssertTrue(app.buttons["example-3"].waitForExistence(timeout: Self.patience))
        app.buttons["example-3"].tap()
        XCTAssertEqual(field.value as? String, "30-minute run: 1 minute hard, 2 minutes easy")
        snap(app, "70c-example-run")
        app.buttons["generateButton"].tap()

        let save = app.buttons["saveGeneratedButton"]
        let tryAgain = app.buttons["tryAgainButton"]
        let cancel = app.buttons["cancelGenerationButton"]
        let total = app.staticTexts["detailTotal"]
        let failure = app.staticTexts["generationFailure"]
        XCTAssertTrue(save.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(app.navigationBars["1-2 Run"].exists)
        XCTAssertEqual(total.label, "30:00", "ten rounds of 1:00 hard and 2:00 easy")
        XCTAssertTrue(app.staticTexts["10 × 1:00"].exists)
        XCTAssertTrue(app.staticTexts["10 × 2:00"].exists)
        snap(app, "72c-result-run")

        tryAgain.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: Self.patience))
        XCTAssertFalse(save.exists)
        cancel.tap()
        XCTAssertTrue(save.waitForExistence(timeout: Self.patience), "Cancel during a retry goes back to the answer")
        XCTAssertTrue(app.navigationBars["1-2 Run"].exists)
        XCTAssertEqual(total.label, "30:00")
        XCTAssertFalse(failure.exists)
        XCTAssertFalse(app.buttons["generateButton"].exists, "and not to the description")

        tryAgain.tap()
        XCTAssertTrue(failure.waitForExistence(timeout: Self.patience), "a retry that fails says so")
        XCTAssertEqual(failure.label, "OpenAI is limiting requests right now. Wait a minute, then try again.")
        XCTAssertEqual(app.staticTexts["keptAnswerNote"].label, "1-2 Run is the answer you already had. You can still save it.")
        XCTAssertTrue(app.navigationBars["1-2 Run"].exists)
        XCTAssertEqual(total.label, "30:00", "the earlier answer is still shown")
        XCTAssertTrue(save.isHittable)
        snap(app, "72d-retry-failed")

        tryAgain.tap()
        XCTAssertTrue(save.waitForExistence(timeout: Self.patience))
        XCTAssertFalse(failure.exists, "a retry that succeeds shows the new answer alone")
        XCTAssertEqual(total.label, "30:00")

        app.buttons["editGeneratedButton"].tap()
        XCTAssertTrue(app.textFields["nameField"].waitForExistence(timeout: Self.patience))
        app.buttons["saveButton"].tap()
        // Changing an answer before saving it is a common way through this screen. It ends where
        // Save on the result ends: on the workout, with Start.
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: Self.patience), "Save in the editor opens the workout, ready to start")
        XCTAssertTrue(app.navigationBars["1-2 Run"].exists)
        XCTAssertEqual(app.staticTexts["detailTotal"].label, "30:00")
        XCTAssertFalse(save.exists, "the result has closed")
        snap(app, "75b-edited-and-saved")
        app.buttons["Close"].tap()
        let row = app.buttons["timerRow-1-2 Run"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(row.label.contains("30:00"), row.label)
    }

    func testAGeneratedTimerOpensInTheEditorAndIsNotSavedByItself() {
        let app = launch(signedIn: true)
        openDescribe(app)
        let generate = app.buttons["generateButton"]
        XCTAssertTrue(app.buttons["example-2"].waitForExistence(timeout: Self.patience))
        app.buttons["example-2"].tap()
        generate.tap()
        let cancel = app.buttons["cancelGenerationButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: Self.patience))
        cancel.tap()
        XCTAssertTrue(generate.waitForExistence(timeout: Self.patience))
        generate.tap()

        let edit = app.buttons["editGeneratedButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(app.navigationBars["Bike Tabata"].exists)
        XCTAssertEqual(app.staticTexts["detailTotal"].label, "11:50", "5:00, then 8 × 0:20 with 7 rests of 0:10, then 3:00")
        XCTAssertTrue(app.staticTexts["8 × 0:20"].exists)
        XCTAssertFalse(app.staticTexts["generationNote"].exists, "the model had nothing to add")
        snap(app, "72a-result-timer")

        edit.tap()
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.patience))
        XCTAssertEqual(name.value as? String, "Bike Tabata")
        XCTAssertTrue(app.navigationBars["New timer"].exists)
        XCTAssertEqual(app.staticTexts["editorTotal"].label, "11:50")
        XCTAssertTrue(app.buttons["saveButton"].isEnabled)
        snap(app, "75-generated-in-editor")
        app.buttons["Cancel"].tap()
        let save = app.buttons["saveGeneratedButton"]
        XCTAssertTrue(save.waitForExistence(timeout: Self.patience), "Cancel in the editor goes back to the answer")
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(app.navigationBars["Bike Tabata"].exists)
        XCTAssertEqual(app.staticTexts["detailTotal"].label, "11:50")
        XCTAssertFalse(name.exists)
        snap(app, "75a-back-at-the-result")

        app.buttons["describeCloseButton"].tap()
        XCTAssertTrue(app.buttons["timerRow-Norwegian 4x4"].waitForExistence(timeout: Self.patience))
        XCTAssertFalse(app.buttons["timerRow-Bike Tabata"].exists, "nothing is saved until Save")
    }

    func testSettingsShowsTheAccountTheModelAndTheKey() {
        let app = launch(signedIn: true)
        openChatGPTSettings(app)

        let status = app.staticTexts["chatGPTStatus"]
        waitFor(status, toRead: "Using ChatGPT plan")
        XCTAssertTrue(app.staticTexts["you@example.com"].exists)
        let model = app.buttons["modelPicker"]
        XCTAssertTrue(model.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(model.label.contains("gpt-6-luna"), "the smallest listed model is chosen: \(model.label)")
        XCTAssertTrue(element(app, "manageUsageLink").exists)
        snap(app, "73-settings-chatgpt")

        app.buttons["signOutButton"].tap()
        waitFor(status, toRead: "Build workouts with ChatGPT")
        XCTAssertTrue(app.buttons["continueWithChatGPT"].exists)
        XCTAssertEqual(app.buttons["continueWithChatGPT"].label, "Continue with ChatGPT")
        XCTAssertFalse(model.exists, "there is no model to choose with nothing to pay for it")
        snap(app, "73a-settings-signed-out")

        let key = app.secureTextFields["apiKeyField"]
        XCTAssertTrue(key.exists)
        XCTAssertFalse(app.buttons["saveKeyButton"].isEnabled)
        key.tap()
        key.typeText("sk-test-key")
        app.buttons["saveKeyButton"].tap()
        XCTAssertTrue(app.buttons["removeKeyButton"].waitForExistence(timeout: Self.patience))
        XCTAssertFalse(key.exists, "a saved key is never shown again")
        scrollBack(app, to: status)
        waitFor(status, toRead: "Using your API key")
        snap(app, "73b-settings-api-key")

        app.buttons["removeKeyButton"].tap()
        XCTAssertTrue(key.waitForExistence(timeout: Self.patience))
        scrollBack(app, to: status)
        waitFor(status, toRead: "Build workouts with ChatGPT")
    }

    /// Settings is a lazy list. On a small screen, typing the key scrolls the account row out of it,
    /// and a row that is off the screen is not there to be read.
    private func scrollBack(_ app: XCUIApplication, to element: XCUIElement) {
        let window = app.windows.firstMatch
        for _ in 0..<8 where !element.exists {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
    }

    /// The whole sign-in on the simulator: the system sheet opens a page, the page sends the browser to
    /// 127.0.0.1, the listener inside the app answers, and the sheet closes. The stub stands in for
    /// ChatGPT's page and for the token endpoint. Everything between them is the code that ships.
    func testSigningInThroughTheSystemSheetAndTheLoopbackListener() {
        let app = launch(signedIn: false)
        openChatGPTSettings(app)
        let status = app.staticTexts["chatGPTStatus"]
        waitFor(status, toRead: "Build workouts with ChatGPT")

        app.buttons["continueWithChatGPT"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Continue"]
        XCTAssertTrue(allow.waitForExistence(timeout: Self.patience), "iOS asks before it opens a sign-in sheet")
        let question = springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Wants to Use")).firstMatch
        XCTAssertTrue(question.label.hasPrefix("“Intervals” Wants to Use"), "iOS names the app as the home screen does: \(question.label)")
        attach(XCUIScreen.main.screenshot(), "76a-sign-in-question")
        allow.tap()

        let notice = app.alerts["You're using your ChatGPT plan"]
        XCTAssertTrue(notice.waitForExistence(timeout: Self.patience), "the listener got the answer and the sheet closed")
        snap(app, "76-plan-notice")
        notice.buttons["OK"].tap()
        waitFor(status, toRead: "Using ChatGPT plan")
        XCTAssertTrue(app.buttons["signOutButton"].exists)
        XCTAssertFalse(app.buttons["continueWithChatGPT"].exists)
    }

    func testDescribeAsksForASignInWhenNothingCanPay() {
        let app = launch(signedIn: false)
        openDescribe(app)
        XCTAssertTrue(element(app, "describeField").waitForExistence(timeout: Self.patience))
        waitFor(element(app, "accountLine"), toRead: "Sign in to use your ChatGPT plan")
        XCTAssertTrue(app.buttons["continueWithChatGPT"].exists)
        XCTAssertFalse(app.buttons["generateButton"].exists)
        snap(app, "70b-describe-signed-out")
    }

    /// `replies` is what the stand-in for OpenAI gives the descriptions in turn: "answer", "never"
    /// or "busy". Every description after them is answered. With none, the first is never answered.
    private func launch(signedIn: Bool, keepLibrary: Bool = false, replies: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            keepLibrary ? "-uiTestingKeepLibrary" : "-uiTesting", "-undoWindow", "20",
            "-aiStub", signedIn ? "signedIn" : "signedOut",
        ] + (replies.map { ["-aiStubReplies", $0] } ?? [])
        app.launch()
        return app
    }

    private func openDescribe(_ app: XCUIApplication) {
        let add = app.buttons["addTimerButton"]
        XCTAssertTrue(add.waitForExistence(timeout: Self.patience))
        add.tap()
        let describe = app.buttons["describeWorkout"]
        XCTAssertTrue(describe.waitForExistence(timeout: Self.patience))
        describe.tap()
    }

    private func openChatGPTSettings(_ app: XCUIApplication) {
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: Self.patience))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: Self.patience))
        let key = app.secureTextFields["apiKeyField"]
        let window = app.windows.firstMatch
        for _ in 0..<8 where !key.isHittable {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        XCTAssertTrue(app.staticTexts["chatGPTStatus"].waitForExistence(timeout: Self.patience))
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitFor(_ element: XCUIElement, toRead label: String) {
        let matches = expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
        wait(for: [matches], timeout: Self.patience)
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
