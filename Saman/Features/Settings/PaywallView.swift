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
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(FreeLimits.proUnlocksSummary)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkKohl)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Samaan.Space.md)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.surfaceDoodh)
                    .accessibilityIdentifier("paywall.unlocks")
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
