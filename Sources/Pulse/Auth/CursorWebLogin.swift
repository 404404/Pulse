import AppKit
import CryptoKit
import Foundation

/// Signing Pulse in to a Cursor account. The same flow also powers a second
/// Grok Bot allowance, with a different login target.
///
/// **This is not OAuth, and calling it that would set the wrong expectations.**
/// Cursor has no authorize/token pair for a third party to drive — it has a
/// login page that takes a challenge and a nonce, and a polling endpoint that
/// hands the tokens back once the browser has finished:
///
/// 1. `GET cursor.com/loginDeepControl?challenge=…&uuid=…&mode=login&…` opens
///    in the browser. Nothing comes back to this Mac, so there is no loopback
///    port to bind and none to collide with Cursor's own sign-in.
/// 2. `GET api2.cursor.sh/auth/poll?uuid=…&verifier=…` answers 404 while the
///    browser has not finished and 200 with `accessToken` / `refreshToken`
///    once it has.
///
/// The proof-key half *is* PKCE's: a random 32 bytes base64url-encoded is the
/// verifier, and the challenge is the base64url of its SHA-256 — of the
/// **encoded string**, not of the raw bytes. Read out of Cursor's own client
/// (`Grok Bot.app/Contents/Resources/app.asar`) rather than guessed, for the
/// reason `OAuthLogin` states: a flow with one parameter wrong fails in a way
/// that looks like the user's fault.
///
/// **Not public API**, the same caveat every other borrowed route carries.
enum CursorLoginTarget: String, Equatable, Sendable {
    case cursor
    case grokBot

    var redirectTarget: String {
        switch self {
        case .cursor: "cli"
        case .grokBot: "sand"
        }
    }
}

enum CursorWebLogin {
    /// What the user is sent to, and what the poll needs afterwards.
    struct Attempt: Sendable, Equatable {
        let loginURL: URL
        let uuid: String
        let verifier: String
    }

    private static let website = URL(string: "https://cursor.com")!
    private static let backend = URL(string: "https://api2.cursor.sh")!

    /// How long to keep asking. Cursor's own client gives up after 150 tries;
    /// this is the same order and matches `OAuthLogin.patience`'s reasoning —
    /// long enough to find a password and a second factor, short enough that
    /// an abandoned sign-in releases the button.
    private static let patience: TimeInterval = 300
    private static let interval: Duration = .seconds(2)

    static func start(target: CursorLoginTarget = .grokBot) -> Attempt? {
        makeAttempt(target: target, uuid: UUID().uuidString.lowercased(), verifier: OAuthLogin.randomToken())
    }

    /// Deterministic constructor used by protocol tests and by the live flow.
    static func makeAttempt(target: CursorLoginTarget, uuid: String, verifier: String) -> Attempt? {
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded

        guard var components = URLComponents(
            url: website.appending(path: "loginDeepControl"),
            resolvingAgainstBaseURL: false
        ) else { return nil }

        components.queryItems = [
            URLQueryItem(name: "challenge", value: challenge),
            URLQueryItem(name: "uuid", value: uuid),
            URLQueryItem(name: "mode", value: "login"),
            URLQueryItem(name: "redirectTarget", value: target.redirectTarget),
        ] + (target == .grokBot
            ? [URLQueryItem(name: "supportsSelectedTeamLogin", value: "true")]
            : [])

        guard let url = components.url else { return nil }
        return Attempt(loginURL: url, uuid: uuid, verifier: verifier)
    }

    /// Opens the page and waits for the browser to finish with it.
    static func signIn(target: CursorLoginTarget = .grokBot) async throws -> AccountCredentials {
        guard let attempt = start(target: target) else { throw OAuthLogin.Failure.unsupported }

        _ = await MainActor.run { NSWorkspace.shared.open(attempt.loginURL) }

        let deadline = Date().addingTimeInterval(patience)
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: interval)

            if let credentials = try await poll(attempt) { return credentials }
        }

        throw OAuthLogin.Failure.timedOut
    }

    /// Nil while the browser has not finished.
    ///
    /// **404 is "not yet", not "wrong address"** — the nonce simply has nothing
    /// filed against it until the page completes, and Cursor's own client
    /// treats that status as a reason to ask again. A 403 carrying an error is
    /// the one refusal that ends the attempt; every other failure is a stumble
    /// and is retried, because this poll runs for minutes and one dropped
    /// connection is not a reason to send the user back to the start.
    private static func poll(_ attempt: Attempt) async throws -> AccountCredentials? {
        guard var components = URLComponents(
            url: backend.appending(path: "auth/poll"),
            resolvingAgainstBaseURL: false
        ) else { throw OAuthLogin.Failure.unsupported }

        components.queryItems = [
            URLQueryItem(name: "uuid", value: attempt.uuid),
            URLQueryItem(name: "verifier", value: attempt.verifier),
        ]
        guard let url = components.url else { throw OAuthLogin.Failure.unsupported }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await NetworkSession.shared.data(for: request)
        } catch {
            // Cancellation is not the service failing to answer — reported as
            // one, pressing Cancel writes an error into a pane the user has
            // just cleared on purpose.
            if error is CancellationError { throw error }
            try Task.checkCancellation()
            return nil
        }

        return try Self.parsePollResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }

    /// Parses one poll reply without performing network I/O.
    ///
    /// Cursor has returned both camelCase and snake_case field names. A 404 is
    /// the normal not-ready state; a 403 is fatal only when it carries an
    /// explicit provider error. Other non-success responses remain retryable.
    static func parsePollResponse(status: Int, data: Data) throws -> AccountCredentials? {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        if status == 404 { return nil }
        if status == 403,
           let said = (json?["error"] as? String) ?? (json?["error_description"] as? String),
           !said.isEmpty {
            throw OAuthLogin.Failure.refused("auth/poll: " + said)
        }
        guard status == 200 else { return nil }

        guard
            let access = (json?["accessToken"] as? String) ?? (json?["access_token"] as? String),
            !access.isEmpty
        else { throw OAuthLogin.Failure.unreadableReply }

        guard let expiry = CursorAppLogin.expiry(of: access) else {
            throw OAuthLogin.Failure.unreadableReply
        }

        let refresh = (json?["refreshToken"] as? String)
            ?? (json?["refresh_token"] as? String)
            ?? ""
        let accountID = [
            json?["userId"] as? String,
            json?["authId"] as? String,
            json?["user_id"] as? String
        ]
        .compactMap { value in value }
        .first { value in !value.isEmpty } ?? CursorAppLogin.accountID(of: access)

        return AccountCredentials(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expiry,
            accountName: nil,
            accountID: accountID
        )
    }
}
