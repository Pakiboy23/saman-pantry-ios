import Foundation

/// Client-side free-plan gates and Samaan Pro marketing copy.
///
/// Free extract quota is enforced by `extract-recipe` (migration 011):
/// grandfathered accounts keep 5/day; new free accounts get 5 lifetime.
/// Pro (`Saman Pro` entitlement) is uncapped once the Edge Function can
/// verify RevenueCat. Pantry items and shopping lists are unlimited for all.
///
/// Do not advertise private cookbook sharing or member invites here until
/// household sharing ships (THESIS). The public family recipe book is free
/// for readers and is not a Pro unlock.
enum FreeLimits {
    static let extractLimit = 5

    /// Legacy alias used by older tests and docs copy.
    static let extractPerDay = extractLimit

    static let freePlanSummary =
        "\(extractLimit) voice extractions · view the family recipe book · unlimited pantry and lists"

    static let proActiveSummary =
        "Unlimited voice extractions · every rescued recipe stays in your cookbook"

    static let proUnlocksSummary =
        "Unlimited voice extractions. No daily or lifetime cap on recipes from recordings."

    /// Source-controlled paywall bullets. Do not load feature copy from the
    /// RevenueCat offering — the remote paywall still advertises a retired
    /// grocery-delivery reorder claim that this app does not ship.
    struct ProBenefit: Equatable, Sendable {
        let title: String
        let subtitle: String
    }

    static let paywallHeadline = "Don't lose the recipes that only one person knows."
    static let paywallSubheadline =
        "Samaan Pantry Pro turns voice notes and recordings into recipes you can keep."
    static let paywallCallToAction = "Get Samaan Pro"
    static let paywallRenewalDisclaimer = "Subscription renews automatically. Cancel anytime."

    static let paywallContextExtractionLimit = "You've used your \(extractLimit) free extractions."

    /// Screenshot / StoreKit fixture labels only. Live paywall cards use
    /// `Package.storeProduct.localizedPriceString`.
    static let monthlyPriceLabel = "$7.99 / month"
    static let yearlyPriceLabel = "$59.99 / year"
    static let yearlySavingsLabel = "save 38%"

    static let proBenefits: [ProBenefit] = [
        ProBenefit(
            title: "Unlimited voice extractions",
            subtitle: "No cap on recipes rescued from recordings"
        ),
        ProBenefit(
            title: "Keep every rescued recipe",
            subtitle: "Your extracts stay in your cookbook, ready to cook from again"
        ),
    ]

    static var proMarketingStrings: [String] {
        [
            freePlanSummary, proUnlocksSummary, proActiveSummary,
            paywallHeadline, paywallSubheadline, paywallCallToAction,
            paywallRenewalDisclaimer,
            paywallContextExtractionLimit,
            monthlyPriceLabel, yearlyPriceLabel, yearlySavingsLabel,
        ] + proBenefits.flatMap { [$0.title, $0.subtitle] }
    }

    static func extractionCounterLabel(used: Int, grandfathered: Bool) -> String {
        let clamped = min(max(used, 0), extractLimit)
        if grandfathered {
            return "\(clamped) of \(extractLimit) extractions used today"
        }
        return "\(clamped) of \(extractLimit) extractions used"
    }
}

/// Why the paywall was presented. Context copy is omitted for Settings.
enum PaywallTrigger: Equatable, Sendable {
    case settings
    case extractionLimit

    var contextLine: String? {
        switch self {
        case .settings:
            return nil
        case .extractionLimit:
            return FreeLimits.paywallContextExtractionLimit
        }
    }
}
