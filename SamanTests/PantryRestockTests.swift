import Foundation
import SwiftData
import Testing
@testable import Saman

@MainActor
struct PantryRestockTests {
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

    @Test func markBoughtRestocksHaldiFromTurmericListRow() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let pantry = Pantry(name: "Kitchen")
        let haldi = Item(name: "Haldi", quantity: 1, unit: "unit", minimumQuantity: 2, pantry: pantry)
        context.insert(pantry)
        context.insert(haldi)
        try context.save()

        let list = ShoppingList(name: "Chicken Karahi")
        context.insert(list)
        PantryProductLink.appendIngredients(
            [
                ExtractedIngredient(
                    ingredient: "turmeric",
                    originalPhrase: "haldi — andaza se",
                    amount: 2,
                    unit: "tsp",
                    vague: false
                )
            ],
            to: list,
            in: context
        )
        try context.save()

        let rows = try context.fetch(FetchDescriptor<ShoppingListItem>())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.product?.name == "turmeric")
        #expect(haldi.product?.id == row.product?.id)
        #expect(row.quantity == 2)

        PantryRestock.apply(items: [haldi], for: row, by: row.quantity)
        #expect(haldi.quantity == 3)
    }

    @Test func markBoughtFallsBackToExactNameWhenProductIsUnlinked() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let haldi = Item(name: "Haldi", quantity: 1, unit: "unit")
        let product = Product(name: "haldi")
        let list = ShoppingList(name: "Shop")
        let row = ShoppingListItem(quantity: 1, unit: "unit", product: product, shoppingList: list)
        context.insert(haldi)
        context.insert(product)
        context.insert(list)
        context.insert(row)
        try context.save()

        PantryRestock.apply(items: [haldi], for: row, by: row.quantity)
        #expect(haldi.quantity == 2)
        #expect(haldi.product == nil)
    }

    @Test(arguments: [
        (Double(Int.max), 1),
        (Double(Int.min).nextDown, 1),
        (Double.greatestFiniteMagnitude, 1),
        (Double.infinity, 1),
        (Double.nan, 1),
        (0.5, 1),
        (1.5, 2),
        (2.0, 2),
    ])
    func ingredientQuantitiesCanBeAddedToList(amount: Double, expected: Int) throws {
        let container = try makeContainer()
        let context = container.mainContext
        let list = ShoppingList(name: "Rice")
        context.insert(list)
        PantryProductLink.appendIngredients([
            ExtractedIngredient(
                ingredient: "rice", originalPhrase: "rice", amount: amount, unit: "kg", vague: false
            ),
        ], to: list, in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<ShoppingListItem>())
        #expect(rows.count == 1)
        #expect(rows.first?.quantity == expected)
    }
}
