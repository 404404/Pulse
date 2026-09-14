import Foundation
import Testing
@testable import Pulse

/// Devin is read from a file its own app wrote rather than from a reply, which
/// changes what can go wrong: the shape is a client's cache and is free to
/// change fields, carry two accounts at once, or say "not applicable" with a
/// negative number. These cover the three.
@Suite("Devin parsing")
struct DevinParsingTests {
    private static func plan(_ name: String) throws -> DevinUsageService.Plan {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try #require(DevinUsageService.Plan(json: try Data(contentsOf: url)))
    }

    private static func windows(_ name: String) throws -> [UsageWindow] {
        DevinUsageService.windows(from: try plan(name))
    }

    // MARK: - A paid plan

    @Test("Used is what is left subtracted from the whole")
    func paidPlanReportsBothWindows() throws {
        let windows = try Self.windows("devin-pro")
        #expect(windows.map(\.id) == ["devin-daily", "devin-weekly"])

        let daily = try #require(windows.first)
        #expect(abs(daily.usedFraction - 0.02) < 0.0001)
        #expect(daily.kind == .daily)
        #expect(daily.windowSeconds == 86_400)
        #expect(daily.resetsAt == Date(timeIntervalSince1970: 1_789_372_800))
        // Devin states both the length and the reset, so the card may draw the
        // window clock beside the ring.
        #expect(daily.reportsLength)
        // Nothing here was inferred: both figures came from the provider.
        #expect(!daily.isEstimated)

        let weekly = windows[1]
        #expect(abs(weekly.usedFraction - 0.01) < 0.0001)
        #expect(weekly.windowSeconds == 604_800)
    }

    @Test("A paid plan's message counters are absent, not empty")
    func negativeMessageCountersAreNotAnAllowance() throws {
        // `-1` is how the paid plans say "not applicable". Read as a count it
        // would draw a message allowance of minus one out of minus one.
        #expect(try Self.windows("devin-pro").allSatisfy { $0.kind != .messages })
    }

    @Test("Overage balance is micros")
    func overageBalanceIsScaled() throws {
        #expect(try Self.plan("devin-pro").overageBalance == 10)
    }

    // MARK: - A free plan

    @Test("A free plan's message pool is a window with no window")
    func freePlanReportsMessages() throws {
        let windows = try Self.windows("devin-free")
        let messages = try #require(windows.first { $0.kind == .messages })

        #expect(abs(messages.usedFraction - 0.3) < 0.0001)
        // No length was reported and none is invented, so nothing downstream
        // may divide by the seconds this sorts on.
        #expect(!messages.reportsLength)
        #expect(messages.resetsAt == nil)
    }

    // MARK: - A hidden window

    @Test("A plan that hides its daily quota draws nothing for it")
    func hiddenDailyQuotaIsDropped() throws {
        let windows = try Self.windows("devin-hidden-daily")
        // Not a full ring and not an empty one: the row is simply absent.
        #expect(windows.map(\.id) == ["devin-weekly"])
        #expect(abs(windows[0].usedFraction - 0.58) < 0.0001)
    }

    // MARK: - The file

    @Test("Two accounts in one store: the live plan wins")
    func theLongestRunningPlanIsChosen() throws {
        let url = try #require(Bundle.module.url(
            forResource: "devin-state", withExtension: "vscdb", subdirectory: "Fixtures"
        ))
        let plan = try #require(DevinUsageService.plan(in: url))

        // Both rows parse. Nothing in the file says which account is signed in,
        // so the one whose subscription runs longest is the one reported.
        #expect(plan.planName == "Pro")
        #expect(plan.overageBalance == 10)
    }

    @Test("The launch stamp comes from the directory's name, in this Mac's zone")
    func launchStampIsReadFromTheName() throws {
        let stamp = try #require(DevinUsageService.launchStamp("20260914T092003"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: stamp)

        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 14)
        #expect(parts.hour == 9)
        #expect(parts.minute == 20)
        #expect(parts.second == 3)

        // Anything else in `logs/` is not a launch and must not be read as one.
        #expect(DevinUsageService.launchStamp("window1") == nil)
    }

    @Test("A store with no plan row reads as nothing rather than as zero")
    func aStoreWithoutAPlanIsUnread() throws {
        let empty = URL.temporaryDirectory.appending(path: "devin-empty-\(UUID().uuidString).vscdb")
        defer { try? FileManager.default.removeItem(at: empty) }
        // An unreadable file is the same answer as a readable one with no row:
        // there is no plan here, which is not a plan of zero.
        try Data("not a database".utf8).write(to: empty)

        #expect(DevinUsageService.plan(in: empty) == nil)
    }
}
