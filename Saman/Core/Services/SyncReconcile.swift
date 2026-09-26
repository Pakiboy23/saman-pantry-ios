import Foundation

enum SyncReconcile {
    /// Identity of a queued server delete. Table + id, not just id — two
    /// tables can theoretically share a UUID.
    struct TombstoneID: Hashable {
        let table: String
        let id: UUID
    }

    /// Local dirty rows win until they upload. Otherwise the newer timestamp wins.
    static func shouldApplyServer(localUpdatedAt: Date, localDirty: Bool, serverUpdatedAt: Date) -> Bool {
        if localDirty { return false }
        return serverUpdatedAt >= localUpdatedAt
    }

    /// A local row that is not dirty and missing on the server was deleted elsewhere.
    static func shouldDeleteLocal(localDirty: Bool, presentOnServer: Bool) -> Bool {
        !localDirty && !presentOnServer
    }

    /// After a flush, keep the live queue minus IDs the server accepted.
    /// A delete queued during the network wait must survive; a successful
    /// delete must not stay queued.
    static func remainingTombstones(
        current: [TombstoneID],
        successfullyDeleted: Set<TombstoneID>
    ) -> [TombstoneID] {
        current.filter { !successfullyDeleted.contains($0) }
    }

    /// Pull must not re-insert a row the user already deleted locally.
    static func shouldInsertPulledRow(id: UUID, tombstonedIDs: Set<UUID>) -> Bool {
        !tombstonedIDs.contains(id)
    }

    /// If the local row changed while the upsert was in flight, keep it dirty
    /// so the next sync uploads the newer values (mark-bought, rename, etc.).
    static func shouldClearDirtyAfterUpload(uploadedUpdatedAt: Date, currentUpdatedAt: Date) -> Bool {
        uploadedUpdatedAt == currentUpdatedAt
    }
}
