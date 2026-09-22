import Foundation
import RevenueCat

/// Decide whether this app session should identify, log out, or leave
/// RevenueCat alone. Guest browse after #20 can follow a Pro account on
/// the same install; logging out an anonymous buyer would drop their
/// purchase until Restore, so only an *identified* leftover identity is
/// cleared.
enum PurchaseSessionBinding {
    enum Action: Equatable {
        case identify(String)
        case logOut
        case ignore
    }

    static func action(
        currentUserID: String?,
        revenueCatIsAnonymous: Bool,
        skipsAuth: Bool
    ) -> Action {
        if skipsAuth {
            return .ignore
        }
        if let currentUserID {
            return .identify(currentUserID)
        }
        if revenueCatIsAnonymous {
            return .ignore
        }
        return .logOut
    }
}

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

    /// Bumped on every identify/logOut so a stale `logOut` cannot land
    /// after a quick sign-in and wipe the new account's RevenueCat user.
    private var identityGeneration = 0

    /// While true, ignore identified RevenueCat snapshots so a cached Pro
    /// entitlement cannot come back through `customerInfoStream` after
    /// sign-out and before `logOut()` finishes.
    private var suppressIdentifiedEntitlements = false

    // MARK: - Init

    init() {
        Task { await startObservingCustomerInfo() }
    }

    // MARK: - Public

    var isAnonymous: Bool {
        Purchases.shared.isAnonymous
    }

    func setAppUserID(_ id: String) {
        identityGeneration += 1
        let generation = identityGeneration
        suppressIdentifiedEntitlements = false
        Task {
            do {
                let (_, info) = try await Purchases.shared.logIn(id)
                guard generation == self.identityGeneration else { return }
                _ = await applyCustomerInfo(info)
            } catch {
                AppLogger.error("[RevenueCat] logIn error: \(error)")
            }
        }
    }

    /// Drop the previous account's Pro flag and RevenueCat identity so
    /// guest browse (or the next sign-in) cannot keep those unlocks.
    func logOutAppUser() {
        identityGeneration += 1
        let generation = identityGeneration
        suppressIdentifiedEntitlements = true
        Task { @MainActor in
            customerInfo = nil
            isPro = false
            do {
                let info = try await Purchases.shared.logOut()
                guard generation == self.identityGeneration else { return }
                _ = applyCustomerInfo(info)
            } catch {
                // Already anonymous, or SDK not configured in tests.
                AppLogger.error("[RevenueCat] logOut error: \(error)")
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
        if suppressIdentifiedEntitlements && !Purchases.shared.isAnonymous {
            customerInfo = nil
            isPro = false
            return false
        }
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
