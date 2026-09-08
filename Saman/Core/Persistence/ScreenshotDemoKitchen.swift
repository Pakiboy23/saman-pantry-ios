import Foundation
import SwiftData

/// A canned desi kitchen that matches `docs/launch/app-store-metadata.md`'s
/// screenshot shot-list. Used only when `-UITesting` / `-ScreenshotSeed` is set.
enum ScreenshotDemoKitchen {
    static let shoppingListName = "Patel Brothers"
    static let recipeTitle = "Chicken Karahi"

    static let karahiTranscript = """
    Beta listen, chicken karahi bahut easy hai. Ek kilo chicken, char tamatar, \
    adrak lehsun. Haldi — andaza se. Thora sa laal mirch, garam masala last mein. \
    Ammi's way, don't measure the haldi.
    """

    static let chickenKarahiReview = ExtractedRecipe(
        title: recipeTitle,
        attribution: "Ammi",
        ingredients: [
            ExtractedIngredient(
                ingredient: "chicken",
                originalPhrase: "ek kilo chicken",
                amount: 1,
                unit: "kg",
                vague: false
            ),
            ExtractedIngredient(
                ingredient: "turmeric",
                originalPhrase: "haldi — andaza se",
                amount: nil,
                unit: nil,
                vague: true
            ),
            ExtractedIngredient(
                ingredient: "tomatoes",
                originalPhrase: "char tamatar",
                amount: 4,
                unit: "unit",
                vague: false
            ),
            ExtractedIngredient(
                ingredient: "ginger-garlic paste",
                originalPhrase: "adrak lehsun",
                amount: nil,
                unit: nil,
                vague: true
            ),
            ExtractedIngredient(
                ingredient: "red chili",
                originalPhrase: "thora sa laal mirch",
                amount: nil,
                unit: nil,
                vague: true
            ),
            ExtractedIngredient(
                ingredient: "garam masala",
                originalPhrase: "garam masala last mein",
                amount: nil,
                unit: nil,
                vague: true
            ),
        ],
        steps: [
            "Heat ghee, brown the chicken.",
            "Add tamatar and adrak lehsun, cook until the oil returns.",
            "Haldi — andaza se. Finish with garam masala.",
        ],
        notes: "Don't invent a number Ammi didn't say."
    )

    private static let pantryStock: [(name: String, unit: String, quantity: Int, minimum: Int)] = [
        ("Atta", "kg", 0, 1),
        ("Haldi", "unit", 1, 2),
        ("Onions", "unit", 1, 2),
        ("Basmati Rice", "kg", 5, 1),
        ("Toor Dal", "kg", 2, 1),
        ("Ghee", "unit", 3, 1),
        ("Jeera", "unit", 2, 1),
        ("Chai Patti", "unit", 2, 1),
        ("Ginger", "unit", 4, 1),
        ("Laal Mirch", "unit", 2, 1),
    ]

    @MainActor
    static func seed(into context: ModelContext) {
        let existingItems = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        if existingItems.contains(where: { $0.name == "Haldi" }) {
            return
        }

        for staple in pantryStock {
            context.insert(Item(
                name: staple.name,
                quantity: staple.quantity,
                unit: staple.unit,
                minimumQuantity: staple.minimum
            ))
        }

        let list = ShoppingList(name: shoppingListName)
        context.insert(list)
        insertListItem(name: "Atta", quantity: 1, unit: "kg", purchased: false, list: list, context: context)
        insertListItem(name: "Haldi", quantity: 1, unit: "unit", purchased: false, list: list, context: context)
        insertListItem(name: "Paneer", quantity: 1, unit: "unit", purchased: false, list: list, context: context)
        insertListItem(name: "Dhaniya Powder", quantity: 1, unit: "unit", purchased: true, list: list, context: context)
        insertListItem(name: "Ginger", quantity: 1, unit: "unit", purchased: true, list: list, context: context)

        var extractedJSON = ""
        if let data = try? JSONEncoder().encode(chickenKarahiReview),
           let json = String(data: data, encoding: .utf8) {
            extractedJSON = json
        }
        context.insert(Recipe(
            title: recipeTitle,
            rawTranscript: karahiTranscript,
            extractedJSON: extractedJSON,
            attribution: "Ammi"
        ))

        try? context.save()
    }

    @MainActor
    private static func insertListItem(
        name: String,
        quantity: Int,
        unit: String,
        purchased: Bool,
        list: ShoppingList,
        context: ModelContext
    ) {
        let product = Product(name: name)
        context.insert(product)
        let item = ShoppingListItem(
            quantity: quantity,
            unit: unit,
            isPurchased: purchased,
            product: product,
            shoppingList: list
        )
        context.insert(item)
    }
}
