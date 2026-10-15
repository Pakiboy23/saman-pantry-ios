import Foundation
import PostHog

/// HeyCatch product analytics. The ingest speaks the PostHog protocol, so this
/// uses PostHog's iOS SDK pointed at HeyCatch. The token and host are HeyCatch's
/// write-only ingest values, safe to ship in the binary.
///
/// Only screen views and named product events leave the device. Recipe text,
/// transcripts, audio, emails, names, and other personal content are never
/// properties. Tests, previews, and screenshot runs never start the SDK.
enum HeyCatch {
    static let projectKey = "hck_pk_rXbQgjO9gc2iHd6hlRBq_y_178czzi4R"
    private static let ingestToken = "phc_oiDt6uXiBiEA2aT43SMzMAFE9D4gMVkRP3BtvYRsmHqe"
    private static let ingestHost = "https://in.heycatch.ai"

    /// Call once from `SamaanApp.init`.
    static func start() {
        guard Analytics.isEnabled else { return }

        // `apiKey` in the HeyCatch guide is this initializer. The 3.x SDK
        // deprecated that name; `projectToken` is the same argument.
        let config = PostHogConfig(projectToken: ingestToken, host: ingestHost)
        // SwiftUI screens are named by hand. UIKit autocapture would reuse
        // navigation titles, and a shopping list's title is the list name.
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.captureSwiftUIElementInteractions = false
        config.captureAutocaptureElementText = false
        config.rageClickConfig.enabled = false
        config.sessionReplay = false
        config.surveys = false
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.setDefaultPersonProperties = false
        config.disableGeoIp = true
        PostHogSDK.shared.setup(config)
        registerProject()
    }

    /// `reset()` clears the registered key and the project group. Call this
    /// again immediately after every reset.
    static func registerProject() {
        guard Analytics.isEnabled else { return }
        PostHogSDK.shared.register(["heycatch_project_key": projectKey])
        PostHogSDK.shared.group(type: "project", key: projectKey)
    }

    /// Stable account id only. Never an email, a name, or a session token.
    static func identify(userID: String) {
        guard Analytics.isEnabled, !userID.isEmpty, userID != "ui-testing" else { return }
        PostHogSDK.shared.identify(userID)
    }

    static func reset() {
        guard Analytics.isEnabled else { return }
        PostHogSDK.shared.reset()
        registerProject()
    }

    /// A business outcome. Pass no properties: names here are fixed strings.
    static func capture(_ event: String) {
        guard Analytics.isEnabled else { return }
        PostHogSDK.shared.capture(event)
    }
}
