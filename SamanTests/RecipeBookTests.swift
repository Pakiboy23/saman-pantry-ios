import Foundation
import Testing
@testable import Saman

@MainActor
struct RecipeBookTests {
    @Test func transcriptSourcePublishesAndUrlDoesNot() {
        #expect(RecipeSourceKind.transcript.publishesToFamilyBook)
        #expect(!RecipeSourceKind.url.publishesToFamilyBook)
    }

    @Test func transcriptRecipeKeepsAndazaPhraseInExtractedJSON() throws {
        let turmeric = ExtractedIngredient(
            ingredient: "turmeric",
            originalPhrase: "haldi andaza se",
            amount: nil,
            unit: nil,
            vague: true
        )
        let extracted = ExtractedRecipe(
            title: "Chicken Karahi",
            attribution: "Mom",
            ingredients: [turmeric],
            steps: ["Add chicken and haldi"],
            notes: nil
        )
        let data = try JSONEncoder().encode(extracted)
        let json = try #require(String(data: data, encoding: .utf8))
        let recipe = Recipe(
            title: "Chicken Karahi",
            rawTranscript: "Beta listen, put in haldi andaza se",
            extractedJSON: json,
            attribution: "Mom",
            sourceKind: .transcript
        )
        #expect(recipe.sourceKindValue == .transcript)
        #expect(recipe.sourceKindValue.publishesToFamilyBook)
        #expect(json.contains("haldi andaza se"))
        let decoded = try JSONDecoder().decode(ExtractedRecipe.self, from: Data(json.utf8))
        #expect(decoded.ingredients.first?.originalPhrase == "haldi andaza se")
    }

    @Test func urlRecipeDoesNotPublishToFamilyBook() {
        let recipe = Recipe(
            title: "YouTube Karahi",
            rawTranscript: "https://www.youtube.com/watch?v=example",
            extractedJSON: nil,
            attribution: "youtube.com",
            sourceKind: .url
        )
        #expect(recipe.sourceKindValue == .url)
        #expect(!recipe.sourceKindValue.publishesToFamilyBook)
    }

    @Test func publicCardKeysNeverIncludeRawTranscript() {
        #expect(!FamilyRecipeBookCard.publicFieldKeys.contains("raw_transcript"))
        #expect(FamilyRecipeBookCard.publicFieldKeys.contains("ingredient_phrases"))
        #expect(FamilyRecipeBookCard.publicFieldKeys.contains("added_by_label"))
    }

    @Test func captureSaveSetsSourceKindFromExtractPath() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let capture = try String(
            contentsOf: repoRoot.appendingPathComponent("Saman/Features/Recipes/RecipeCaptureView.swift"),
            encoding: .utf8
        )
        #expect(capture.contains("capturedSourceKind = .url"))
        #expect(capture.contains("capturedSourceKind = .transcript"))
        #expect(capture.contains("sourceKind: capturedSourceKind"))
    }

    @Test func migrationKeepsOwnerRLSAndPublishesCardNotRawRow() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let migration = try String(
            contentsOf: repoRoot.appendingPathComponent("supabase/migrations/008_recipe_book.sql"),
            encoding: .utf8
        )
        #expect(migration.contains("recipe_book_cards"))
        #expect(migration.contains("raw_transcript never appears on the card") || migration.contains("raw_transcript never"))
        #expect(migration.contains("source_kind"))
        #expect(migration.contains("recipe_book_notes"))
        #expect(migration.contains("for select to authenticated"))
        #expect(!migration.contains("drop policy if exists \"owner\" on recipes"))
    }
}
