import Foundation
import SwiftData

enum RecipeSourceKind: String, Codable, CaseIterable {
    case transcript
    case url
    /// A member's private copy of a family recipe. Never a community card.
    case copied

    /// True when a save publishes with no extra step. URL extracts stay private
    /// until the owner sets `Recipe.shareInFamilyBook`. Family copies stay private.
    var publishesToFamilyBook: Bool { self == .transcript }
}

enum FamilyBookShareCopy {
    static let addAction = "Add to family book"
    static let removeAction = "Remove from family book"
    static let addTitle = "Add to the family book?"
    static let removeTitle = "Remove from the family book?"
    static let addMessage = "Signed-in cooks will be able to read this recipe and open its source link. It stays in your book either way."
    static let removeMessage = "This recipe stays in your book. Other people will no longer see the card."
    static let uploadFailedTitle = "Couldn't update the family book"
    static let uploadFailedMessage = "Check your connection and try again."
    static let signInRequired = "Sign in to change the family book."

    static var all: [String] {
        [
            addAction, removeAction, addTitle, removeTitle, addMessage, removeMessage,
            uploadFailedTitle, uploadFailedMessage, signInRequired,
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
        guard recipe.sourceKindValue == .url else { return }
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
    /// `transcript`, `url`, or `copied`. Transcript saves become public family-book cards.
    var sourceKind: String = RecipeSourceKind.transcript.rawValue
    /// Owner opt-in for a link recipe. Transcripts publish either way.
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

    /// Whether this recipe has a family-book card. Link recipes stay out until the owner opts in.
    var isInFamilyBook: Bool {
        switch sourceKindValue {
        case .transcript:
            return true
        case .url:
            return shareInFamilyBook
        case .copied:
            return false
        }
    }

    /// My Book shelf line. A private link stays "link". A shared link says both.
    var myBookStatusLabel: String {
        switch sourceKindValue {
        case .transcript:
            return "in the family book"
        case .url:
            return shareInFamilyBook ? "link · in the family book" : "link"
        case .copied:
            return "family copy"
        }
    }

    /// Link recipes only. Transcripts keep publishing, so this does not clear them.
    func setFamilyBookSharing(_ share: Bool) {
        guard sourceKindValue == .url else { return }
        shareInFamilyBook = share
        markDirty()
    }

    func markDirty() {
        isDirty = true
        updatedAt = Date()
    }
}
