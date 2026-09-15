import SwiftUI
import RevenueCat
import RevenueCatUI

// Thin wrapper so we can intercept purchase/restore callbacks and
// keep PurchaseService.isPro in sync immediately (stream also updates it,
// but this makes the sheet dismiss feel instant).
struct SamaanPaywallView: View {
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
            // RevenueCatUI 5.87 has no tosUrl/privacyUrl view modifier; TOS
            // lives on the remote paywall config. Attach Config URLs here so
            // the purchase sheet always shows Terms + Privacy (3.1.2(c)).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SamaanLegalLinks(includeSupport: false)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.surfaceDoodh)
                    .accessibilityIdentifier("paywall.legal")
            }
    }
}
