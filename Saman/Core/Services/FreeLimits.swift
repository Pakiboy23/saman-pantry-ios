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

    static var quotaExceededMessage: String {
        "That's today's \(extractPerDay) recipes. Try again tomorrow."
    }
}
