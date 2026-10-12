import SwiftUI
import RevenueCat

/// Local Samaan Pro paywall. Feature bullets come from `FreeLimits`, not from
/// RevenueCatUI's remote `PaywallView` — that offering still lists a retired
/// grocery-delivery reorder claim this app does not ship.
///
/// Lifetime packages are hidden. New App Store prices ($7.99 / $59.99) are
/// shown from `FreeLimits` until RevenueCat offerings are updated after Apple
/// approves the products.
struct SamaanPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnv) private var appEnv
    @Environment(\.openURL) private var openURL

    var trigger: PaywallTrigger = .settings

    @State private var packages: [Package] = []
    @State private var selectedPackageID: String?
    @State private var isLoading = true
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var loadFailed = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.surfaceDoodh.ignoresSafeArea()
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerLinks
                .padding(.top, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .background(Color.surfaceDoodh)
                .accessibilityIdentifier("paywall.legal")
        }
        .task { await loadOffering() }
        .onAppear { Analytics.track(.paywallViewed) }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .tint(Color.brandSaag)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed && packages.isEmpty {
            retryState
        } else {
            paywallBody
        }
    }

    private var paywallBody: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    if let context = trigger.contextLine {
                        Text(context)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.brandSaag)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("paywall.context")
                    }

                    Text(FreeLimits.paywallHeadline)
                        .font(.cormorant(size: 30))
                        .foregroundStyle(Color.inkKohl)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("paywall.headline")

                    Text(FreeLimits.paywallSubheadline)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.inkKohlSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(FreeLimits.proBenefits, id: \.title) { benefit in
                        benefitRow(benefit)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("paywall.features")

                packagePicker

                VStack(spacing: 10) {
                    Button {
                        Task { await purchaseSelected() }
                    } label: {
                        if isPurchasing {
                            ProgressView().tint(Color.surfaceDoodh)
                        } else {
                            Text(FreeLimits.paywallCallToAction)
                        }
                    }
                    .buttonStyle(SamaanPrimaryButtonStyle())
                    .disabled(selectedPackage == nil || isPurchasing || isRestoring)
                    .accessibilityIdentifier("paywall.cta")

                    Text(FreeLimits.paywallRenewalDisclaimer)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkKohlSoft)
                        .multilineTextAlignment(.center)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentAnaar)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Samaan.Space.lg)
            .padding(.bottom, 16)
        }
    }

    private var retryState: some View {
        VStack(spacing: 14) {
            Text("Couldn't load plans.")
                .font(.system(size: 15))
                .foregroundStyle(Color.inkKohl)
            Button("Try again") {
                Task { await loadOffering() }
            }
            .buttonStyle(SamaanSecondaryButtonStyle())
            .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func benefitRow(_ benefit: FreeLimits.ProBenefit) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.brandSaag)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.inkKohl)
                Text(benefit.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkKohlSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var packagePicker: some View {
        VStack(spacing: 10) {
            ForEach(displayPackages, id: \.id) { option in
                packageCard(option)
            }
        }
        .accessibilityIdentifier("paywall.packages")
    }

    private var displayPackages: [DisplayPackage] {
        var options: [DisplayPackage] = []
        if let annual = packages.first(where: { $0.packageType == .annual }) {
            options.append(DisplayPackage(
                id: annual.identifier,
                package: annual,
                title: "Yearly",
                priceLabel: FreeLimits.yearlyPriceLabel,
                detail: FreeLimits.yearlySavingsLabel,
                badge: FreeLimits.yearlySavingsLabel
            ))
        } else {
            options.append(DisplayPackage(
                id: "yearly-fallback",
                package: nil,
                title: "Yearly",
                priceLabel: FreeLimits.yearlyPriceLabel,
                detail: FreeLimits.yearlySavingsLabel,
                badge: FreeLimits.yearlySavingsLabel
            ))
        }
        if let monthly = packages.first(where: { $0.packageType == .monthly }) {
            options.append(DisplayPackage(
                id: monthly.identifier,
                package: monthly,
                title: "Monthly",
                priceLabel: FreeLimits.monthlyPriceLabel,
                detail: nil,
                badge: nil
            ))
        } else {
            options.append(DisplayPackage(
                id: "monthly-fallback",
                package: nil,
                title: "Monthly",
                priceLabel: FreeLimits.monthlyPriceLabel,
                detail: nil,
                badge: nil
            ))
        }
        return options
    }

    private func packageCard(_ option: DisplayPackage) -> some View {
        let selected = option.id == selectedPackageID
        return Button {
            selectedPackageID = option.id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(option.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.inkKohl)
                        if let badge = option.badge {
                            Text(badge)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selected ? Color.surfaceDoodh : Color.brandSaag)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    selected ? Color.brandSaag : Color.brandSaagSoft.opacity(0.55),
                                    in: Capsule()
                                )
                        }
                    }
                    Text(option.priceLabel)
                        .font(.samaanMono(14))
                        .foregroundStyle(Color.inkKohl)
                    if let detail = option.detail, option.badge == nil {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.inkKohlSoft)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Color.brandSaag : Color.borderAkhrotSoft)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .background(
                selected ? Color.brandSaagSoft.opacity(0.55) : Color.surfaceMalai,
                in: RoundedRectangle(cornerRadius: Samaan.Radius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Samaan.Radius.md)
                    .stroke(selected ? Color.brandSaag : Color.borderAkhrotSoft.opacity(0.5), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(option.package == nil && packages.isEmpty == false)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var footerLinks: some View {
        HStack(spacing: 6) {
            Button("Restore Purchases") {
                Task { await restore() }
            }
            .disabled(isPurchasing || isRestoring)
            .accessibilityIdentifier("paywall.restore")

            Text("·").foregroundStyle(Color.inkKohlSoft)

            if let privacy = URL(string: Config.privacyPolicyURL) {
                Link("Privacy Policy", destination: privacy)
            }

            Text("·").foregroundStyle(Color.inkKohlSoft)

            if let terms = URL(string: Config.termsOfUseURL) {
                Link("Terms of Use", destination: terms)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.brandSaag)
        .tint(Color.brandSaag)
        .multilineTextAlignment(.center)
    }

    private var selectedPackage: Package? {
        displayPackages.first(where: { $0.id == selectedPackageID })?.package
            ?? packages.first(where: { $0.identifier == selectedPackageID })
    }

    private func loadOffering() async {
        isLoading = true
        loadFailed = false
        errorMessage = nil
        do {
            let offering = try await appEnv.purchases.currentOffering()
            // Lifetime is retired from this paywall. Keep monthly + yearly only.
            let available = (offering?.availablePackages ?? []).filter {
                $0.packageType == .monthly || $0.packageType == .annual
            }
            packages = available
            // Prefer yearly, then monthly, then the static fallback cards so
            // Review / screenshots still see the new $7.99 / $59.99 copy.
            loadFailed = false
            if selectedPackageID == nil || !displayPackages.contains(where: { $0.id == selectedPackageID }) {
                selectedPackageID = available.first(where: { $0.packageType == .annual })?.identifier
                    ?? available.first(where: { $0.packageType == .monthly })?.identifier
                    ?? displayPackages.first(where: { $0.package != nil })?.id
                    ?? displayPackages.first?.id
            }
        } catch {
            AppLogger.error("[Paywall] offerings: \(error)")
            packages = []
            selectedPackageID = displayPackages.first?.id
            loadFailed = false
        }
        isLoading = false
    }

    private func purchaseSelected() async {
        guard let selectedPackage else {
            errorMessage = "Plans are updating. Try Restore Purchases, or check back shortly."
            return
        }
        Analytics.track(.purchaseStarted)
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            let unlocked = try await appEnv.purchases.purchase(selectedPackage)
            if unlocked { dismiss() }
        } catch {
            AppLogger.error("[Paywall] purchase: \(error)")
            errorMessage = "Couldn't complete purchase. Try again."
        }
    }

    private func restore() async {
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }
        do {
            let unlocked = try await appEnv.purchases.restorePurchases()
            if unlocked {
                dismiss()
            } else {
                errorMessage = "No Pro purchase found for this Apple ID."
            }
        } catch {
            AppLogger.error("[Paywall] restore: \(error)")
            errorMessage = "Couldn't restore purchases. Try again."
        }
    }

    private struct DisplayPackage: Identifiable {
        let id: String
        let package: Package?
        let title: String
        let priceLabel: String
        let detail: String?
        let badge: String?
    }
}
