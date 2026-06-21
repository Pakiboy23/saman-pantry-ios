import SwiftUI
import SwiftData
import CoreText
import RevenueCat

@main
struct SamanApp: App {
    @State private var appEnv = AppEnvironment()

    init() {
        registerFonts()
        configureNavigationBarAppearance()
        configureTabBarAppearance()
        configureRevenueCat()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appEnv, appEnv)
                .tint(Color.brandSaag)
                .onChange(of: appEnv.auth.currentUserID) { _, userID in
                    if let userID {
                        appEnv.purchases.setAppUserID(userID)
                    }
                }
        }
        .modelContainer(appEnv.modelContainer)
    }

    // MARK: - RevenueCat

    private func configureRevenueCat() {
        Purchases.logLevel = .error
        Purchases.configure(withAPIKey: Config.revenueCatAPIKey)
    }

    // MARK: - Font registration

    private func registerFonts() {
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

    private func configureNavigationBarAppearance() {
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

    private func configureTabBarAppearance() {
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
