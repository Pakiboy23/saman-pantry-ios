import SwiftUI
import RevenueCatUI

struct SettingsView: View {
    @Environment(\.appEnv) private var appEnv
    @State private var showSignOutConfirm = false
    @State private var showPaywall = false
    @State private var showCustomerCenter = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Subscription card
                    settingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            cardLabel("SUBSCRIPTION")
                            if appEnv.purchases.isPro {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(Color.brandSaag)
                                        Text("Samaan Pro")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color.inkKohl)
                                        Spacer()
                                        Button("Manage") { showCustomerCenter = true }
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color.inkKohlSoft)
                                    }
                                    Text(FreeLimits.proActiveSummary)
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundStyle(Color.inkKohlSoft)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Free plan")
                                                .font(.system(size: 15))
                                                .foregroundStyle(Color.inkKohl)
                                            Text(FreeLimits.freePlanSummary)
                                                .font(.system(size: 12, weight: .light))
                                                .foregroundStyle(Color.inkKohlSoft)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer(minLength: 8)
                                        Button("Upgrade") { showPaywall = true }
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Color.surfaceDoodh)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(Color.brandSaag)
                                            .clipShape(Capsule())
                                    }
                                    Button {
                                        Task { await restorePurchases() }
                                    } label: {
                                        HStack {
                                            if isRestoring {
                                                ProgressView().tint(Color.inkKohlSoft)
                                            }
                                            Text("Restore Purchases")
                                                .foregroundStyle(Color.inkKohlSoft)
                                            Spacer()
                                        }
                                        .font(.system(size: 13))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isRestoring)
                                    .accessibilityIdentifier("settings.restorePurchases")
                                }
                            }
                        }
                    }

                    // Sync card
                    settingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            cardLabel("SYNC")
                            Button {
                                if appEnv.requireAccount() {
                                    appEnv.syncNow()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.trianglehead.clockwise")
                                        .foregroundStyle(Color.brandSaag)
                                    Text("Sync now")
                                        .foregroundStyle(Color.inkKohl)
                                    Spacer()
                                }
                                .font(.system(size: 15))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Account card
                    settingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            cardLabel("ACCOUNT")
                            if appEnv.auth.isSignedIn {
                                Button {
                                    showSignOutConfirm = true
                                } label: {
                                    HStack {
                                        Image(systemName: "rectangle.portrait.and.arrow.right")
                                            .foregroundStyle(Color.accentAnaar)
                                        Text("Sign out")
                                            .foregroundStyle(Color.accentAnaar)
                                        Spacer()
                                    }
                                    .font(.system(size: 15))
                                }
                                .buttonStyle(.plain)

                                Divider().overlay(Color.borderAkhrotSoft.opacity(0.5))

                                Button {
                                    showDeleteConfirm = true
                                } label: {
                                    HStack {
                                        if isDeleting {
                                            ProgressView().tint(Color.accentAnaar)
                                        } else {
                                            Image(systemName: "trash")
                                                .foregroundStyle(Color.accentAnaar)
                                        }
                                        Text("Delete account")
                                            .foregroundStyle(Color.accentAnaar)
                                        Spacer()
                                    }
                                    .font(.system(size: 15))
                                }
                                .buttonStyle(.plain)
                                .disabled(isDeleting)
                            } else {
                                Button {
                                    appEnv.requireAccount()
                                } label: {
                                    HStack {
                                        Image(systemName: "person.crop.circle")
                                            .foregroundStyle(Color.brandSaag)
                                        Text("Sign in")
                                            .foregroundStyle(Color.inkKohl)
                                        Spacer()
                                    }
                                    .font(.system(size: 15))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("settings.signIn")

                                Divider().overlay(Color.borderAkhrotSoft.opacity(0.5))

                                Button {
                                    if appEnv.requireAccount() {
                                        showDeleteConfirm = true
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                            .foregroundStyle(Color.accentAnaar)
                                        Text("Delete account")
                                            .foregroundStyle(Color.accentAnaar)
                                        Spacer()
                                    }
                                    .font(.system(size: 15))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Legal card
                    settingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            cardLabel("LEGAL")
                            legalLink("Privacy Policy", urlString: Config.privacyPolicyURL)
                            Divider().overlay(Color.borderAkhrotSoft.opacity(0.5))
                            legalLink("Terms of Use", urlString: Config.termsOfUseURL)
                            Divider().overlay(Color.borderAkhrotSoft.opacity(0.5))
                            legalLink("Support", urlString: Config.supportURL)
                        }
                    }

                    // About card
                    settingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            cardLabel("ABOUT")
                            metaRow("Version", value: Bundle.main.appVersion)
                            Divider().overlay(Color.borderAkhrotSoft.opacity(0.5))
                            metaRow("Build", value: Bundle.main.buildNumber)
                        }
                    }

                    // Wordmark footer
                    VStack(spacing: 6) {
                        Text("Samaan")
                            .font(.pantrySectionHead)
                            .foregroundStyle(Color.inkKohlSoft)
                        HStack(spacing: 4) {
                            Text("سامان")
                                .font(.custom("NotoNastaliqUrdu-Regular", size: 16))
                                .foregroundStyle(Color.inkKohlSoft.opacity(0.8))
                            Text("· Made with care")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.inkKohlSoft.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                }
                .padding(.horizontal, Samaan.Space.md)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.surfaceDoodh)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    SamaanHeader(subtitle: "Preferences & account")
                    Rectangle().frame(height: 1).foregroundStyle(Color.borderAkhrotSoft.opacity(0.5))
                }
                .background(Color.surfaceDoodh)
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Sign out of Samaan?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { await appEnv.auth.signOut(); appEnv.clearLocalStore() }
                }
            }
            .confirmationDialog("Delete your account?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Account", role: .destructive) {
                    Task {
                        isDeleting = true
                        let deleted = await appEnv.auth.deleteAccount()
                        if deleted { appEnv.clearLocalStore() }
                        isDeleting = false
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently removes your account, pantry, lists, and recipes. This can't be undone.")
            }
            .sheet(isPresented: $showPaywall) {
                SamaanPaywallView()
            }
            .alert("Restore Purchases", isPresented: Binding(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } }
            )) {
                Button("OK") { restoreMessage = nil }
            } message: {
                Text(restoreMessage ?? "")
            }
            .fullScreenCover(isPresented: Binding(
                get: { appEnv.isAuthPresented },
                set: { appEnv.isAuthPresented = $0 }
            )) {
                AuthView()
            }
            .sheet(isPresented: $showCustomerCenter) {
                CustomerCenterView()
            }
        }
    }

    // MARK: - Helpers

    private func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            let restoredPro = try await appEnv.purchases.restorePurchases()
            restoreMessage = restoredPro
                ? "Samaan Pro restored."
                : "No Pro purchase found for this Apple ID."
        } catch {
            restoreMessage = "Couldn't restore purchases. Try again."
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .samaanCard()
    }

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.inkKohlSoft)
            .kerning(0.8)
            .padding(.bottom, 4)
    }

    private func metaRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Color.inkKohl)
            Spacer()
            Text(value).font(.samaanMono(13)).foregroundStyle(Color.inkKohlSoft)
        }
    }

    @ViewBuilder
    private func legalLink(_ title: String, urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                HStack {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.inkKohl)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkKohlSoft)
                }
            }
        }
    }
}

private extension Bundle {
    var appVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    var buildNumber: String { infoDictionary?["CFBundleVersion"] as? String ?? "—" }
}

#Preview {
    SettingsView()
        .environment(\.appEnv, AppEnvironment(modelContainer: .preview))
}
