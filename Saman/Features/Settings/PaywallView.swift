import SwiftUI
import RevenueCat

/// Local Saman Pro paywall. Feature bullets come from `FreeLimits`, not from
/// RevenueCatUI's remote `PaywallView` — that offering still lists a retired
/// grocery-delivery reorder claim this app does not ship.
struct SamaanPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnv) private var appEnv

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SamaanLegalLinks(includeSupport: false)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .background(Color.surfaceDoodh)
                .accessibilityIdentifier("paywall.legal")
        }
        .task { await loadOffering() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .tint(Color.brandSaag)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed {
            retryState
        } else {
            paywallBody
        }
    }

    private var paywallBody: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(FreeLimits.paywallTitle)
                        .font(.pantryDisplay)
                        .foregroundStyle(Color.inkKohl)
                    Text(FreeLimits.paywallSubtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.inkKohlSoft)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(FreeLimits.proBenefits, id: \.title) { benefit in
                        benefitRow(benefit)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("paywall.features")

                if !packages.isEmpty {
                    packagePicker
                }

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

                    Text(disclaimer)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkKohlSoft)
                        .multilineTextAlignment(.center)

                    Button {
                        Task { await restore() }
                    } label: {
                        if isRestoring {
                            ProgressView().tint(Color.inkKohlSoft)
                        } else {
                            Text("Restore Purchases")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkKohlSoft)
                    .disabled(isPurchasing || isRestoring)
                    .accessibilityIdentifier("paywall.restore")
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
        HStack(alignment: .top, spacing: 8) {
            ForEach(packages, id: \.identifier) { package in
                packageCard(package)
            }
        }
        .accessibilityIdentifier("paywall.packages")
    }

    private func packageCard(_ package: Package) -> some View {
        let selected = package.identifier == selectedPackageID
        return Button {
            selectedPackageID = package.identifier
        } label: {
            VStack(spacing: 6) {
                if let badge = badge(for: package) {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selected ? Color.surfaceDoodh : Color.inkKohlSoft)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            selected ? Color.brandSaag : Color.brandSaagSoft.opacity(0.45),
                            in: Capsule()
                        )
                }
                Text(title(for: package))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.inkKohl)
                Text(package.storeProduct.localizedPriceString)
                    .font(.samaanMono(13))
                    .foregroundStyle(Color.inkKohl)
                Text(periodCaption(for: package))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkKohlSoft)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
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
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var selectedPackage: Package? {
        packages.first { $0.identifier == selectedPackageID }
    }

    private var disclaimer: String {
        if let selectedPackage, selectedPackage.packageType == .lifetime {
            return FreeLimits.paywallLifetimeDisclaimer
        }
        return FreeLimits.paywallRenewalDisclaimer
    }

    private func title(for package: Package) -> String {
        switch package.packageType {
        case .monthly: return "Monthly"
        case .annual: return "Yearly"
        case .lifetime: return "Lifetime"
        case .weekly: return "Weekly"
        case .twoMonth: return "2 months"
        case .threeMonth: return "3 months"
        case .sixMonth: return "6 months"
        case .custom, .unknown:
            return package.storeProduct.localizedTitle
        @unknown default:
            return package.storeProduct.localizedTitle
        }
    }

    private func periodCaption(for package: Package) -> String {
        switch package.packageType {
        case .monthly: return "Billed monthly"
        case .annual: return annualCaption(package)
        case .lifetime: return "One-time purchase"
        case .weekly: return "Billed weekly"
        case .twoMonth: return "Billed every 2 months"
        case .threeMonth: return "Billed every 3 months"
        case .sixMonth: return "Billed every 6 months"
        case .custom, .unknown:
            return "Plan"
        @unknown default:
            return "Plan"
        }
    }

    private func annualCaption(_ package: Package) -> String {
        if let perMonth = package.storeProduct.localizedPricePerMonth {
            return "\(perMonth)/month, billed yearly"
        }
        return "Billed yearly"
    }

    private func badge(for package: Package) -> String? {
        switch package.packageType {
        case .annual:
            if let percent = annualSavingsPercent { return "Save \(percent)%" }
            return nil
        case .lifetime:
            return "Best value"
        case .monthly, .weekly, .twoMonth, .threeMonth, .sixMonth, .custom, .unknown:
            return nil
        @unknown default:
            return nil
        }
    }

    private var annualSavingsPercent: Int? {
        guard
            let monthly = packages.first(where: { $0.packageType == .monthly })?.storeProduct.price,
            let annual = packages.first(where: { $0.packageType == .annual })?.storeProduct.price
        else { return nil }
        let yearlyAtMonthly = monthly * 12
        guard yearlyAtMonthly > 0, yearlyAtMonthly > annual else { return nil }
        let saved = (yearlyAtMonthly - annual) / yearlyAtMonthly * 100
        let percent = NSDecimalNumber(decimal: saved).intValue
        return percent > 0 ? percent : nil
    }

    private func loadOffering() async {
        isLoading = true
        loadFailed = false
        errorMessage = nil
        do {
            let offering = try await appEnv.purchases.currentOffering()
            let available = offering?.availablePackages ?? []
            packages = available
            if selectedPackageID == nil {
                selectedPackageID = available.first(where: { $0.packageType == .annual })?.identifier
                    ?? available.first?.identifier
            }
            loadFailed = available.isEmpty
        } catch {
            AppLogger.error("[Paywall] offerings: \(error)")
            loadFailed = true
        }
        isLoading = false
    }

    private func purchaseSelected() async {
        guard let selectedPackage else { return }
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
}
