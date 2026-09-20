import Foundation

/// The login Pulse holds for one account it signed in to itself.
///
/// This is the point where Pulse stops only *borrowing* credentials. Every
/// other route reads a token some other tool already stored; an added account
/// has no such tool behind it, so Pulse keeps the tokens and renews them.
struct AccountCredentials: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    /// When the access token stops being accepted. Renewal happens before
    /// this, not after a request has already been refused.
    var expiresAt: Date
    /// What the provider called the account when it was added, used to seed
    /// the label so two subscriptions are not both called "Codex".
    var accountName: String?
    /// Codex's usage endpoint wants the account named in a header of its own,
    /// and the token is the only place it appears.
    var accountID: String?

    /// A minute's headroom: a token that expires while the request is in
    /// flight comes back refused, and the retry costs more than renewing early.
    var isFresh: Bool { expiresAt.timeIntervalSinceNow > 60 }

    /// A provider-stable identity used for managed-account de-duplication.
    /// Missing identity is deliberately not treated as a match.
    var stableIdentity: String? {
        guard let accountID, !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return accountID
    }
}

/// Where those logins are kept: encrypted, in Pulse's own folder, one file for
/// all of them, owner-only.
///
/// Separate from `APIKeyStore` on purpose. A pasted API key and a full OAuth
/// login are different things with different lifetimes, and a corrupt file
/// should not be able to take both down at once.
enum AccountCredentialStore {
    private static let purpose = "Pulse account logins"
    private static let lock = NSLock()

    private static var file: URL {
        PulseStorage.directory.appending(path: "accounts.dat")
    }

    static func credentials(for account: AccountKey) -> AccountCredentials? {
        lock.lock()
        defer { lock.unlock() }
        return load()?[account.id]
    }

    /// Stores a login, or forgets one when nil is passed.
    @discardableResult
    static func set(_ credentials: AccountCredentials?, for account: AccountKey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return setLocked(credentials, for: account)
    }

    /// Stores a renewal, unless what is already there outlives it.
    @discardableResult
    static func renewed(_ credentials: AccountCredentials, for account: AccountKey) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard shouldAcceptRenewal(existing: load()?[account.id], candidate: credentials) else {
            return false
        }
        return setLocked(credentials, for: account)
    }

    /// Pure compare-and-set policy for concurrent-refresh tests.
    static func shouldAcceptRenewal(existing: AccountCredentials?, candidate: AccountCredentials) -> Bool {
        guard let existing else { return true }
        return existing.expiresAt < candidate.expiresAt
    }

    static func hasSameStableIdentity(_ lhs: AccountCredentials, _ rhs: AccountCredentials) -> Bool {
        guard let left = lhs.stableIdentity, let right = rhs.stableIdentity else { return false }
        return left == right
    }

    private static func setLocked(_ credentials: AccountCredentials?, for account: AccountKey) -> Bool {
        guard var all = load() else { return false }
        all[account.id] = credentials
        return save(all)
    }

    // MARK: - The file

    /// What is stored, or nil when there is a file here that cannot be read.
    /// An absent file is empty; an unreadable one is not.
    private static func load() -> [String: AccountCredentials]? {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }

        guard
            let sealed = try? Data(contentsOf: file),
            let plain = LocalSecrets.open(sealed, purpose: purpose),
            let all = try? JSONDecoder().decode([String: AccountCredentials].self, from: plain)
        else { return nil }

        return all
    }

    private static func save(_ all: [String: AccountCredentials]) -> Bool {
        guard
            let plain = try? JSONEncoder().encode(all),
            let sealed = LocalSecrets.seal(plain, purpose: purpose)
        else { return false }

        return LocalSecrets.write(sealed, to: file)
    }
}
