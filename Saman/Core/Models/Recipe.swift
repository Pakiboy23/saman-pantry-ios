import Foundation
import SwiftData

enum RecipeSourceKind: String, Codable, CaseIterable {
    case transcript
    case url

    /// True when a save publishes with no extra step. URL extracts stay private
    /// until the owner sets `Recipe.shareInFamilyBook`.
    var publishesToFamilyBook: Bool { self == .transcript }
}

enum FamilyBookShareCopy {
    static let addAction = "Add to family book"
    static let removeAction = "Remove from family book"
    static let addTitle = "Add to the family book?"
    static let removeTitle = "Remove from the family book?"
    static let addMessage = "Signed-in cooks will be able to read this recipe and open its source link. It stays in your book either way."
    static let removeMessage = "This recipe stays in your book. Other people will no longer see the card."

    static var all: [String] {
        [addAction, removeAction, addTitle, removeTitle, addMessage, removeMessage]
    }
}

@Model
final class Recipe {
    var id: UUID
    var title: String
    var rawTranscript: String
    var extractedJSON: String?
    var attribution: String?
    /// `transcript` or `url`. Transcript saves become public family-book cards.
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
        }
    }

    /// My Book shelf line. A private link stays "link". A shared link says both.
    var myBookStatusLabel: String {
        switch sourceKindValue {
        case .transcript:
            return "in the family book"
        case .url:
            return shareInFamilyBook ? "link · in the family book" : "link"
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
