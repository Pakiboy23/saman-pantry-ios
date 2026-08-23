import Foundation

enum SyncReconcile {
    /// Local dirty rows win until they upload. Otherwise the newer timestamp wins.
    static func shouldApplyServer(localUpdatedAt: Date, localDirty: Bool, serverUpdatedAt: Date) -> Bool {
        if localDirty { return false }
        return serverUpdatedAt >= localUpdatedAt
    }

    /// A local row that is not dirty and missing on the server was deleted elsewhere.
    static func shouldDeleteLocal(localDirty: Bool, presentOnServer: Bool) -> Bool {
        !localDirty && !presentOnServer
    }
}
