import SwiftUI
import RevenueCatUI

struct SettingsView: View {
    @Environment(\.appEnv) private var appEnv
    @State private var showSignOutConfirm = false
    @State private var showPaywall = false
    @State private var showCustomerCenter = false

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
                                        .foregroundStyle(Color.samanAccent)
                                    Text("Saman Pro")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.samanPrimary)
                                    Spacer()
                                    Button("Manage") { showCustomerCenter = true }
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.samanMuted)
                                }
                            } else {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Free plan")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color.samanPrimary)
                                        Text("Upgrade to Pro to support development")
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundStyle(Color.samanMuted)
                                    }
                                    Spacer()
                                    Button("Upgrade") { showPaywall = true }
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.samanBg)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(Color.samanAccent)
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
                                        .foregroundStyle(Color.samanAccent)
                                    Text("Sync now")
                                        .foregroundStyle(Color.samanPrimary)
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
                                        .foregroundStyle(Color.samanRed)
                                    Text("Sign out")
                                        .foregroundStyle(Color.samanRed)
                                    Spacer()
                                }
                                .font(.system(size: 15))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // About card
                    settingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            cardLabel("ABOUT")
                            metaRow("Version", value: Bundle.main.appVersion)
                            Divider().overlay(Color.samanBorder)
                            metaRow("Build", value: Bundle.main.buildNumber)
                        }
                    }

                    // Wordmark footer
                    VStack(spacing: 6) {
                        Text("Saman")
                            .font(.cormorant(22))
                            .foregroundStyle(Color.samanMuted)
                        HStack(spacing: 4) {
                            Text("سامان")
                                .font(.custom("NotoNastaliqUrdu-Regular", size: 16))
                                .foregroundStyle(Color.samanMuted.opacity(0.8))
                            Text("· Made with care")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.samanMuted.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                }
                .padding(.horizontal, Saman.Space.md)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.samanBg)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    SamanHeader(subtitle: "Preferences & account")
                    Rectangle().frame(height: 1).foregroundStyle(Color.samanBorder)
                }
                .background(Color.samanBg)
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Sign out of Saman?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { await appEnv.auth.signOut() }
                }
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
            .foregroundStyle(Color.samanMuted)
            .kerning(0.8)
            .padding(.bottom, 4)
    }

    private func metaRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Color.samanSecondary)
            Spacer()
            Text(value).font(.samanMono(13)).foregroundStyle(Color.samanMuted)
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
