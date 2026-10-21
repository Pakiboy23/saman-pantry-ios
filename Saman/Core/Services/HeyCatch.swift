import Foundation
import PostHog
import SwiftUI

/// How to move PostHog's persisted identity onto the current Supabase session.
///
/// The SDK ignores `identify` once a person is already identified, and it
/// reloads that person after a cold launch. `boundUserID` is the account we
/// last identified, because an anonymous distinct id and a user id are both
/// UUIDs and cannot be told apart from `getDistinctId()` alone.
enum HeyCatchIdentity {
    enum Action: Equatable {
        case none
        case identify(String)
        case reset
        case resetThenIdentify(String)
    }

    static func action(currentUserID: String?, boundUserID: String?) -> Action {
        let current = accountID(currentUserID)
        let bound = accountID(boundUserID)
        if current == bound {
            return .none
        }
        guard let current else {
            return .reset
        }
        guard bound != nil else {
            return .identify(current)
        }
        return .resetThenIdentify(current)
    }

    /// Screenshot launches use `ui-testing`, which is not an account.
    static func accountID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "ui-testing" {
            return nil
        }
        return trimmed
    }
}

/// What `bind` does, in order. `$groupidentify` is last so it uses the
/// distinct id for this session. PostHog 3.92.0 `reset()` does not delete
/// the on-disk event queue, so a group ping queued before the reset would
/// still flush as the previous account.
enum HeyCatchBindEffect: Equatable {
    case resetSDK
    case identify(String)
    case remember(String)
    case forgetBoundUser
    case registerAndGroup
}

enum HeyCatchBind {
    static func effects(
        for action: HeyCatchIdentity.Action,
        alreadyGrouped: Bool
    ) -> [HeyCatchBindEffect] {
        var effects: [HeyCatchBindEffect] = []
        switch action {
        case .none:
            break
        case .identify(let id):
            effects.append(.identify(id))
            effects.append(.remember(id))
        case .reset:
            effects.append(.resetSDK)
            effects.append(.forgetBoundUser)
        case .resetThenIdentify(let id):
            effects.append(.resetSDK)
            effects.append(.identify(id))
            effects.append(.remember(id))
        }
        if action != .none || !alreadyGrouped {
            effects.append(.registerAndGroup)
        }
        return effects
    }
}

/// Screen and product events held until the first session bind. PostHog
/// restores the last person during setup, and SwiftUI can run `onAppear`
/// before the `onChange` that calls `bind`.
struct HeyCatchOutbox: Equatable {
    var isOpen = false
    var screens: [String] = []
    var captures: [String] = []

    enum Delivery: Equatable {
        case screen(String)
        case capture(String)
    }

    mutating func screen(_ name: String) -> [Delivery] {
        guard isOpen else {
            screens.append(name)
            return []
        }
        return [.screen(name)]
    }

    mutating func capture(_ event: String) -> [Delivery] {
        guard isOpen else {
            captures.append(event)
            return []
        }
        return [.capture(event)]
    }

    mutating func open() -> [Delivery] {
        isOpen = true
        let pending = screens.map { Delivery.screen($0) } + captures.map { Delivery.capture($0) }
        screens.removeAll()
        captures.removeAll()
        return pending
    }
}

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
        // The app sends its own fixed screen names and `app_open`. Every
        // automatic capture path stays off, including ones that default on.
        // Swizzling is off so a later default cannot install autocapture.
        config.captureScreenViews = false
        config.captureApplicationLifecycleEvents = false
        config.captureElementInteractions = false
        config.captureSwiftUIElementInteractions = false
        config.captureAutocaptureElementText = false
        config.rageClickConfig.enabled = false
        config.sessionReplay = false
        config.surveys = false
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false
        config.enableSwizzling = false
        config.errorTrackingConfig.autoCapture = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.setDefaultPersonProperties = false
        config.disableGeoIp = true
        PostHogSDK.shared.setup(config)
        // Do not call `group()` here. It queues `$groupidentify` with the
        // distinct id restored from disk, and `reset()` leaves that event
        // in the queue. `bind` groups only after the id matches this session.
    }

    /// Super property plus the project group. `group()` sends `$groupidentify`
    /// for the current distinct id, so call it only after `bind` has reset or
    /// identified.
    private static func registerProject() {
        guard Analytics.isEnabled else { return }
        PostHogSDK.shared.register(["heycatch_project_key": projectKey])
        PostHogSDK.shared.group(type: "project", key: projectKey)
    }

    /// Supabase user id stored at the last `identify`. PostHog keeps that
    /// identity on disk and ignores a later `identify` until `reset`.
    static let boundUserIDKey = "samaan.heycatch.boundUserID"

    /// Point the SDK at the current session before any event is captured.
    /// A cold launch does not emit a user-id change when the session is
    /// already gone, and a same-step account swap never passes through nil.
    static func bind(userID: String?, defaults: UserDefaults = .standard) {
        guard Analytics.isEnabled else { return }
        let bound = defaults.string(forKey: boundUserIDKey)
        let action = HeyCatchIdentity.action(currentUserID: userID, boundUserID: bound)
        let effects = groupLock.withLock {
            HeyCatchBind.effects(for: action, alreadyGrouped: didRegisterProject)
        }
        for effect in effects {
            apply(effect, defaults: defaults)
        }
    }

    private static var didRegisterProject = false
    private static let groupLock = NSLock()

    private static func apply(_ effect: HeyCatchBindEffect, defaults: UserDefaults) {
        switch effect {
        case .resetSDK:
            PostHogSDK.shared.reset()
        case .identify(let id):
            identify(userID: id)
        case .remember(let id):
            defaults.set(id, forKey: boundUserIDKey)
        case .forgetBoundUser:
            defaults.removeObject(forKey: boundUserIDKey)
        case .registerAndGroup:
            registerProject()
            groupLock.withLock { didRegisterProject = true }
        }
    }

    /// Stable account id only. Never an email, a name, or a session token.
    static func identify(userID: String) {
        guard Analytics.isEnabled, !userID.isEmpty, userID != "ui-testing" else { return }
        PostHogSDK.shared.identify(userID)
    }

    /// A business outcome. Pass no properties: names here are fixed strings.
    /// Held until `releaseQueuedEvents` so a cold launch cannot send it
    /// under the previous account.
    static func capture(_ event: String) {
        guard Analytics.isEnabled else { return }
        let deliveries = outboxLock.withLock { outbox.capture(event) }
        send(deliveries)
    }

    /// Fixed screen name. Same hold as `capture` until the initial bind.
    static func screen(_ name: String) {
        guard Analytics.isEnabled else { return }
        let deliveries = outboxLock.withLock { outbox.screen(name) }
        send(deliveries)
    }

    /// Call once the initial session has been bound. Flushes screens and
    /// events that appeared while PostHog still had the previous person.
    static func releaseQueuedEvents() {
        guard Analytics.isEnabled else { return }
        let deliveries = outboxLock.withLock { outbox.open() }
        send(deliveries)
    }

    private static var outbox = HeyCatchOutbox()
    private static let outboxLock = NSLock()

    private static func send(_ deliveries: [HeyCatchOutbox.Delivery]) {
        for delivery in deliveries {
            switch delivery {
            case .screen(let name):
                PostHogSDK.shared.screen(name)
            case .capture(let event):
                PostHogSDK.shared.capture(event)
            }
        }
    }
}

extension View {
    /// Fixed screen name only. Queued until the initial session bind.
    func heycatchScreen(_ name: String) -> some View {
        modifier(HeyCatchScreenModifier(name: name))
    }
}

private struct HeyCatchScreenModifier: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        content.onAppear { HeyCatch.screen(name) }
    }
}
