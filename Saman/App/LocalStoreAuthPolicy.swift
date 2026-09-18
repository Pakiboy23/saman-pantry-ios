import Foundation

/// Decides when guest browse must drop the on-disk kitchen.
///
/// #20 opened the tab shell without a session. SwiftData and sync tombstones
/// still belonged to the last signed-in account unless Settings sign-out ran.
/// A vanished session (expired refresh, remote revoke, cold start with no
/// Keychain session) then showed that kitchen as "guest" and let deletes
/// queue tombstones that later flushed under the real account.
enum LocalStoreAuthPolicy {
    /// - Parameters:
    ///   - persistedUserID: Last account this install reconciled (`nil` = never signed in).
    ///   - currentUserID: Session user after the latest auth event (`nil` = unsigned).
    static func shouldClearLocalStore(persistedUserID: String?, currentUserID: String?) -> Bool {
        let persisted = normalized(persistedUserID)
        let current = normalized(currentUserID)

        if persisted == nil && current == nil {
            // True guest. Keep the local kitchen.
            return false
        }
        if persisted == nil {
            // First sign-in after guest browse. Upload what they already added.
            return false
        }
        if let persisted, let current, persisted == current {
            // Same account restored. Keep the cache for pull-sync.
            return false
        }
        // Session lost (A → unsigned) or account switch (A → B).
        return true
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.uppercased()
    }
}
