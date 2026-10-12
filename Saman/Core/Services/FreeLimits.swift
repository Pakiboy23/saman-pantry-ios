import Foundation

/// Client-side free-plan gates and Samaan Pro marketing copy.
///
/// Free extract quota is enforced by `extract-recipe` (migration 011):
/// grandfathered accounts keep 5/day; new free accounts get 5 lifetime.
/// Pro (`Saman Pro` entitlement) is uncapped once the Edge Function can
/// verify RevenueCat. Pantry items and shopping lists are unlimited for all.
enum FreeLimits {
    static let extractLimit = 5

    /// Legacy alias used by older tests and docs copy.
    static let extractPerDay = extractLimit

    static let freePlanSummary =
        "\(extractLimit) voice extractions · view shared cookbooks · unlimited pantry and lists"

    static let proActiveSummary =
        "Unlimited voice extractions · create and share your family cookbook"

    static let proUnlocksSummary =
        "Unlimited voice extractions, a family cookbook you can share, and members who cook from it for free."

    /// Source-controlled paywall bullets. Do not load feature copy from the
    /// RevenueCat offering — the remote paywall still advertises a retired
    /// grocery-delivery reorder claim that this app does not ship.
    struct ProBenefit: Equatable, Sendable {
        let title: String
        let subtitle: String
    }

    static let paywallHeadline = "Don't lose the recipes that only one person knows."
    static let paywallSubheadline =
        "Samaan Pantry Pro turns voice notes and recordings into a cookbook your whole family can keep."
    static let paywallCallToAction = "Get Samaan Pro"
    static let paywallRenewalDisclaimer = "Subscription renews automatically. Cancel anytime."

    static let paywallContextExtractionLimit = "You've used your \(extractLimit) free extractions."
    static let paywallContextCookbookCreation = "Creating a family cookbook is a Pro feature."

    static let monthlyPriceLabel = "$7.99 / month"
    static let yearlyPriceLabel = "$59.99 / year"
    static let yearlySavingsLabel = "save 38%"

    static let proBenefits: [ProBenefit] = [
        ProBenefit(
            title: "Unlimited voice extractions",
            subtitle: "No cap on recipes rescued from recordings"
        ),
        ProBenefit(
            title: "Create your family cookbook",
            subtitle: "One place for every recipe, from every generation"
        ),
        ProBenefit(
            title: "Add family members",
            subtitle: "They can read and cook from it for free"
        ),
    ]

    static var proMarketingStrings: [String] {
        [
            freePlanSummary, proUnlocksSummary, proActiveSummary,
            paywallHeadline, paywallSubheadline, paywallCallToAction,
            paywallRenewalDisclaimer,
            paywallContextExtractionLimit, paywallContextCookbookCreation,
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
    case cookbookCreation

    var contextLine: String? {
        switch self {
        case .settings:
            return nil
        case .extractionLimit:
            return FreeLimits.paywallContextExtractionLimit
        case .cookbookCreation:
            return FreeLimits.paywallContextCookbookCreation
        }
    }
}
