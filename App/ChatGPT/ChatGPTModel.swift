import Foundation
import Observation

/// How the sign-in page is shown.
enum SignInRoute: Equatable {
    /// The system's sign-in sheet, inside the app.
    case sheet
    /// Safari. The app is in the background while the user signs in, so iOS may have suspended it by
    /// the time ChatGPT sends the browser back. The user then pastes the address Safari could not open.
    case safari
}

/// What the screens see of ChatGPT: the account, the model list, and the two things a user can
/// start, a sign-in and a generation. The work itself is done off the main thread by `ChatGPTAccount`
/// and `WorkoutGenerator`.
@MainActor @Observable
final class ChatGPTModel {
    private(set) var models: [String] = []
    /// Why the last sign-in did not finish, in words.
    private(set) var signInProblem: String?
    /// The one-time notice that OpenAI asks for when plan usage is first granted.
    var planNoticeIsShown = false
    var model: String? {
        didSet { defaults.set(model, forKey: Key.model) }
    }

    private var summary = AccountSummary()
    private var attempt: Attempt?

    @ObservationIgnored private let account: ChatGPTAccount
    @ObservationIgnored private let generator: WorkoutGenerator
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let web = WebSignIn()
    @ObservationIgnored private let openInSafari: (URL) -> Void
    @ObservationIgnored private let signInPage: (URL) -> URL

    private enum Key {
        static let model = "chatGPTModel"
        static let planNoticeWasShown = "chatGPTPlanNoticeWasShown"
    }

    private struct Attempt {
        let route: SignInRoute
        let events: AsyncStream<SignInEvent>.Continuation
    }

    private enum SignInEvent {
        case callback(String, pasted: Bool)
        case sheetClosed
        case cancelled
        case timedOut
    }

    /// Long enough for a password manager and a second factor. The listener is not left open after it.
    private static let signInTimeLimit: Duration = .seconds(600)
    /// The port in the redirect address when no listener could start. Nothing listens on it, and the
    /// sign-in is finished by pasting the address.
    private static let portWithoutListener: UInt16 = 1455

    /// `signInPage` turns OpenAI's sign-in address into the one to open. Only the stub changes it.
    init(account: ChatGPTAccount, generator: WorkoutGenerator, defaults: UserDefaults = .standard,
         openInSafari: @escaping (URL) -> Void, signInPage: @escaping (URL) -> URL = { $0 }) {
        self.account = account
        self.generator = generator
        self.defaults = defaults
        self.openInSafari = openInSafari
        self.signInPage = signInPage
        model = defaults.string(forKey: Key.model)
    }

    var status: AccountStatus { attempt == nil ? summary.status : .signingIn }
    var hasAPIKey: Bool { summary.hasAPIKey }
    var email: String? { summary.email }
    var canPay: Bool { summary.canPay }
    /// The route of the sign-in in progress. The address can be pasted only for `.safari`.
    var signInRoute: SignInRoute? { attempt?.route }

    /// Reads the account from the Keychain. The screens call it when they appear.
    func load() async {
        summary = await account.summary
    }

    func signIn(by route: SignInRoute, askAgain: Bool = false) async {
        guard attempt == nil else { return }
        signInProblem = nil
        let (events, feed) = AsyncStream.makeStream(of: SignInEvent.self)
        attempt = Attempt(route: route, events: feed)
        let reply: LoopbackCallback.Reply = route == .sheet
            ? .redirect(WebSignIn.done) : .page("Signed in. Go back to Intervals.")
        let listener = try? await LoopbackCallback.start(reply: reply) { feed.yield(.callback($0, pasted: false)) }
        let begun = await account.beginSignIn(port: listener?.port ?? Self.portWithoutListener, askAgain: askAgain)
        let page = signInPage(begun.page)
        switch route {
        case .sheet: web.open(page) { feed.yield(.sheetClosed) }
        case .safari: openInSafari(page)
        }
        let timeLimit = Task {
            guard (try? await Task.sleep(for: Self.signInTimeLimit)) != nil else { return }
            feed.yield(.timedOut)
        }

        var outcome: Result<SignInGrant, SignInProblem>?
        waiting: for await event in events {
            switch event {
            case .callback(let address, let pasted):
                do {
                    outcome = .success(try begun.attempt.grant(from: address))
                    break waiting
                } catch {
                    if error == .denied || error == .refused {
                        outcome = .failure(error)
                        break waiting
                    }
                    // Not an answer to this attempt. A stray request to the listener is ignored, and
                    // a wrong paste can be corrected.
                    if pasted { signInProblem = error.message }
                }
            case .sheetClosed, .cancelled:
                break waiting
            case .timedOut:
                outcome = .failure(.timedOut)
                break waiting
            }
        }
        timeLimit.cancel()
        listener?.stop()
        web.close()

        switch outcome {
        case .success(let grant):
            do {
                try await account.finishSignIn(begun.attempt, grant)
                signInProblem = nil
            } catch {
                signInProblem = error.message
            }
        case .failure(let problem):
            signInProblem = problem.message
        case nil:
            break
        }
        attempt = nil
        await accountChanged()
    }

    /// Finishes a Safari sign-in with the address that Safari was sent to and could not open.
    func paste(_ address: String) {
        attempt?.events.yield(.callback(address, pasted: true))
    }

    func cancelSignIn() {
        attempt?.events.yield(.cancelled)
    }

    func signOut() async {
        await account.signOut()
        await accountChanged()
    }

    func setAPIKey(_ key: String?) async {
        await account.setAPIKey(key)
        await accountChanged()
    }

    func loadModels() async {
        guard canPay, let listed = try? await generator.models() else { return }
        choose(from: listed)
    }

    func generate(_ description: String) async -> Result<GeneratedWorkout, GenerationFailure> {
        do {
            if model == nil { choose(from: try await generator.models()) }
            guard let model else { return .failure(.noModels) }
            return .success(try await generator.generate(description, model: model))
        } catch {
            // A failed refresh ends the sign-in, and the screens have to show that.
            summary = await account.summary
            return .failure(error)
        }
    }

    private func choose(from listed: [String]) {
        models = listed
        if model.map(listed.contains) != true { model = ModelList.smallest(of: listed) }
    }

    private func accountChanged() async {
        summary = await account.summary
        if summary.status == .planUsage, !defaults.bool(forKey: Key.planNoticeWasShown) {
            defaults.set(true, forKey: Key.planNoticeWasShown)
            planNoticeIsShown = true
        }
        if canPay {
            await loadModels()
        } else {
            models = []
        }
    }
}
