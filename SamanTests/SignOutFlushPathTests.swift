import Foundation
import Testing
@testable import Saman

/// Sign-out used to drop the session and wipe the delete queue before an
/// in-flight `syncNow()` finished, so a just-deleted row came back on the
/// next sign-in. These source locks keep the flush-then-sign-out order.
struct SignOutFlushPathTests {
    @Test func settingsSignOutFlushesBeforeDroppingTheSession() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settings = try String(
            contentsOf: repoRoot.appendingPathComponent("Saman/Features/Settings/SettingsView.swift"),
            encoding: .utf8
        )
        let environment = try String(
            contentsOf: repoRoot.appendingPathComponent("Saman/App/AppEnvironment.swift"),
            encoding: .utf8
        )
        let sync = try String(
            contentsOf: repoRoot.appendingPathComponent("Saman/Core/Services/SyncManager.swift"),
            encoding: .utf8
        )

        let signOutStart = try #require(settings.range(of: "Button(\"Sign Out\", role: .destructive)"))
        let signOutBody = settings[signOutStart.lowerBound...]
        let flushRange = try #require(signOutBody.range(of: "flushPendingSync()"))
        let sessionDrop = try #require(signOutBody.range(of: "auth.signOut()"))
        #expect(flushRange.lowerBound < sessionDrop.lowerBound)

        #expect(environment.contains("func flushPendingSync() async"))
        #expect(environment.contains("await syncManager.syncAll"))

        #expect(sync.contains("syncWaiters"))
        #expect(sync.contains("withCheckedContinuation"))
    }
}
