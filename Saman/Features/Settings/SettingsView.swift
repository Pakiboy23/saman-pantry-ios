import SwiftUI
import RevenueCatUI

struct SettingsView: View {
    @Environment(\.appEnv) private var appEnv
    @State private var showSignOutConfirm = false
    @State private var showPaywall = false
    @State private var showCustomerCenter = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Subscription card
                    settingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            cardLabel("SUBSCRIPTION")
                            if appEnv.purchases.isPro {
                                HStack {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(Color.brandSaag)
                                    Text("Saman Pro")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.inkKohl)
                                    Spacer()
                                    Button("Manage") { showCustomerCenter = true }
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.inkKohlSoft)
                                }
                            } else {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Free plan")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color.inkKohl)
                                        Text("Upgrade to Pro to support development")
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundStyle(Color.inkKohlSoft)
                                    }
                                    Spacer()
                                    Button("Upgrade") { showPaywall = true }
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.surfaceDoodh)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(Color.brandSaag)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Sync card
                    settingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            cardLabel("SYNC")
                            Button {
                                appEnv.syncNow()
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
                        Text("Saman")
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
                .padding(.horizontal, Saman.Space.md)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.surfaceDoodh)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    SamanHeader(subtitle: "Preferences & account")
                    Rectangle().frame(height: 1).foregroundStyle(Color.borderAkhrotSoft.opacity(0.5))
                }
                .background(Color.surfaceDoodh)
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Sign out of Saman?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
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
                SamanPaywallView()
            }
            .sheet(isPresented: $showCustomerCenter) {
                CustomerCenterView()
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .samanCard()
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
            Text(value).font(.samanMono(13)).foregroundStyle(Color.inkKohlSoft)
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
