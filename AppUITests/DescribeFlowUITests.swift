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

        let row = app.buttons["timerRow-Hip Mobility"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.patience))
        XCTAssertTrue(row.label.contains("8 stretches · 4 each side"), row.label)
        XCTAssertTrue(row.label.contains("11:57 + reps"), row.label)
        snap(app, "74-generated-saved")
        app.terminate()

        let relaunched = launch(signedIn: true, keepLibrary: true)
        XCTAssertTrue(relaunched.buttons["timerRow-Hip Mobility"].waitForExistence(timeout: Self.patience))
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
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Continue"]
        XCTAssertTrue(allow.waitForExistence(timeout: Self.patience), "iOS asks before it opens a sign-in sheet")
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

    private func launch(signedIn: Bool, keepLibrary: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            keepLibrary ? "-uiTestingKeepLibrary" : "-uiTesting", "-undoWindow", "20",
            "-aiStub", signedIn ? "signedIn" : "signedOut",
        ]
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
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
