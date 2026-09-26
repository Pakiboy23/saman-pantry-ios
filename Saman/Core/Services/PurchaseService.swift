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
        return await applyCustomerInfo(info)
    }

    func currentOffering() async throws -> Offering? {
        let offerings = try await Purchases.shared.offerings()
        return offerings.current
    }

    /// Purchases `package`. Returns whether Pro is active afterward.
    /// User cancellation is not an error — it returns `false`.
    @discardableResult
    func purchase(_ package: Package) async throws -> Bool {
        do {
            let (_, info, userCancelled) = try await Purchases.shared.purchase(package: package)
            let unlocked = await applyCustomerInfo(info)
            return !userCancelled && unlocked
        } catch {
            if Self.isPurchaseCancelled(error) { return false }
            throw error
        }
    }

    // MARK: - Private

    private func startObservingCustomerInfo() async {
        for await info in Purchases.shared.customerInfoStream {
            _ = await applyCustomerInfo(info)
        }
    }

    @MainActor
    @discardableResult
    private func applyCustomerInfo(_ info: CustomerInfo) -> Bool {
        let unlocked = info.entitlements[Self.proEntitlementID]?.isActive == true
        customerInfo = info
        isPro = unlocked
        return unlocked
    }

    static func isPurchaseCancelled(_ error: Error) -> Bool {
        if let code = error as? ErrorCode {
            return code == .purchaseCancelledError
        }
        let nsError = error as NSError
        return nsError.code == ErrorCode.purchaseCancelledError.rawValue
    }
}
