import SwiftUI

struct RootView: View {
    @Environment(\.appEnv) private var appEnv
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab
    @State private var showScreenshotRecipeReview: Bool
    @State private var showScreenshotPaywall: Bool

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
            if !appEnv.auth.hasCheckedInitialSession {
                // Splash — wait for Supabase to resolve the cached session
                // before committing to either screen (prevents tab-bar flash)
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
            } else {
                tabShell
                    .onAppear {
                        if ScreenshotLaunchConfiguration.current.skipsAuth { return }
                        appEnv.reconcileLocalStore(currentUserID: appEnv.auth.currentUserID)
                    }
            }
        }
        .task { await appEnv.auth.startListening() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && appEnv.auth.isSignedIn { appEnv.syncNow() }
        }
        .onChange(of: appEnv.auth.isSignedIn) { _, signedIn in
            if ScreenshotLaunchConfiguration.current.skipsAuth { return }
            appEnv.reconcileLocalStore(currentUserID: signedIn ? appEnv.auth.currentUserID : nil)
            guard signedIn else { return }
            appEnv.isAuthPresented = false
            appEnv.syncNow()
            presentScreenshotSheetsIfNeeded()
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
