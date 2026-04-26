import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(\.appEnv) private var appEnv
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPackage: Package? = nil
    @State private var offerings: Offerings? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Saman")
                            .font(.cormorant(48))
                            .foregroundStyle(Color.samanPrimary)
                        Text("سامان Pro")
                            .font(.custom("NotoNastaliqUrdu-Regular", size: 20))
                            .foregroundStyle(Color.samanAccent)
                        Text("Support independent development and unlock cosmetic upgrades as they ship.")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Color.samanMuted)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 40)
                    .padding(.bottom, 32)

                    // Plan cards
                    if let offering = offerings?.current {
                        VStack(spacing: 10) {
                            ForEach(offering.availablePackages, id: \.identifier) { pkg in
                                planCard(for: pkg)
                            }
                        }
                        .padding(.horizontal, Saman.Space.md)
                    } else {
                        ProgressView()
                            .padding(40)
                    }

                    // Purchase button
                    VStack(spacing: 12) {
                        Button {
                            guard let pkg = selectedPackage else { return }
                            Task {
                                let success = await appEnv.purchases.purchase(pkg)
                                if success { dismiss() }
                            }
                        } label: {
                            Group {
                                if appEnv.purchases.isLoading {
                                    ProgressView().tint(Color.samanBg)
                                } else {
                                    Text(selectedPackage == nil ? "Select a plan" : "Subscribe")
                                        .font(.system(size: 16, weight: .medium))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(selectedPackage == nil ? Color.samanMuted.opacity(0.3) : Color.samanPrimary)
                            .foregroundStyle(selectedPackage == nil ? Color.samanMuted : Color.samanBg)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(selectedPackage == nil || appEnv.purchases.isLoading)

                        if let error = appEnv.purchases.purchaseError {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.samanRed)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task { await appEnv.purchases.restorePurchases() }
                        } label: {
                            Text("Restore purchases")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.samanMuted)
                        }

                        Text("Subscription renews automatically. Cancel anytime in App Store settings.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.samanMuted.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Saman.Space.md)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .background(Color.samanBg)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.samanMuted)
                    }
                }
            }
            .task {
                await appEnv.purchases.loadOfferings()
                offerings = appEnv.purchases.offerings
                selectedPackage = offerings?.current?.availablePackages.first(where: {
                    $0.packageType == .annual
                }) ?? offerings?.current?.availablePackages.first
            }
            .onChange(of: appEnv.purchases.isPro) { _, isPro in
                if isPro { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func planCard(for pkg: Package) -> some View {
        let isSelected = selectedPackage?.identifier == pkg.identifier
        let isAnnual = pkg.packageType == .annual

        Button { selectedPackage = pkg } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(pkg.storeProduct.localizedTitle.isEmpty
                             ? (isAnnual ? "Annual" : "Monthly")
                             : pkg.storeProduct.localizedTitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.samanPrimary)
                        if isAnnual {
                            Text("Best value")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.samanAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.samanAccent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    Text(pkg.storeProduct.localizedPriceString + (isAnnual ? " / year" : " / month"))
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(Color.samanMuted)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.samanAccent : Color.samanBorder, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.samanAccent)
                            .frame(width: 13, height: 13)
                    }
                }
            }
            .padding(16)
            .background(Color.samanCard)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.samanAccent : Color.samanBorder, lineWidth: isSelected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    PaywallView()
        .environment(\.appEnv, AppEnvironment(modelContainer: .preview))
}
