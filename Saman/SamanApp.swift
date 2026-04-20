import SwiftUI
import SwiftData
import CoreText

@main
struct SamanApp: App {
    @State private var appEnv = AppEnvironment()

    init() {
        registerFonts()
        configureTabBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appEnv, appEnv)
        }
        .modelContainer(appEnv.modelContainer)
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
                print("[Fonts] \(name).ttf not found in bundle")
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if let e = error { print("[Fonts] \(name): \(e.takeRetainedValue())") }
        }
    }

    // MARK: - Tab bar appearance

    private func configureTabBarAppearance() {
        // #FAF6EF — spec cream background
        let cream  = UIColor(red: 0.980, green: 0.965, blue: 0.937, alpha: 1)
        let muted  = UIColor(red: 0.604, green: 0.518, blue: 0.447, alpha: 1) // #9A8472
        let accent = UIColor(red: 0.776, green: 0.494, blue: 0.165, alpha: 1) // #C67E2A
        // rgba(28,15,0,0.1) top border
        let border = UIColor(red: 28/255, green: 15/255, blue: 0, alpha: 0.10)

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = cream
        appearance.shadowColor = border      // produces the 1pt top hairline
        appearance.backgroundEffect = nil   // no blur / glass

        // Remove the selection indicator pill/capsule entirely
        appearance.selectionIndicatorImage = UIImage()
        appearance.selectionIndicatorTintColor = .clear

        let normal:   [NSAttributedString.Key: Any] = [.foregroundColor: muted]
        let selected: [NSAttributedString.Key: Any] = [.foregroundColor: accent]

        for layout in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ] {
            layout.normal.titleTextAttributes  = normal
            layout.selected.titleTextAttributes = selected
            layout.normal.iconColor  = muted
            layout.selected.iconColor = accent
        }

        UITabBar.appearance().standardAppearance   = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
