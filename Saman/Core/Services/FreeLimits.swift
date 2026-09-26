import Foundation

/// Client-side free-plan gates. Settings, StoreKit, and the paywall must name
/// these unlocks — not vague "premium features" or "support development."
///
/// Recipe extract is **not** a Pro unlock: `extract-recipe` caps everyone at
/// `extractPerDay` and does not read the RevenueCat entitlement.
enum FreeLimits {
    static let pantryItemCap = 30

    /// Lists tab `+` only. Recipe capture/detail still create a new list — do
    /// not claim a kitchen-wide one-list cap in copy.
    static let shoppingListCap = 1

    static let extractPerDay = 5

    static func canAddPantryItem(existingCount: Int, isPro: Bool) -> Bool {
        isPro || existingCount < pantryItemCap
    }

    static func canAddShoppingListFromListsTab(existingCount: Int, isPro: Bool) -> Bool {
        isPro || existingCount < shoppingListCap
    }

    static let freePlanSummary =
        "\(pantryItemCap) pantry items · \(shoppingListCap) list from Lists · \(extractPerDay) extracts/day. Pro lifts the pantry and Lists-tab caps. Extract stays \(extractPerDay)/day."

    static let proUnlocksSummary =
        "Pro unlocks more than \(pantryItemCap) pantry items and extra shopping lists from the Lists tab. Recipe extract is \(extractPerDay) per day for everyone."

    static let proActiveSummary =
        "Unlimited pantry items and extra lists from Lists. Recipe extract is \(extractPerDay) per day."

    /// Source-controlled paywall bullets. Do not load feature copy from the
    /// RevenueCat offering — the remote paywall still advertises a retired
    /// grocery-delivery reorder claim that this app does not ship.
    struct ProBenefit: Equatable, Sendable {
        let title: String
        let subtitle: String
    }

    static let paywallTitle = "Saman Pro"
    static let paywallSubtitle = "The full kitchen, unlocked."
    static let paywallCallToAction = "Get Saman Pro"
    static let paywallRenewalDisclaimer = "Subscription renews automatically. Cancel anytime."
    static let paywallLifetimeDisclaimer = "One-time purchase. No subscription."

    static let proBenefits: [ProBenefit] = [
        ProBenefit(
            title: "Unlimited pantry items",
            subtitle: "Track every staple in the kitchen."
        ),
        ProBenefit(
            title: "Unlimited shopping lists",
            subtitle: "Keep weekly, festival, and bulk lists organized."
        ),
    ]

    static var proMarketingStrings: [String] {
        [freePlanSummary, proUnlocksSummary, proActiveSummary,
         paywallTitle, paywallSubtitle, paywallCallToAction,
         paywallRenewalDisclaimer, paywallLifetimeDisclaimer]
            + proBenefits.flatMap { [$0.title, $0.subtitle] }
    }

    static var quotaExceededMessage: String {
        "That's today's \(extractPerDay) recipes. Try again tomorrow."
    }
}
