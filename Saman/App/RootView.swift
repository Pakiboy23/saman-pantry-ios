import SwiftUI

struct RootView: View {
    @Environment(\.appEnv) private var appEnv
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(OnboardingStorage.completedKey) private var hasCompletedOnboarding = false
    @State private var selectedTab: AppTab
    @State private var showScreenshotRecipeReview: Bool
    @State private var showScreenshotPaywall: Bool
    /// False until this launch has called `HeyCatch.bind`. Child screen
    /// views capture in `onAppear`, which can run before the app `onChange`.
    @State private var hasBoundIdentity = false

    private enum AppTab: Hashable {
        case home, pantry, lists, recipes
    }

    init() {
        let launch = ScreenshotLaunchConfiguration.current
        let scene = launch.scene
        _selectedTab = State(initialValue: Self.tab(for: scene))
        // Don't present capture sheets over the splash. -UITesting is signed
        // in before the first frame; a demo-account sign-in presents after.
        let presentNow = launch.skipsAuth
        _showScreenshotRecipeReview = State(initialValue: presentNow && scene == .recipeReview)
        _showScreenshotPaywall = State(initialValue: presentNow && scene == .paywall)
        // Screenshot / UI-test launches skip onboarding so seeded scenes stay reachable.
        if launch.skipsAuth {
            UserDefaults.standard.set(true, forKey: OnboardingStorage.completedKey)
        }
    }

    private static func tab(for scene: ScreenshotLaunchConfiguration.Scene?) -> AppTab {
        switch scene {
        case .pantry:
            return .pantry
        case .shoppingList:
            return .lists
        case .recipeReview:
            return .recipes
        case .home, .paywall, nil:
            return .home
        }
    }

    var body: some View {
        Group {
            if !appEnv.auth.hasCheckedInitialSession || !hasBoundIdentity {
                // Splash until the cached session is known and HeyCatch has
                // bound it. Leaving earlier lets Home, Onboarding, or Auth
                // capture a screen under the person PostHog restored from disk.
                ZStack {
                    Color.surfaceDoodh.ignoresSafeArea()
                    VStack(spacing: 8) {
                        Text("Samaan")
                            .font(.pantryWordmark)
                            .foregroundStyle(Color.brandSaag)
                        Text("سامان")
                            .font(.custom("NotoNastaliqUrdu-Regular", size: 22))
                            .foregroundStyle(Color.inkKohlSoft)
                    }
                }
            } else if appEnv.auth.isRecoveringPassword {
                AuthView(allowsDismiss: false)
            } else if !hasCompletedOnboarding {
                OnboardingView {
                    HeyCatch.capture("onboarding_completed")
                    hasCompletedOnboarding = true
                }
            } else {
                tabShell
                    .onAppear {
                        if ScreenshotLaunchConfiguration.current.skipsAuth { return }
                        appEnv.reconcileLocalStore(currentUserID: appEnv.auth.currentUserID)
                    }
            }
        }
        .task { await appEnv.auth.startListening() }
        .onAppear { bindIdentityBeforeScreens() }
        .onChange(of: appEnv.auth.hasCheckedInitialSession) { _, _ in
            bindIdentityBeforeScreens()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && appEnv.auth.isSignedIn { appEnv.syncNow() }
        }
        .onChange(of: appEnv.auth.isSignedIn) { _, signedIn in
            if ScreenshotLaunchConfiguration.current.skipsAuth { return }
            appEnv.reconcileLocalStore(currentUserID: signedIn ? appEnv.auth.currentUserID : nil)
            if signedIn {
                appEnv.isAuthPresented = false
                appEnv.syncNow()
                Task { await appEnv.extractionQuota.refresh() }
                presentScreenshotSheetsIfNeeded()
            } else {
                appEnv.extractionQuota.resetForSignOut()
            }
        }
        .sheet(isPresented: $showScreenshotRecipeReview) {
            RecipeCaptureView(demoReview: ScreenshotDemoKitchen.chickenKarahiReview)
        }
        .sheet(isPresented: $showScreenshotPaywall) {
            SamaanPaywallView()
                .accessibilityIdentifier("screenshot.paywall")
        }
    }

    private var tabShell: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppTab.home)

            InventoryView()
                .tabItem {
                    Label("Pantry", systemImage: "cabinet.fill")
                }
                .tag(AppTab.pantry)

            ShoppingListsView()
                .tabItem {
                    Label("Lists", systemImage: "list.bullet.rectangle.fill")
                }
                .tag(AppTab.lists)

            RecipesView()
                .tabItem {
                    Label("Recipes", systemImage: "fork.knife")
                }
                .tag(AppTab.recipes)
        }
        .tint(Color.brandSaag)
    }

    /// Bind while splash is still up, then reveal the real root. `onAppear`
    /// covers a session that was already checked; `onChange` covers the
    /// cold-launch flip. Either way the next body is the first one that can
    /// mount a screen view.
    private func bindIdentityBeforeScreens() {
        guard appEnv.auth.hasCheckedInitialSession, !hasBoundIdentity else { return }
        HeyCatch.bind(userID: appEnv.auth.currentUserID)
        hasBoundIdentity = true
    }

    private func presentScreenshotSheetsIfNeeded() {
        switch ScreenshotLaunchConfiguration.current.scene {
        case .recipeReview:
            showScreenshotRecipeReview = true
        case .paywall:
            showScreenshotPaywall = true
        case .home, .pantry, .shoppingList, nil:
            break
        }
    }
}

#Preview {
    RootView()
        .environment(\.appEnv, AppEnvironment(modelContainer: .preview))
}
