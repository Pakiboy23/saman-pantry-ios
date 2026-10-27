import Foundation
import RevenueCat
import Supabase

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

/// RevenueCat app user ids are case-sensitive. `UUID.uuidString` is
/// uppercase; `user_accounts.id` and Supabase auth ids are lowercase.
enum RevenueCatAppUserID {
    static func normalized(_ supabaseUserID: String) -> String {
        supabaseUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// One `revenuecat-sync` POST per signed-in user for this process.
/// Anonymous buyers, and a RevenueCat id that is not the signed-in user,
/// stay local until `logIn` has finished.
enum RevenueCatAccountSync {
    static let functionName = "revenuecat-sync"

    static func candidate(
        loggedInAppUserID: String?,
        revenueCatAppUserID: String,
        revenueCatIsAnonymous: Bool,
        attemptedUserIDs: Set<String>
    ) -> String? {
        guard !revenueCatIsAnonymous else { return nil }
        guard let loggedInAppUserID else { return nil }
        let id = RevenueCatAppUserID.normalized(loggedInAppUserID)
        guard !id.isEmpty else { return nil }
        guard RevenueCatAppUserID.normalized(revenueCatAppUserID) == id else { return nil }
        guard !attemptedUserIDs.contains(id) else { return nil }
        return id
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

    /// Supabase user id last passed to `logIn`, lowercased. Nil until that
    /// call finishes, and cleared on sign-out so a cached Pro snapshot
    /// cannot sync against the wrong account.
    private var loggedInAppUserID: String?

    /// Users this process already tried to sync. Failures count, so a
    /// missing `revenuecat-sync` function cannot retry on every customer-info
    /// update. The next launch gets a fresh set.
    private var revenueCatSyncAttemptedUserIDs: Set<String> = []

    private let supabase: SupabaseClient

    // MARK: - Init

    init(supabase: SupabaseClient = .shared) {
        self.supabase = supabase
        Task { await startObservingCustomerInfo() }
    }

    // MARK: - Public

    var isAnonymous: Bool {
        Purchases.shared.isAnonymous
    }

    func setAppUserID(_ id: String) {
        let appUserID = RevenueCatAppUserID.normalized(id)
        guard !appUserID.isEmpty else { return }
        identityGeneration += 1
        let generation = identityGeneration
        suppressIdentifiedEntitlements = false
        Task {
            do {
                let (info, _) = try await Purchases.shared.logIn(appUserID)
                guard generation == self.identityGeneration else { return }
                loggedInAppUserID = appUserID
                // Pro on this customer info syncs inside applyCustomerInfo.
                // A free account still syncs once here. Either way the attempt
                // is recorded, so later customerInfoStream updates do not POST again.
                _ = await applyCustomerInfo(info)
                requestRevenueCatSync()
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
        loggedInAppUserID = nil
        Task { @MainActor in
            customerInfo = nil
            isPro = false
            do {
                let info = try await Purchases.shared.logOut()
                guard generation == self.identityGeneration else { return }
                _ = applyCustomerInfo(info)
            } catch {
                // Already anonymous is expected for a guest. Other failures
                // (SDK not configured in tests, network) are non-fatal.
                if Self.isAnonymousLogOut(error) { return }
                AppLogger.error("[RevenueCat] logOut error: \(error)")
            }
        }
    }

    /// StoreKit restore for the free Settings surface (Guideline 3.1.1).
    /// Returns whether the `Saman Pro` entitlement (RevenueCat ID, unchanged; shown to users as Samaan Pro) is active after restore.
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
        if unlocked {
            requestRevenueCatSync()
        }
        return unlocked
    }

    /// POST `revenuecat-sync` with the signed-in session. At most once per
    /// user for this process; a failure is logged and does not retry.
    private func requestRevenueCatSync() {
        guard let id = RevenueCatAccountSync.candidate(
            loggedInAppUserID: loggedInAppUserID,
            revenueCatAppUserID: Purchases.shared.appUserID,
            revenueCatIsAnonymous: Purchases.shared.isAnonymous,
            attemptedUserIDs: revenueCatSyncAttemptedUserIDs
        ) else { return }
        revenueCatSyncAttemptedUserIDs.insert(id)
        let client = supabase
        Task {
            do {
                let sessionID = try await client.auth.session.user.id.uuidString.lowercased()
                guard sessionID == id else { return }
                // Discard the body. The no-decode overload is ambiguous with
                // `invoke<T: Decodable>` when the result is unused.
                try await client.functions.invoke(RevenueCatAccountSync.functionName) { _, _ in () }
            } catch {
                AppLogger.error("[RevenueCat] revenuecat-sync error: \(error)")
            }
        }
    }

    static func isAnonymousLogOut(_ error: Error) -> Bool {
        if let code = error as? ErrorCode {
            return code == .logOutAnonymousUserError
        }
        // `logOut()` throws `PublicError`, which is an `NSError` in `ErrorCode`'s domain.
        let nsError = error as NSError
        return nsError.domain == ErrorCode.errorDomain
            && nsError.code == ErrorCode.logOutAnonymousUserError.rawValue
    }

    static func isPurchaseCancelled(_ error: Error) -> Bool {
        if let code = error as? ErrorCode {
            return code == .purchaseCancelledError
        }
        let nsError = error as NSError
        return nsError.code == ErrorCode.purchaseCancelledError.rawValue
    }
}
