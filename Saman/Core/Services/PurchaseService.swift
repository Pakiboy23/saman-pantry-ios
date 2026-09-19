import Foundation
import RevenueCat

@Observable
final class PurchaseService {

    // RevenueCat entitlement identifier — must match the RevenueCat dashboard
    // byte-for-byte, so it intentionally keeps the original "Saman" spelling
    // even though the brand is now "Samaan". Renaming it here without renaming
    // it in the dashboard would silently disable Pro for every subscriber.
    static let proEntitlementID = "Saman Pro"

    // MARK: - State

    private(set) var isPro: Bool = false
    private(set) var customerInfo: CustomerInfo? = nil

    // MARK: - Init

    init() {
        Task { await startObservingCustomerInfo() }
    }

    // MARK: - Public

    func setAppUserID(_ id: String) {
        Task {
            do {
                let (_, _) = try await Purchases.shared.logIn(id)
            } catch {
                AppLogger.error("[RevenueCat] logIn error: \(error)")
            }
        }
    }

    /// StoreKit restore for the free Settings surface (Guideline 3.1.1).
    /// Returns whether the `Saman Pro` entitlement is active after restore.
    @discardableResult
    func restorePurchases() async throws -> Bool {
        let info = try await Purchases.shared.restorePurchases()
        let restoredPro = info.entitlements[Self.proEntitlementID]?.isActive == true
        await MainActor.run {
            customerInfo = info
            isPro = restoredPro
        }
        return restoredPro
    }

    // MARK: - Private

    private func startObservingCustomerInfo() async {
        for await info in Purchases.shared.customerInfoStream {
            await MainActor.run {
                customerInfo = info
                isPro = info.entitlements[Self.proEntitlementID]?.isActive == true
            }
        }
    }
}
