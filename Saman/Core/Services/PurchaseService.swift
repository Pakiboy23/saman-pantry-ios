import Foundation
import RevenueCat

@Observable
final class PurchaseService {

    // MARK: - State

    private(set) var isPro: Bool = false
    private(set) var offerings: Offerings? = nil
    private(set) var isLoading: Bool = false
    private(set) var purchaseError: String? = nil

    // MARK: - Init

    init() {
        Task { await refreshCustomerInfo() }
    }

    // MARK: - Public

    func setAppUserID(_ id: String) {
        Task {
            do {
                let (_, _) = try await Purchases.shared.logIn(id)
                await refreshCustomerInfo()
            } catch {
                print("[RevenueCat] logIn error: \(error)")
            }
        }
    }

    func loadOfferings() async {
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            print("[RevenueCat] offerings error: \(error)")
        }
    }

    func purchase(_ package: Package) async -> Bool {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            isPro = result.customerInfo.entitlements["pro"]?.isActive == true
            return isPro
        } catch {
            if (error as NSError).code != ErrorCode.purchaseCancelledError.rawValue {
                purchaseError = error.localizedDescription
            }
            return false
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            isPro = info.entitlements["pro"]?.isActive == true
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Private

    @MainActor
    private func refreshCustomerInfo() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            isPro = info.entitlements["pro"]?.isActive == true
        } catch {
            print("[RevenueCat] customerInfo error: \(error)")
        }
    }
}
