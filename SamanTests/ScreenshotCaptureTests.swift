import Foundation
import SwiftData
import Testing
@testable import Saman

struct ScreenshotLaunchConfigurationTests {
    @Test func uiTestingFlagSkipsAuthAndSeedsKitchen() {
        let config = ScreenshotLaunchConfiguration.parse(
            arguments: ["/app", "-UITesting"],
            environment: [:]
        )
        #expect(config.isUITesting)
        #expect(config.skipsAuth)
        #expect(config.shouldSeedDemoKitchen)
        #expect(config.usesInMemoryStore)
        #expect(config.scene == nil)
    }

    @Test func screenshotSeedWithoutUITestingStillSeedsButDoesNotSkipAuth() {
        let config = ScreenshotLaunchConfiguration.parse(
            arguments: ["/app", "-ScreenshotSeed"],
            environment: [:]
        )
        #expect(!config.isUITesting)
        #expect(!config.skipsAuth)
        #expect(config.shouldSeedDemoKitchen)
        #expect(config.usesInMemoryStore)
    }

    @Test func xcodeUITestEnvAloneDoesNotSkipAuth() {
        let config = ScreenshotLaunchConfiguration.parse(
            arguments: ["/app"],
            environment: ["XCODE_RUNNING_FOR_UI_TESTING": "1"]
        )
        #expect(!config.isUITesting)
        #expect(!config.skipsAuth)
        #expect(!config.shouldSeedDemoKitchen)
    }

    @Test func parsesKnownScenes() {
        let scenes: [(String, ScreenshotLaunchConfiguration.Scene)] = [
            ("home", .home),
            ("pantry", .pantry),
            ("recipeReview", .recipeReview),
            ("shoppingList", .shoppingList),
            ("paywall", .paywall),
        ]
        for (raw, expected) in scenes {
            let config = ScreenshotLaunchConfiguration.parse(
                arguments: ["/app", "-UITesting", "-ScreenshotScene", raw],
                environment: [:]
            )
            #expect(config.scene == expected)
        }
    }

    @Test func unknownSceneIsNil() {
        let config = ScreenshotLaunchConfiguration.parse(
            arguments: ["/app", "-ScreenshotScene", "marketingCollage"],
            environment: [:]
        )
        #expect(config.scene == nil)
    }

    @Test func missingSceneValueIsNil() {
        let config = ScreenshotLaunchConfiguration.parse(
            arguments: ["/app", "-ScreenshotScene"],
            environment: [:]
        )
        #expect(config.scene == nil)
    }

    @Test func productionLaunchIsUnchanged() {
        let config = ScreenshotLaunchConfiguration.parse(
            arguments: ["/var/containers/Bundle/Application/Saman.app/Saman"],
            environment: [:]
        )
        #expect(!config.isUITesting)
        #expect(!config.skipsAuth)
        #expect(!config.shouldSeedDemoKitchen)
        #expect(!config.usesInMemoryStore)
        #expect(config.scene == nil)
    }
}

@MainActor
struct ScreenshotDemoKitchenTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Item.self,
            Pantry.self,
            Product.self,
            Store.self,
            ShoppingList.self,
            ShoppingListItem.self,
            Recipe.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    @Test func seedMatchesAppStoreShotList() throws {
        let container = try makeContainer()
        let context = container.mainContext

        ScreenshotDemoKitchen.seed(into: context)

        let items = try context.fetch(FetchDescriptor<Item>())
        let atta = items.first { $0.name == "Atta" }
        let haldi = items.first { $0.name == "Haldi" }
        #expect(atta != nil)
        #expect(haldi != nil)
        #expect(atta?.quantity == 0)
        #expect(atta?.stockStatus == .out)
        #expect(haldi?.quantity == 1)
        #expect(haldi?.minimumQuantity == 2)
        #expect(haldi?.stockStatus == .low)
        #expect(items.contains { $0.name == "Basmati Rice" && !$0.stockStatus.isAttention })

        let lists = try context.fetch(FetchDescriptor<ShoppingList>())
        let list = lists.first { $0.name == ScreenshotDemoKitchen.shoppingListName }
        #expect(list != nil)
        #expect(list?.isCompleted == false)
        let purchased = list?.items.filter(\.isPurchased) ?? []
        let pending = list?.items.filter { !$0.isPurchased } ?? []
        #expect(purchased.count >= 2)
        #expect(pending.count >= 2)

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let karahi = recipes.first { $0.title == ScreenshotDemoKitchen.recipeTitle }
        #expect(karahi != nil)
        #expect(karahi?.attribution == "Ammi")

        let data = try #require(karahi?.extractedJSON?.data(using: .utf8))
        let extracted = try JSONDecoder().decode(ExtractedRecipe.self, from: data)
        let turmeric = extracted.ingredients.first { $0.ingredient.lowercased() == "turmeric" }
        #expect(turmeric != nil)
        #expect(turmeric?.originalPhrase == "haldi — andaza se")
        #expect(turmeric?.vague == true)
    }

    @Test func seedIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        ScreenshotDemoKitchen.seed(into: context)
        ScreenshotDemoKitchen.seed(into: context)

        let items = try context.fetch(FetchDescriptor<Item>())
        #expect(items.filter { $0.name == "Haldi" }.count == 1)
        let lists = try context.fetch(FetchDescriptor<ShoppingList>())
        #expect(lists.filter { $0.name == ScreenshotDemoKitchen.shoppingListName }.count == 1)
    }

    @Test func cannedReviewPreservesAndazaSeNextToTurmeric() {
        let review = ScreenshotDemoKitchen.chickenKarahiReview
        let turmeric = review.ingredients.first { $0.ingredient.lowercased() == "turmeric" }
        #expect(turmeric?.originalPhrase == "haldi — andaza se")
        #expect(review.title == ScreenshotDemoKitchen.recipeTitle)
    }
}
