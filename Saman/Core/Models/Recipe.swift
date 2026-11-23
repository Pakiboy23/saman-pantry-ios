import Foundation
import SwiftData

enum RecipeSourceKind: String, Codable, CaseIterable {
    case transcript
    case url
}

/// Copy for the public Community book. Every recipe starts private; the owner shares it.
enum FamilyBookShareCopy {
    static let addAction = "Share to Community"
    static let removeAction = "Remove from Community"
    static let addTitle = "Share to Community?"
    static let removeTitle = "Remove from Community?"
    static let linkAddMessage = "Signed-in cooks will be able to read this recipe and open its source link. The card shows your display name, or the start of your email if you haven't set one. It stays in your book either way."
    static let spokenAddMessage = "Signed-in cooks will be able to read the steps and ingredients. Your recording and transcript stay off the card. The card shows your display name, or the start of your email if you haven't set one."
    static let removeMessage = "This recipe stays in your book. Other people will no longer see the card."
    static let uploadFailedTitle = "Couldn't update Community"
    static let uploadFailedMessage = "Check your connection and try again."
    static let signInRequired = "Sign in to share to Community."

    static func addMessage(for kind: RecipeSourceKind) -> String {
        switch kind {
        case .transcript:
            return spokenAddMessage
        case .url:
            return linkAddMessage
        }
    }

    static var all: [String] {
        [
            addAction, removeAction, addTitle, removeTitle, linkAddMessage, spokenAddMessage,
            removeMessage, uploadFailedTitle, uploadFailedMessage, signInRequired,
        ]
    }
}

enum FamilyBookShareError: LocalizedError {
    case signedOut
    case failed

    var errorDescription: String? {
        switch self {
        case .signedOut:
            return FamilyBookShareCopy.signInRequired
        case .failed:
            return FamilyBookShareCopy.uploadFailedMessage
        }
    }
}

/// Remembers a family-book tap that had to wait for sign-in.
struct FamilyBookAuthIntent: Equatable {
    var recipeID: UUID?

    mutating func remember(_ recipeID: UUID) {
        self.recipeID = recipeID
    }

    /// Confirmation to show after the sign-in sheet closes. Canceled sign-in clears the tap.
    mutating func resolve(signedIn: Bool) -> UUID? {
        let remembered = recipeID
        recipeID = nil
        guard signedIn else { return nil }
        return remembered
    }
}

/// Local flag change for one family-book upload. A rejected upload restores the snapshot.
struct FamilyBookShareSnapshot: Equatable {
    let share: Bool
    let isDirty: Bool
    let updatedAt: Date

    static func capture(_ recipe: Recipe) -> FamilyBookShareSnapshot {
        FamilyBookShareSnapshot(
            share: recipe.shareInFamilyBook,
            isDirty: recipe.isDirty,
            updatedAt: recipe.updatedAt
        )
    }

    func restore(to recipe: Recipe) {
        recipe.shareInFamilyBook = share
        recipe.isDirty = isDirty
        recipe.updatedAt = updatedAt
    }
}

enum FamilyBookShareCommit {
    /// The upload did not land. A newer local edit uses a different timestamp and must stay.
    static func uploadWasRejected(isDirty: Bool, updatedAt: Date, toggleUpdatedAt: Date) -> Bool {
        isDirty && updatedAt == toggleUpdatedAt
    }

    @MainActor
    static func send(
        _ share: Bool,
        recipe: Recipe,
        context: ModelContext,
        sync: SyncManager
    ) async throws {
        if ScreenshotLaunchConfiguration.current.shouldSeedDemoKitchen {
            recipe.setFamilyBookSharing(share)
            try? context.save()
            return
        }
        guard await sync.signedInUserID() != nil else { throw FamilyBookShareError.signedOut }
        let snapshot = FamilyBookShareSnapshot.capture(recipe)
        recipe.setFamilyBookSharing(share)
        let toggleUpdatedAt = recipe.updatedAt
        try? context.save()
        await sync.syncAll(context: context)
        if uploadWasRejected(isDirty: recipe.isDirty, updatedAt: recipe.updatedAt, toggleUpdatedAt: toggleUpdatedAt) {
            snapshot.restore(to: recipe)
            try? context.save()
            throw FamilyBookShareError.failed
        }
    }
}

@Model
final class Recipe {
    var id: UUID
    var title: String
    var rawTranscript: String
    var extractedJSON: String?
    var attribution: String?
    /// `transcript` (recorded, audio file, or pasted text) or `url`.
    var sourceKind: String = RecipeSourceKind.transcript.rawValue
    /// Owner opt-in to the public Community book. Every recipe starts private.
    var shareInFamilyBook: Bool = false
    var isDirty: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        rawTranscript: String,
        extractedJSON: String? = nil,
        attribution: String? = nil,
        sourceKind: RecipeSourceKind = .transcript,
        shareInFamilyBook: Bool = false
    ) {
        self.id = id
        self.title = title
        self.rawTranscript = rawTranscript
        self.extractedJSON = extractedJSON
        self.attribution = attribution
        self.sourceKind = sourceKind.rawValue
        self.shareInFamilyBook = shareInFamilyBook
        self.isDirty = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var sourceKindValue: RecipeSourceKind {
        get { RecipeSourceKind(rawValue: sourceKind) ?? .transcript }
        set { sourceKind = newValue.rawValue }
    }

    /// Whether this recipe has a Community card. Nothing is public until the owner shares it.
    var isInFamilyBook: Bool { shareInFamilyBook }

    /// My Book shelf line. Says "in Community" only for a recipe the owner shared.
    var myBookStatusLabel: String {
        switch sourceKindValue {
        case .transcript:
            return shareInFamilyBook ? "in Community" : "private"
        case .url:
            return shareInFamilyBook ? "link · in Community" : "link"
        }
    }

    func setFamilyBookSharing(_ share: Bool) {
        shareInFamilyBook = share
        markDirty()
    }

    func markDirty() {
        isDirty = true
        updatedAt = Date()
    }
}
