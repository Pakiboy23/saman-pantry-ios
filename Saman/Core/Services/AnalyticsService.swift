import Foundation

/// Anonymous, fire-and-forget product analytics.
///
/// Each event is one row in the Supabase `events` table: a random per-install
/// UUID, the event name, and the app version. There's no account id, email, or
/// user content, and the request uses the public anon key (never the user's
/// session), so events can't be linked back to an account. RLS allows INSERT
/// only. App Privacy: Usage Data → Product Interaction, not linked, not tracking.
enum AnalyticsEvent: String, CaseIterable, Sendable {
    case appOpen = "app_open"
    case signup = "signup"
    case guestStart = "guest_start"
    case itemAdded = "item_added"
    case listItemBought = "list_item_bought"
    case pantryRestocked = "pantry_restocked"
    case recipeSaved = "recipe_saved"
    case recipeExtracted = "recipe_extracted"
    case paywallViewed = "paywall_viewed"
    case purchaseStarted = "purchase_started"
}

enum Analytics {
    static let installIDKey = "samaan.analytics.installID"
    private static let onceKeyPrefix = "samaan.analytics.once."

    /// Tests, previews, and screenshot runs never send.
    static var isEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return false }
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return false }
        if ScreenshotLaunchConfiguration.current.isUITesting { return false }
        if ScreenshotLaunchConfiguration.current.shouldSeedDemoKitchen { return false }
        return true
    }

    static func installID(defaults: UserDefaults = .standard) -> UUID {
        if let raw = defaults.string(forKey: installIDKey), let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: installIDKey)
        return id
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    static func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        let body = payload(event: event, installID: installID(), appVersion: appVersion)
        Task.detached(priority: .utility) {
            await Analytics.send(body)
        }
    }

    /// Track an event at most once per install (for example `guest_start`).
    static func trackOnce(_ event: AnalyticsEvent, defaults: UserDefaults = .standard) {
        let key = onceKeyPrefix + event.rawValue
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        track(event)
    }

    static func payload(event: AnalyticsEvent, installID: UUID, appVersion: String) -> [String: String] {
        [
            "install_id": installID.uuidString.lowercased(),
            "event": event.rawValue,
            "app_version": String(appVersion.prefix(32)),
        ]
    }

    private static func send(_ body: [String: String]) async {
        guard let url = URL(string: "\(Config.supabaseURL)/rest/v1/events"),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = data
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                AppLogger.error("[Analytics] \(body["event"] ?? "?") HTTP \(http.statusCode)")
            }
        } catch {
            // Offline or blocked: analytics are best-effort, never retried.
        }
    }
}
