import Foundation
import Testing
@testable import Saman

struct FamilyBookTests {
    @Test func joinLinkParsesOnlySamanpantryJoinPaths() {
        let token = String(repeating: "a1", count: 32)
        #expect(FamilyInviteLink.joinValue(from: URL(string: "https://samanpantry.com/join/\(token)")!) == token)
        #expect(FamilyInviteLink.joinValue(from: URL(string: "https://www.samanpantry.com/join/ABCD2345")!) == "ABCD2345")
        #expect(FamilyInviteLink.joinValue(from: URL(string: "https://evil.com/join/ABCD2345")!) == nil)
        #expect(FamilyInviteLink.joinValue(from: URL(string: "http://samanpantry.com/join/ABCD2345")!) == nil)
        #expect(FamilyInviteLink.joinValue(from: URL(string: "https://samanpantry.com/privacy")!) == nil)
        #expect(FamilyInviteLink.joinValue(from: URL(string: "samaan://auth-callback")!) == nil)
    }

    @Test func displayNameIsTrimmedAndCollapsed() {
        #expect(FamilyDisplayName.normalized("   Sam    Rivera  ") == "Sam Rivera")
        #expect(FamilyDisplayName.normalized("   ").isEmpty)
        #expect(FamilyNameSection.isValid(String(repeating: "x", count: 40)))
        #expect(!FamilyNameSection.isValid(String(repeating: "x", count: 41)))
        struct Fake: Error, CustomStringConvertible { let description: String }
        #expect(FamilyError.from(Fake(description: "hint: name_too_long")) == .nameTooLong)
    }

    @Test func codeEntryIsNormalized() {
        #expect(FamilyInviteLink.normalizedCode(" abcd-2345 ") == "ABCD2345")
    }

    @Test func memberFieldsNeverIncludeTranscript() {
        #expect(!FamilyRecipe.memberFieldKeys.contains("raw_transcript"))
    }

    @Test func serverHintsMapToPlainErrors() {
        struct Fake: Error, CustomStringConvertible { let description: String }
        #expect(FamilyError.from(Fake(description: "hint: pro_required")) == .proRequired)
        #expect(FamilyError.from(Fake(description: "hint: pro_required"), isProOnDevice: true) == .proSyncing)
        #expect(FamilyError.from(Fake(description: "family_full")) == .familyFull)
    }

    @Test func familyCopyFollowsBrandRules() {
        let all = FamilyCopy.all + [FamilyInvite(code: "ABCD2345", token: "t", expiresAt: .now).shareText]
        for line in all {
            #expect(!line.contains("\u{2014}"), "em dash in: \(line)")
            #expect(!line.contains("Pantry Pro"))
            for word in [" his ", " her ", " he ", " she "] {
                #expect(!" \(line.lowercased()) ".contains(word), "gendered: \(line)")
            }
        }
        #expect(FamilyCopy.paywallContext.contains("Samaan Pro"))
    }

    @Test func savedCopyDecodesAsExtractedRecipe() throws {
        let recipe = FamilyRecipe(
            familyId: UUID(), recipeId: UUID(), addedBy: nil, addedByLabel: "a cook",
            title: "Aloo keema", attribution: "Nani", steps: ["Fry onions"],
            ingredientPhrases: ["andaza namak"], sourceUrl: nil, addedAt: .now
        )
        let decoded = try JSONDecoder().decode(ExtractedRecipe.self, from: Data(recipe.copyExtractedJSON.utf8))
        #expect(decoded.title == "Aloo keema")
        #expect(decoded.ingredients.first?.originalPhrase == "andaza namak")
    }

    @Test @MainActor func savedCopyOfSpokenFamilyRecipeStaysOutOfTheVillageBook() {
        let recipe = FamilyRecipe(
            familyId: UUID(), recipeId: UUID(), addedBy: nil, addedByLabel: "a cook",
            title: "Aloo keema", attribution: "Nani", steps: ["Fry onions"],
            ingredientPhrases: ["andaza namak"], sourceUrl: nil, addedAt: .now
        )
        let copy = recipe.ownedCopy()
        #expect(copy.sourceKindValue == .url)
        #expect(!copy.sourceKindValue.publishesToFamilyBook)
        #expect(!copy.shareInFamilyBook)
        #expect(!copy.isInFamilyBook)
        #expect(copy.rawTranscript.isEmpty)
        #expect(copy.title == "Aloo keema")
        #expect(copy.attribution == "Nani")
    }

    @Test @MainActor func savedCopyOfLinkedFamilyRecipeStaysPrivateUntilOptIn() {
        let url = "https://www.youtube.com/watch?v=example"
        let recipe = FamilyRecipe(
            familyId: UUID(), recipeId: UUID(), addedBy: nil, addedByLabel: "a cook",
            title: "YouTube Karahi", attribution: "Ammi", steps: ["Fry onions"],
            ingredientPhrases: ["andaza namak"], sourceUrl: url, addedAt: .now
        )
        let copy = recipe.ownedCopy()
        #expect(copy.sourceKindValue == .url)
        #expect(!copy.shareInFamilyBook)
        #expect(!copy.isInFamilyBook)
        #expect(copy.rawTranscript == url)
    }
}
