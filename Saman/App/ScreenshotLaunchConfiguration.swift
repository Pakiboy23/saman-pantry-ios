import Foundation

/// Launch-argument contract for App Store screenshot capture and UI tests.
///
/// This is **not** guest mode. Production launches never pass these flags, so
/// auth still gates the tab shell. The Mac capture script and
/// `AppStoreScreenshotUITests` pass `-UITesting` so Simulator can show a seeded
/// desi kitchen without a live session.
struct ScreenshotLaunchConfiguration: Equatable, Sendable {
    enum Scene: String, Equatable, Sendable {
        case home
        case pantry
        case recipeReview
        case shoppingList
        case paywall
    }

    /// Explicit light/dark override from `-ScreenshotAppearance`.
    /// App Store shots should match a Dark Mode device (forest-green
    /// `surfaceDoodh` / `surfaceMalai`), not the cream light palette.
    enum Appearance: String, Equatable, Sendable {
        case light
        case dark
    }

    var isUITesting: Bool
    var shouldSeedDemoKitchen: Bool
    var skipsAuth: Bool
    var usesInMemoryStore: Bool
    var scene: Scene?
    var appearance: Appearance?

    /// Dark Mode is the App Store look: green cards on near-black doodh.
    /// Capture defaults to dark even if `-ScreenshotAppearance` is omitted.
    var usesDarkAppearance: Bool {
        switch appearance {
        case .dark:
            return true
        case .light:
            return false
        case nil:
            return isUITesting || shouldSeedDemoKitchen
        }
    }

    static var current: ScreenshotLaunchConfiguration {
        parse(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func parse(
        arguments: [String],
        environment: [String: String]
    ) -> ScreenshotLaunchConfiguration {
        _ = environment
        let isUITesting = arguments.contains("-UITesting")
        let shouldSeedDemoKitchen = isUITesting || arguments.contains("-ScreenshotSeed")
        var scene: Scene?
        if let flagIndex = arguments.firstIndex(of: "-ScreenshotScene") {
            let valueIndex = arguments.index(after: flagIndex)
            if valueIndex < arguments.endIndex {
                scene = Scene(rawValue: arguments[valueIndex])
            }
        }
        var appearance: Appearance?
        if let flagIndex = arguments.firstIndex(of: "-ScreenshotAppearance") {
            let valueIndex = arguments.index(after: flagIndex)
            if valueIndex < arguments.endIndex {
                appearance = Appearance(rawValue: arguments[valueIndex])
            }
        }
        return ScreenshotLaunchConfiguration(
            isUITesting: isUITesting,
            shouldSeedDemoKitchen: shouldSeedDemoKitchen,
            skipsAuth: isUITesting,
            usesInMemoryStore: shouldSeedDemoKitchen,
            scene: scene,
            appearance: appearance
        )
    }
}
