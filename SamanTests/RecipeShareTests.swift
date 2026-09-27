import Foundation
import Testing
@testable import Saman

struct RecipeShareTests {
    @Test func shareTextIncludesRecipeAndAppStoreLine() {
        let chicken = ExtractedIngredient(
            ingredient: "chicken",
            originalPhrase: "1 kg chicken",
            amount: 1,
            unit: "kg",
            vague: false
        )
        let turmeric = ExtractedIngredient(
            ingredient: "turmeric",
            originalPhrase: "haldi andaza se",
            amount: nil,
            unit: nil,
            vague: true
        )
        let text = RecipeShareText.format(
            title: "Chicken Karahi",
            attribution: "Mom",
            ingredients: [chicken, turmeric],
            steps: ["Heat the oil"],
            notes: "Rest it",
            transcript: "ignored when the recipe is structured"
        )

        #expect(text.contains("Chicken Karahi"))
        #expect(text.contains("from Mom"))
        #expect(text.contains("• chicken — 1 kg"))
        #expect(text.contains("haldi andaza se"))
        #expect(text.contains("1. Heat the oil"))
        #expect(text.contains("Rest it"))
        #expect(text.contains(RecipeShareText.footerTitle))
        #expect(text.contains("https://apps.apple.com/us/app/id6761982454"))
        #expect(!text.contains("ignored when the recipe is structured"))
    }

    @Test func shareTextFallsBackToTranscript() {
        let text = RecipeShareText.format(
            title: "Phone recipe",
            attribution: nil,
            ingredients: [],
            steps: [],
            notes: nil,
            transcript: "beta listen, chicken karahi"
        )
        #expect(text.contains("beta listen, chicken karahi"))
        #expect(text.hasSuffix("https://apps.apple.com/us/app/id6761982454"))
    }
}

struct RecipeLinkInputTests {
    @Test func normalizesBareYouTubeAndRejectsProse() {
        #expect(RecipeLinkInput.normalized("https://youtu.be/dQw4w9WgXcQ") == "https://youtu.be/dQw4w9WgXcQ")
        #expect(RecipeLinkInput.normalized("  youtu.be/dQw4w9WgXcQ  ") == "https://youtu.be/dQw4w9WgXcQ")
        #expect(RecipeLinkInput.normalized("www.seriouseats.com/chicken-karahi") == "https://www.seriouseats.com/chicken-karahi")
        #expect(RecipeLinkInput.normalized("haldi and pyaaz") == nil)
        #expect(RecipeLinkInput.normalized("https://example.com/a and more") == nil)
        #expect(RecipeLinkInput.hostLabel("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "youtube.com")
    }
}
