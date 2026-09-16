import Foundation
import Testing
@testable import Pulse

/// Pricing a model no first-party provider publishes, at the rate the plan it
/// was bought on charges.
///
/// The case this exists for: `deepseek-v4.1-flash` is real, OpenCode Go sells
/// it, and DeepSeek's own models.dev entry does not list it — so a machine
/// that had spent 150k tokens on it showed no figure at all.
@Suite("Vendor prices")
struct VendorPriceTests {
    private static let table: [String: ModelPrice] = [
        "deepseek-v4-flash": ModelPrice(input: 0.15, output: 0.6, cacheRead: 0.003, cacheWrite: nil, name: "DeepSeek V4 Flash"),
        ModelPrices.vendorKey("opencode-go", "deepseek-v4.1-flash"):
            ModelPrice(input: 0.15, output: 0.6, cacheRead: 0.003, cacheWrite: nil, name: "DeepSeek V4.1 Flash"),
        ModelPrices.vendorKey("opencode-go", "deepseek-v4-flash"):
            ModelPrice(input: 99, output: 99, cacheRead: nil, cacheWrite: nil, name: "Wrong"),
    ]

    @Test("A model only the plan vendor publishes is priced by that vendor")
    func vendorFallback() {
        let price = ModelPrices.price(for: "deepseek-v4.1-flash", in: Self.table, vendor: "opencode-go")
        #expect(price?.input == 0.15)
        #expect(price?.output == 0.6)
    }

    /// The whole reason vendor rates are namespaced: a caller that did not ask
    /// for a vendor must never be handed one's price.
    @Test("Without a vendor the same model stays unpriced")
    func noVendorNoPrice() {
        #expect(ModelPrices.price(for: "deepseek-v4.1-flash", in: Self.table) == nil)
    }

    /// A vendor re-listing a model the model's own maker publishes must not
    /// shadow it — the first-party rate is the answer, the plan's is not a
    /// second opinion on it.
    @Test("A first-party price always wins over the plan vendor's")
    func firstPartyWins() {
        let price = ModelPrices.price(for: "deepseek-v4-flash", in: Self.table, vendor: "opencode-go")
        #expect(price?.input == 0.15, "the vendor's 99 must not be reachable")
    }

    @Test("A vendor that sells nothing for the model is still nil")
    func unknownStaysUnpriced() {
        #expect(ModelPrices.price(for: "no-such-model", in: Self.table, vendor: "opencode-go") == nil)
    }

    /// Only the agents whose plan is a reseller carry one; an agent that calls
    /// the model vendors directly must not get a second answer.
    @Test("Only plan-based agents name a vendor")
    func whoHasAVendor() {
        #expect(SpendAgent.openCode.priceVendor == "opencode-go")
        #expect(SpendAgent.kiloCLI.priceVendor == "kilo")
        #expect(SpendAgent.cline.priceVendor == "cline-pass")
        #expect(SpendAgent.claudeCode.priceVendor == nil)
        #expect(SpendAgent.codex.priceVendor == nil)
    }
}
