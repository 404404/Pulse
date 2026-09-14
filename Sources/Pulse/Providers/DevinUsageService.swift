import Foundation
import SQLite3

/// Devin's daily and weekly quota, read from the cache its own desktop app
/// keeps.
///
/// Devin is Cognition's agent, and `Devin.app` is the former Windsurf editor —
/// the bundle identifier is still `com.exafunction.windsurf` and every key it
/// writes is still named `windsurf.*`. That inheritance is the whole reason
/// this route exists: it is a VS Code fork, so it keeps its global state in
/// `User/globalStorage/state.vscdb`, an ordinary SQLite file, and the plan it
/// last read from the account is one row in it.
///
/// ```json
/// { "planName": "Pro", "billingStrategy": "quota",
///   "dailyRemainingPercent": 98, "weeklyRemainingPercent": 99,
///   "dailyResetAtUnix": 1789372800, "weeklyResetAtUnix": 1789891200,
///   "hideDailyQuota": false, "hideWeeklyQuota": false,
///   "remainingMessages": -1, "totalMessages": -1,
///   "overageBalanceMicros": 10000000 }
/// ```
///
/// **The provider reports both percentages itself**, which is unusual company
/// for a local file: nothing here is inferred, the resets are stated, and the
/// two windows have real lengths. `used = 100 − remaining`, and that is all.
///
/// **Two shapes, because the plans differ.** A paid plan reports the two
/// percentages and sets the message counters to `-1`; a free one reports
/// `remainingMessages`/`totalMessages` instead. Both were captured on this
/// machine — the free shape out of `state.vscdb.backup`, written the moment
/// before the account was upgraded — so both are read. A message allowance has
/// no window and no reset, which is why `UsageWindow.Kind.messages` exists
/// rather than it being filed under a period nobody reported.
///
/// ## What this route cannot do
///
/// **The row is written when the app launches, not while it runs.** Measured:
/// the account was spent down through the morning and the file sat at 100%
/// throughout; the app was quit and reopened at 09:20:01 and the row changed
/// at 09:20:16, fifteen seconds later. So this is a snapshot of the last
/// launch and nothing else, and it is reported with the launch as its
/// `observedAt` — which is what puts "as of …" on the card rather than letting
/// a morning-old reading pass for a fresh one. The launch time is taken from
/// the newest directory under `logs/`, which the app creates once per run.
///
/// That is a real limitation and not a small one. It is worth having anyway:
/// it costs nothing — no credential, no network, no keychain prompt, no Full
/// Disk Access — and someone who keeps Devin open all day is exactly the
/// person whose reading goes stale, which the card now says out loud.
struct DevinUsageService: Sendable {
    /// Where the app keeps its state. Both names are checked because the
    /// product was renamed: an Electron app's support directory follows its
    /// product name, so a Mac that ran Windsurf before the rename carries the
    /// old directory and a fresh install carries the new one. Newest wins.
    private static let supportDirectoryNames = ["Devin", "Windsurf"]

    /// The row, current first. The second is the name CodexBar's notes carry
    /// and this build has never seen; it is read because a name that changed
    /// once can change back, and a `LIKE` for the old one costs nothing.
    private static let planKeyPatterns = [
        "windsurf.reactSettings.cachedPlanInfoData%",
        "windsurf.settings.cachedPlanInfo%",
    ]

    func fetch() async -> ProviderUsage {
        guard let support = Self.supportDirectory() else {
            return .unavailable(.devin, reason: .devinAppMissing)
        }

        let database = support.appending(path: "User/globalStorage/state.vscdb")
        guard let plan = Self.plan(in: database) else {
            return .unavailable(.devin, reason: .devinPlanUnread)
        }

        let windows = Self.windows(from: plan)
        let balance = plan.overageBalance

        guard !windows.isEmpty || balance != nil else {
            return .unavailable(.devin, reason: .noLimitsReported)
        }

        return ProviderUsage(
            account: AccountKey(.devin),
            windows: windows,
            observedAt: Self.lastLaunch(in: support) ?? Self.modified(database),
            state: .live,
            plan: plan.planName,
            creditBalance: balance.map(Self.money)
        )
    }

    /// Whether this Mac has ever run the app. Read by `Provider` to decide
    /// whether a ring is worth offering at all — there is nothing to paste
    /// here, so an install is the only evidence there is.
    static func isInstalled() -> Bool { supportDirectory() != nil }

    // MARK: - The file

    private static func supportDirectory() -> URL? {
        let support = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        let manager = FileManager.default

        return supportDirectoryNames
            .map { support.appending(path: $0) }
            .filter { manager.fileExists(atPath: $0.appending(path: "User/globalStorage/state.vscdb").path) }
            .max { (modified($0) ?? .distantPast) < (modified($1) ?? .distantPast) }
    }

    /// When the app last started, which is when the plan row was last written.
    ///
    /// Taken from `logs/`, where each run creates one directory whose **name**
    /// is its start time — `20260914T092003`, in this Mac's own zone. The name
    /// rather than the directory's date because the date moves: writing inside
    /// an existing file leaves it alone, but a log file created an hour into
    /// the session bumps it, and every minute it gains is a minute the card
    /// under-reports the age of a reading that has not changed since launch.
    /// The date is kept as the fallback for a name that stops parsing.
    ///
    /// **Not the database's own modification date**, which every other key in
    /// the file keeps current — a reading from breakfast would look a second
    /// old.
    private static func lastLaunch(in support: URL) -> Date? {
        let logs = support.appending(path: "logs")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: logs, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        return entries.compactMap { launchStamp($0.lastPathComponent) ?? modified($0) }.max()
    }

    /// `20260914T092003`, written in local time and with no zone on it — which
    /// is why the formatter is given this Mac's own rather than left at UTC.
    static func launchStamp(_ name: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter.date(from: name)
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    // MARK: - The row

    /// Opened read-only and in place, the same way Pulse reads every other
    /// application's store: the app may be running and its journal belongs to
    /// that process.
    ///
    /// More than one row can exist where two accounts have signed in on this
    /// Mac, and nothing in the file says which is current. The one whose plan
    /// runs longest is taken — an active subscription outranks a lapsed one —
    /// and the plan name is on the card either way.
    static func plan(in file: URL) -> Plan? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        defer { sqlite3_close(handle) }

        var found: [Plan] = []
        for pattern in planKeyPatterns {
            found += rows(handle, pattern).compactMap(Plan.init(json:))
            if !found.isEmpty { break }
        }

        return found.max { ($0.endTimestamp ?? 0) < ($1.endTimestamp ?? 0) }
    }

    private static func rows(_ handle: OpaquePointer?, _ pattern: String) -> [Data] {
        var statement: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key LIKE ?"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, pattern, -1, transient)

        var values: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_text(statement, 0) else { continue }
            values.append(Data(String(cString: bytes).utf8))
        }
        return values
    }

    // MARK: - The reply

    /// One account's plan, as the app cached it.
    ///
    /// Every figure is optional because this is a client's own cache rather
    /// than a documented reply: a field that stops being written should drop
    /// its window, not the whole reading.
    struct Plan: Equatable, Sendable {
        var planName: String?
        var dailyRemainingPercent: Double?
        var weeklyRemainingPercent: Double?
        var dailyResetAtUnix: Double?
        var weeklyResetAtUnix: Double?
        var hideDailyQuota = false
        var hideWeeklyQuota = false
        var remainingMessages: Int?
        var totalMessages: Int?
        var overageBalanceMicros: Double?
        var endTimestamp: Double?

        /// Micros, as the field's name says: 10,000,000 is ten dollars.
        var overageBalance: Double? { overageBalanceMicros.map { $0 / 1_000_000 } }

        init?(json data: Data) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            planName = (object["planName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            dailyRemainingPercent = Self.number(object["dailyRemainingPercent"])
            weeklyRemainingPercent = Self.number(object["weeklyRemainingPercent"])
            dailyResetAtUnix = Self.number(object["dailyResetAtUnix"])
            weeklyResetAtUnix = Self.number(object["weeklyResetAtUnix"])
            hideDailyQuota = object["hideDailyQuota"] as? Bool ?? false
            hideWeeklyQuota = object["hideWeeklyQuota"] as? Bool ?? false
            remainingMessages = Self.number(object["remainingMessages"]).map(Int.init)
            totalMessages = Self.number(object["totalMessages"]).map(Int.init)
            overageBalanceMicros = Self.number(object["overageBalanceMicros"])
            endTimestamp = Self.number(object["endTimestamp"])
        }

        /// Booleans are `NSNumber` too, and `NSNumber(true).doubleValue` is 1 —
        /// which would turn `hideDailyQuota` into a percentage if it were ever
        /// read through here.
        private static func number(_ value: Any?) -> Double? {
            guard let value = value as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID()
            else { return nil }
            let double = value.doubleValue
            return double.isFinite ? double : nil
        }
    }

    static func windows(from plan: Plan) -> [UsageWindow] {
        var windows: [UsageWindow] = []

        if !plan.hideDailyQuota,
           let window = window(
               id: "devin-daily", kind: .daily, seconds: 86_400,
               remainingPercent: plan.dailyRemainingPercent, resetAt: plan.dailyResetAtUnix
           ) {
            windows.append(window)
        }

        if !plan.hideWeeklyQuota,
           let window = window(
               id: "devin-weekly", kind: .weekly, seconds: 604_800,
               remainingPercent: plan.weeklyRemainingPercent, resetAt: plan.weeklyResetAtUnix
           ) {
            windows.append(window)
        }

        // A free plan's message pool. **`-1` is the paid plans' way of saying
        // "not applicable"**, not a count, so anything below zero — at either
        // end — is absent rather than empty.
        if let total = plan.totalMessages, let remaining = plan.remainingMessages,
           total > 0, remaining >= 0 {
            windows.append(
                UsageWindow(
                    id: "devin-messages",
                    kind: .messages,
                    scope: nil,
                    usedFraction: min(max(Double(total - remaining) / Double(total), 0), 1),
                    // No window was reported and none is invented: the seconds
                    // exist only so this sorts after the two timed ones.
                    windowSeconds: 2_592_000,
                    resetsAt: nil,
                    reportsLength: false
                )
            )
        }

        return windows
    }

    /// Nil rather than a zeroed window when the percentage is missing: a plan
    /// that reports no daily quota draws nothing, never a full ring.
    private static func window(
        id: String,
        kind: UsageWindow.Kind,
        seconds: Int,
        remainingPercent: Double?,
        resetAt: Double?
    ) -> UsageWindow? {
        guard let remainingPercent else { return nil }
        return UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: min(max(1 - remainingPercent / 100, 0), 1),
            windowSeconds: seconds,
            resetsAt: resetAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    /// US dollars, which is what the field is denominated in — there is no
    /// currency beside it and Devin bills in one.
    private static func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").locale(LocalizationSource.locale))
    }
}
