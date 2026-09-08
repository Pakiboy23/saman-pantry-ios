import SwiftUI
import SwiftData
import UIKit
import CoreText
import RevenueCat

@main
struct SamaanApp: App {
    @State private var appEnv: AppEnvironment

    init() {
        // Static helpers: instance methods cannot run before `_appEnv` is set.
        Self.registerFonts()
        Self.configureNavigationBarAppearance()
        Self.configureTabBarAppearance()
        Self.configureRevenueCat()

        let launch = ScreenshotLaunchConfiguration.current
        if launch.isUITesting {
            UIView.setAnimationsEnabled(false)
        }
        let container: ModelContainer = launch.usesInMemoryStore ? .preview : .shared
        let env = AppEnvironment(modelContainer: container)
        if launch.shouldSeedDemoKitchen {
            ScreenshotDemoKitchen.seed(into: env.modelContainer.mainContext)
        }
        _appEnv = State(initialValue: env)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appEnv, appEnv)
                .tint(Color.brandSaag)
                .onChange(of: appEnv.auth.currentUserID) { _, userID in
                    if ScreenshotLaunchConfiguration.current.skipsAuth { return }
                    if let userID {
                        appEnv.purchases.setAppUserID(userID)
                    }
                }
                .onOpenURL { url in
                    Task { await appEnv.auth.handleAuthURL(url) }
                }
        }
        .modelContainer(appEnv.modelContainer)
    }

    // MARK: - RevenueCat

    private static func configureRevenueCat() {
        Purchases.logLevel = .error
        Purchases.configure(withAPIKey: Config.revenueCatAPIKey)
    }

    // MARK: - Font registration

    private static func registerFonts() {
        let names = [
            "CormorantGaramond-Bold",
            "CormorantGaramond-SemiBold",
            "NotoNastaliqUrdu-Regular",
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                AppLogger.debug("[Fonts] \(name).ttf not found in bundle")
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if let e = error { AppLogger.debug("[Fonts] \(name): \(e.takeRetainedValue())") }
        }
    }

    // MARK: - Navigation bar appearance

    private static func configureNavigationBarAppearance() {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(Color.surfaceDoodh)
        navAppearance.shadowColor = UIColor(Color.borderAkhrotSoft.opacity(0.5))

        // Standard title — Cormorant SemiBold
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(Color.inkKohl),
            .font: UIFont(name: "CormorantGaramond-SemiBold", size: 17) ?? UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]

        // Large title — Cormorant Bold
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(Color.inkKohl),
            .font: UIFont(name: "CormorantGaramond-Bold", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
        ]

        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(Color.brandSaag)
    }

    // MARK: - Tab bar appearance

    private static func configureTabBarAppearance() {
        // Saag palette colors
        let doodh = UIColor(Color.surfaceDoodh)          // #FCF8EE light
        let kohlSoft = UIColor(Color.inkKohlSoft)        // #5C5448 light
        let saag = UIColor(Color.brandSaag)              // #3F6B47 light
        let border = UIColor(Color.borderAkhrotSoft.opacity(0.5))

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = doodh
        appearance.shadowColor = border      // produces the 1pt top hairline
        appearance.backgroundEffect = nil   // no blur / glass

        // Remove the selection indicator pill/capsule entirely
        appearance.selectionIndicatorImage = UIImage()
        appearance.selectionIndicatorTintColor = .clear

        let normal:   [NSAttributedString.Key: Any] = [.foregroundColor: kohlSoft]
        let selected: [NSAttributedString.Key: Any] = [.foregroundColor: saag]

        for layout in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ] {
            layout.normal.titleTextAttributes  = normal
            layout.selected.titleTextAttributes = selected
            layout.normal.iconColor  = kohlSoft
            layout.selected.iconColor = saag
        }

        UITabBar.appearance().standardAppearance   = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
