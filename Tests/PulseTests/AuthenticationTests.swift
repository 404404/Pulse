import Foundation
import Testing
@testable import Pulse

@Suite("Pulse-managed authentication")
struct AuthenticationTests {
    private static let future = Date(timeIntervalSince1970: 2_000_000_000)

    private static func jwt(_ claims: [String: Any]) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payload = try JSONSerialization.data(withJSONObject: claims)
        return "\(header.base64URLEncoded).\(payload.base64URLEncoded).signature"
    }

    private static func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    @Test("Codex keeps its device fallback and Grok keeps its device flow configuration")
    func deviceConfigurations() throws {
        let codex = try #require(OAuthLogin.Configuration.of(.codex))
        #expect(codex.authorize.absoluteString == "https://auth.openai.com/oauth/authorize")
        #expect(codex.token.absoluteString == "https://auth.openai.com/oauth/token")
        #expect(codex.clientID == "app_EMoamEEZ73f0CkXaXp7hrann")
        #expect(codex.scopes == [
            "openid", "profile", "email", "offline_access",
            "api.connectors.read", "api.connectors.invoke"
        ])
        guard let codexFlow = codex.deviceFlow else {
            Issue.record("Codex lost its OpenAI device flow")
            return
        }
        guard case .openAI(let codexBase) = codexFlow else {
            Issue.record("Codex changed to the RFC 8628 flow")
            return
        }
        #expect(codexBase.absoluteString == "https://auth.openai.com/api/accounts")

        let grok = try #require(OAuthLogin.Configuration.of(.grok))
        #expect(grok.token.absoluteString == "https://auth.x.ai/oauth2/token")
        #expect(grok.clientID == "b1a00492-073a-47ea-816f-4c329264a828")
        #expect(grok.scopes == ["openid", "email", "offline_access", "grok-cli:access"])
        guard let grokFlow = grok.deviceFlow else {
            Issue.record("Grok lost its device flow")
            return
        }
        guard case .standard(let grokEndpoint) = grokFlow else {
            Issue.record("Grok changed away from RFC 8628")
            return
        }
        #expect(grokEndpoint.absoluteString == "https://auth.x.ai/oauth2/device/code")
    }

    @Test("Codex credentials prefer the ChatGPT account claim and keep email labels")
    func codexIdentityParsing() throws {
        let access = try Self.jwt(["sub": "access-sub"])
        let idToken = try Self.jwt([
            "email": "person@example.com",
            "https://api.openai.com/auth": ["chatgpt_account_id": "chatgpt-account-1"]
        ])

        let credentials = try OAuthLogin.credentials(from: [
            "access_token": access,
            "refresh_token": "refresh-a",
            "expires_in": NSNumber(value: 3_600),
            "id_token": idToken
        ])

        #expect(credentials.accountID == "chatgpt-account-1")
        #expect(credentials.accountName == "person@example.com")
        #expect(credentials.refreshToken == "refresh-a")
        #expect(credentials.expiresAt > Date())
    }

    @Test("Grok credentials accept camel case replies and use the token subject")
    func grokIdentityParsing() throws {
        let token = try Self.jwt(["sub": "xai-user-1"])
        let credentials = try OAuthLogin.credentials(from: [
            "accessToken": token,
            "refreshToken": "refresh-b",
            "expiresIn": "3600"
        ])

        #expect(credentials.accountID == "xai-user-1")
        #expect(credentials.accountName == nil)
        #expect(credentials.refreshToken == "refresh-b")
    }

    @Test("Cursor and Grok Bot use separate redirect targets with the encoded verifier vector")
    func cursorPKCEAndTargets() throws {
        let verifier = Data((0..<32).map { UInt8($0) }).base64URLEncoded
        #expect(verifier == "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")

        let cursor = try #require(CursorWebLogin.makeAttempt(
            target: .cursor,
            uuid: "cursor-test",
            verifier: verifier
        ))
        let cursorComponents = try #require(URLComponents(
            url: cursor.loginURL,
            resolvingAgainstBaseURL: false
        ))
        let cursorQuery = try #require(cursorComponents.queryItems)
        let cursorValues = Dictionary(uniqueKeysWithValues: cursorQuery.compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(cursorValues["redirectTarget"] == "cli")
        #expect(cursorValues["mode"] == "login")
        #expect(cursorValues["uuid"] == "cursor-test")
        #expect(cursorValues["challenge"] == "6oZqdX5MOLq_qBJ8vppAnT4fk6AP8UiP9zX8-Rev_9A")
        #expect(cursorValues["supportsSelectedTeamLogin"] == nil)

        let grokBot = try #require(CursorWebLogin.makeAttempt(
            target: .grokBot,
            uuid: "grok-bot-test",
            verifier: verifier
        ))
        let grokBotComponents = try #require(URLComponents(
            url: grokBot.loginURL,
            resolvingAgainstBaseURL: false
        ))
        let grokBotQuery = try #require(grokBotComponents.queryItems)
        let grokBotValues = Dictionary(uniqueKeysWithValues: grokBotQuery.compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(grokBotValues["redirectTarget"] == "sand")
        #expect(grokBotValues["supportsSelectedTeamLogin"] == "true")
    }

    @Test("Cursor poll handles pending, both token spellings, refusal, and malformed replies")
    func cursorPollStates() throws {
        let pending = try CursorWebLogin.parsePollResponse(status: 404, data: Data())
        let transient = try CursorWebLogin.parsePollResponse(status: 500, data: Data())
        #expect(pending == nil)
        #expect(transient == nil)

        let token = try Self.jwt([
            "sub": "auth0|user-123",
            "exp": 2_000_000_000
        ])
        let camel = try Self.json([
            "accessToken": token,
            "refreshToken": "cursor-refresh",
            "userId": "user-123"
        ])
        let parsed = try CursorWebLogin.parsePollResponse(status: 200, data: camel)
        let credentials = try #require(parsed)
        #expect(credentials.accessToken == token)
        #expect(credentials.refreshToken == "cursor-refresh")
        #expect(credentials.accountID == "user-123")
        #expect(credentials.expiresAt == Self.future)

        let snake = try Self.json([
            "access_token": token,
            "refresh_token": "cursor-refresh-snake",
            "user_id": "user-123"
        ])
        let snakeParsed = try CursorWebLogin.parsePollResponse(status: 200, data: snake)
        let snakeCredentials = try #require(snakeParsed)
        #expect(snakeCredentials.refreshToken == "cursor-refresh-snake")

        let refusal = try Self.json(["error": "invalid_grant"])
        #expect(throws: OAuthLogin.Failure.refused("auth/poll: invalid_grant")) {
            try CursorWebLogin.parsePollResponse(status: 403, data: refusal)
        }
        #expect(throws: OAuthLogin.Failure.unreadableReply) {
            try CursorWebLogin.parsePollResponse(status: 200, data: Data("not-json".utf8))
        }
    }

    @Test("Cursor session uses the cookie account suffix while retaining full subject identity")
    func cursorSessionFromManagedToken() throws {
        let token = try Self.jwt([
            "sub": "auth0|user-123",
            "exp": 2_000_000_000
        ])
        let session = try #require(CursorAppLogin.session(from: token))
        #expect(session.cookie == "WorkosCursorSessionToken=user-123%3A%3A\(token)")
        #expect(CursorAppLogin.accountID(of: token) == "auth0|user-123")
        #expect(CursorAppLogin.expiry(of: token) == Self.future)
    }

    @Test("Codex browser authorization uses its registered loopback redirect and PKCE")
    func codexBrowserAuthorization() throws {
        let codex = try #require(OAuthLogin.Configuration.of(.codex))
        #expect(codex.fixedPort == 1455)
        #expect(codex.fallbackPort == 1457)
        let url = try #require(OAuthLogin.authorizeURL(
            codex,
            redirect: "http://localhost:1455/auth/callback",
            challenge: "challenge",
            state: "state"
        ))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: try #require(components.queryItems).compactMap { item in
            item.value.map { value in (item.name, value) }
        })
        #expect(values["response_type"] == "code")
        #expect(values["redirect_uri"] == "http://localhost:1455/auth/callback")
        #expect(values["code_challenge"] == "challenge")
        #expect(values["code_challenge_method"] == "S256")
        #expect(values["state"] == "state")
        #expect(values["device_code"] == nil)
    }

    @Test("Loopback callbacks reject wrong state, duplicate fields and provider errors")
    func loopbackCallbackValidation() throws {
        let valid = try #require(URLComponents(string: "http://localhost:1455/auth/callback?code=abc%2B123&state=state"))
        #expect(try LoopbackCallback.callbackCode(from: valid, path: "/auth/callback", expectedState: "state") == "abc+123")

        let wrongState = try #require(URLComponents(string: "http://localhost:1455/auth/callback?code=abc&state=other"))
        #expect(throws: OAuthLogin.Failure.cancelled) {
            try LoopbackCallback.callbackCode(from: wrongState, path: "/auth/callback", expectedState: "state")
        }

        let duplicate = try #require(URLComponents(string: "http://localhost:1455/auth/callback?code=abc&code=def&state=state"))
        #expect(throws: OAuthLogin.Failure.refused("Duplicate callback parameter.")) {
            try LoopbackCallback.callbackCode(from: duplicate, path: "/auth/callback", expectedState: "state")
        }

        let refused = try #require(URLComponents(string: "http://localhost:1455/auth/callback?error=access_denied&state=state"))
        #expect(throws: OAuthLogin.Failure.refused("access_denied")) {
            try LoopbackCallback.callbackCode(from: refused, path: "/auth/callback", expectedState: "state")
        }
    }

    @Test("Credential sources default to Local and persist without changing extras")
    func credentialSources() {
        let key = "settings.credentialSources.v1"
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defer { defaults.set(previous, forKey: key) }

        let settings = AppSettings(credentialSources: [Provider.codex.rawValue: ProviderCredentialSource.auth.rawValue])
        #expect(settings.credentialSource(for: AccountKey(.codex)) == .auth)
        #expect(settings.credentialSource(for: AccountKey(.grokBot)) == .local)
        #expect(settings.credentialSource(for: AccountKey(.codex, slot: "work")) == .auth)

        settings.setCredentialSource(.local, for: AccountKey(.codex))
        #expect(settings.credentialSource(for: AccountKey(.codex)) == .local)
        #expect(defaults.dictionary(forKey: key)?[Provider.codex.rawValue] as? String == ProviderCredentialSource.local.rawValue)

        settings.setCredentialSource(.auth, for: AccountKey(.codex, slot: "work"))
        #expect(settings.credentialSource(for: AccountKey(.codex, slot: "work")) == .auth)
    }

    @Test("Newer managed credentials win and duplicate identities compare without display names")
    func renewalAndDeduplicationPolicy() {
        let old = AccountCredentials(
            accessToken: "old",
            refreshToken: "old-refresh",
            expiresAt: Date(timeIntervalSince1970: 1_000),
            accountName: "same",
            accountID: "remote-1"
        )
        let newer = AccountCredentials(
            accessToken: "new",
            refreshToken: "new-refresh",
            expiresAt: Date(timeIntervalSince1970: 2_000),
            accountName: "same",
            accountID: "remote-1"
        )
        let other = AccountCredentials(
            accessToken: "other",
            refreshToken: "other-refresh",
            expiresAt: Date(timeIntervalSince1970: 3_000),
            accountName: "same",
            accountID: "remote-2"
        )

        #expect(!AccountCredentialStore.shouldAcceptRenewal(existing: newer, candidate: old))
        #expect(AccountCredentialStore.shouldAcceptRenewal(existing: old, candidate: newer))
        #expect(!AccountCredentialStore.shouldAcceptRenewal(existing: newer, candidate: newer))
        #expect(AccountCredentialStore.hasSameStableIdentity(old, newer))
        #expect(!AccountCredentialStore.hasSameStableIdentity(old, other))
        #expect(!AccountCredentialStore.hasSameStableIdentity(old, AccountCredentials(
            accessToken: "missing",
            refreshToken: "missing",
            expiresAt: newer.expiresAt,
            accountName: "same",
            accountID: nil
        )))
    }

    @Test("Provider and authentication source remain separate")
    func authenticationSources() {
        #expect(AccountKey(.codex).authenticationSource == .localApplication)
        #expect(AccountKey(.codex, slot: "work").authenticationSource == .pulseManaged)
        #expect(Provider.codex.supportsPulseManagedLogin)
        #expect(Provider.grok.supportsPulseManagedLogin)
        #expect(Provider.cursor.supportsPulseManagedLogin)
        #expect(Provider.grokBot.supportsPulseManagedLogin)
        #expect(Provider.cursor.supportsMultipleAccounts)
        #expect(Provider.grokBot.supportsMultipleAccounts)
    }
}
