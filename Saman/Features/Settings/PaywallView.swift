import SwiftUI
import RevenueCat
import RevenueCatUI

// Thin wrapper so we can intercept purchase/restore callbacks and
// keep PurchaseService.isPro in sync immediately (stream also updates it,
// but this makes the sheet dismiss feel instant).
struct SamanPaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PaywallView()
            .onPurchaseCompleted { customerInfo in
                if customerInfo.entitlements[PurchaseService.proEntitlementID]?.isActive == true {
                    dismiss()
                }
            }
            .onRestoreCompleted { customerInfo in
                if customerInfo.entitlements[PurchaseService.proEntitlementID]?.isActive == true {
                    dismiss()
                }
            }
    }
}
