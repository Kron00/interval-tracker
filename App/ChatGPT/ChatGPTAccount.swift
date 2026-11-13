import Foundation

/// Everything the app keeps about the account. It is stored as one Keychain item and nowhere else.
struct Vault: Codable, Equatable, Sendable {
    /// Names this install to OpenAI. It is made once and outlives a sign-out.
    var hostID = UUID()
    /// The client id that the first sign-in was issued. It belongs to one ChatGPT user.
    var clientID: String?
    var session: Session?
    var apiKey: String?

    struct Session: Codable, Equatable, Sendable {
        var accessToken: String
        var refreshToken: String
        var scope: String
        var expiresAt: Date
        var email: String?

        var allowsPlanUsage: Bool {
            scope.split(separator: " ").contains { $0 == OpenAI.planUsageScope }
        }
    }
}

protocol VaultStore: Sendable {
    func load() -> Vault?
    func save(_ vault: Vault)
}

enum AccountStatus: Equatable, Sendable {
    case signedOut
    case signingIn
    case planUsage
    /// Signed in, and the plan may not be spent: the user declined it, or the plan does not offer it.
    case signedInWithoutPlanUsage
    /// Not signed in, with an API key to pay.
    case keyOnly
}

/// What the screens show of the account. All of it follows from the vault.
struct AccountSummary: Equatable, Sendable {
    let status: AccountStatus
    let hasAPIKey: Bool
    let email: String?

    init(_ vault: Vault = Vault()) {
        hasAPIKey = vault.apiKey != nil
        email = vault.session?.email
        status = switch vault.session {
        case let session? where session.allowsPlanUsage: .planUsage
        case .some: .signedInWithoutPlanUsage
        case nil: hasAPIKey ? .keyOnly : .signedOut
        }
    }

    /// Whether a request can be paid for, by the plan or by the key.
    var canPay: Bool { status == .planUsage || hasAPIKey }
}

/// What goes in the Authorization header of a request, and who is billed for it.
enum Bearer: Equatable, Sendable {
    case plan(String)
    case apiKey(String)

    var secret: String {
        switch self {
        case .plan(let secret), .apiKey(let secret): secret
        }
    }
}

enum AccountProblem: Error, Equatable, Sendable {
    case signedOut
    case planUsageOff
    /// The refresh token is no longer good. The session was cleared.
    case signInAgain
    case unreachable
}

/// The ChatGPT sign-in and the API key: what is stored, and how the tokens are exchanged, refreshed and
/// revoked. It is an actor so that the Keychain and the token responses are never handled on the main thread.
actor ChatGPTAccount {
    private let transport: any OpenAITransport
    private let store: any VaultStore
    private let now: @Sendable () -> Date
    private lazy var vault = store.load() ?? Vault()
    private var refresh: Task<Result<Vault.Session, AccountProblem>, Never>?

    /// A token this close to its end is replaced before use, so a request never starts with one that
    /// expires on the way.
    private static let refreshMargin: TimeInterval = 120
    /// What OpenAI documents for an access token, for an answer that does not say.
    private static let documentedLifetime: TimeInterval = 3600
    private static let endsTheSession: Set = [
        "invalid_grant", "refresh_token_expired", "refresh_token_reused", "refresh_token_invalidated",
    ]

    init(transport: any OpenAITransport, store: any VaultStore, now: @escaping @Sendable () -> Date = { .now }) {
        self.transport = transport
        self.store = store
        self.now = now
    }

    var summary: AccountSummary { AccountSummary(vault) }

    func beginSignIn(port: UInt16, askAgain: Bool) -> (attempt: SignInAttempt, page: URL) {
        // A new install has just made its host id. It has to be the same one at the next sign-in.
        store.save(vault)
        let attempt = SignInAttempt(port: port, clientID: vault.clientID)
        return (attempt, attempt.authorizeURL(hostID: vault.hostID, askAgain: askAgain))
    }

    func finishSignIn(_ attempt: SignInAttempt, _ grant: SignInGrant) async throws(SignInProblem) {
        let reply: (status: Int, body: Data)
        do {
            reply = try await transport.send(attempt.exchange(grant))
        } catch {
            throw .unreachable
        }
        guard reply.status == 200, let tokens = TokenResponse(body: reply.body),
              let refreshToken = tokens.refreshToken,
              let claims = tokens.idToken.flatMap(IDTokenClaims.init), claims.nonce == attempt.nonce
        else { throw .refused }
        vault.clientID = grant.clientID
        vault.session = Vault.Session(
            accessToken: tokens.accessToken, refreshToken: refreshToken, scope: tokens.scope ?? "",
            expiresAt: now().addingTimeInterval(tokens.expiresIn ?? Self.documentedLifetime), email: claims.email)
        store.save(vault)
    }

    /// The plan's token when the plan may be spent, refreshed first if it is about to expire.
    /// Otherwise the API key.
    func bearer() async throws(AccountProblem) -> Bearer {
        if let session = vault.session, session.allowsPlanUsage {
            switch await freshSession() {
            case .success(let fresh): return .plan(fresh.accessToken)
            case .failure(let problem): throw problem
            }
        }
        if let apiKey = vault.apiKey { return .apiKey(apiKey) }
        throw vault.session == nil ? .signedOut : .planUsageOff
    }

    /// The server turned `bearer` down, so the next request must not use it again.
    func rejected(_ bearer: Bearer) {
        if case .plan(let token) = bearer, vault.session?.accessToken == token {
            vault.session?.expiresAt = .distantPast
        }
    }

    func signOut() async {
        let session = vault.session
        let clientID = vault.clientID
        vault.session = nil
        vault.clientID = nil
        store.save(vault)
        guard let session, let clientID else { return }
        _ = try? await transport.send(.form(OpenAI.revoke, [
            "token": session.refreshToken, "token_type_hint": "refresh_token", "client_id": clientID,
        ]))
    }

    func setAPIKey(_ key: String?) {
        let key = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        vault.apiKey = key?.isEmpty == false ? key : nil
        store.save(vault)
    }

    /// Every refresh rotates the refresh token, and the old one stops working. Two refreshes at once
    /// would leave one of them holding a dead token, so every caller waits for the same request.
    private func freshSession() async -> Result<Vault.Session, AccountProblem> {
        if let refresh { return await refresh.value }
        guard let session = vault.session, let clientID = vault.clientID else { return .failure(.signedOut) }
        guard session.expiresAt.timeIntervalSince(now()) < Self.refreshMargin else { return .success(session) }
        let request = Task { await self.refreshed(session, clientID: clientID) }
        refresh = request
        defer { refresh = nil }
        return await request.value
    }

    private func refreshed(_ session: Vault.Session, clientID: String) async -> Result<Vault.Session, AccountProblem> {
        let reply = try? await transport.send(.form(OpenAI.token, [
            "grant_type": "refresh_token", "client_id": clientID, "refresh_token": session.refreshToken,
            "resource": OpenAI.resource,
        ]))
        // A sign-out while the request was out must not be undone by a late answer.
        guard vault.session?.refreshToken == session.refreshToken else { return .failure(.signedOut) }
        guard let reply else { return .failure(.unreachable) }
        if reply.status == 200, let tokens = TokenResponse(body: reply.body) {
            var renewed = session
            renewed.accessToken = tokens.accessToken
            renewed.refreshToken = tokens.refreshToken ?? session.refreshToken
            renewed.scope = tokens.scope ?? session.scope
            renewed.expiresAt = now().addingTimeInterval(tokens.expiresIn ?? Self.documentedLifetime)
            vault.session = renewed
            store.save(vault)
            return .success(renewed)
        }
        guard let code = OpenAI.Failure(body: reply.body).code, Self.endsTheSession.contains(code) else {
            return .failure(.unreachable)
        }
        vault.session = nil
        store.save(vault)
        return .failure(.signInAgain)
    }
}
