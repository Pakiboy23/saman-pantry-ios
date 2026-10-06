import Foundation
import Testing
@testable import Saman

struct IngredientQuantityTests {
    @Test func decodedOversizedQuantityCanBeDisplayed() throws {
        let json = #"{"ingredient":"rice","original_phrase":"9223372036854775808 kg rice","amount":9223372036854775808,"unit":"kg","vague":false}"#
        let ingredient = try JSONDecoder().decode(ExtractedIngredient.self, from: Data(json.utf8))

        #expect(ingredient.amount == Double(Int.max))
        #expect(ingredient.amountLabel == "9.223372036854776e+18 kg")
        #expect(ingredient.originalPhrase == "9223372036854775808 kg rice")
    }

    @Test(arguments: [
        (0.0, "0 kg"),
        (2.0, "2 kg"),
        (0.5, "0.5 kg"),
        (Double(Int.max).nextDown, "9223372036854774784 kg"),
        (Double(Int.max), "9.223372036854776e+18 kg"),
        (Double(Int.min), "-9223372036854775808 kg"),
        (Double(Int.min).nextDown, "-9.223372036854778e+18 kg"),
        (Double.greatestFiniteMagnitude, "1.7976931348623157e+308 kg"),
        (-Double.greatestFiniteMagnitude, "-1.7976931348623157e+308 kg"),
    ])
    func quantityLabelsRemainSafe(amount: Double, expected: String) {
        let ingredient = ExtractedIngredient(
            ingredient: "rice", originalPhrase: "rice", amount: amount, unit: "kg", vague: false
        )
        #expect(ingredient.amountLabel == expected)
    }

    @Test func missingQuantityOrUnitKeepsPlaceholder() {
        let noAmount = ExtractedIngredient(
            ingredient: "salt", originalPhrase: "to taste", amount: nil, unit: "tsp", vague: true
        )
        let noUnit = ExtractedIngredient(
            ingredient: "onion", originalPhrase: "2 onions", amount: 2, unit: nil, vague: false
        )
        #expect(noAmount.amountLabel == "—")
        #expect(noUnit.amountLabel == "—")
    }

    @MainActor
    @Test func savedOversizedQuantityCanBeOpenedForEditing() throws {
        let extracted = ExtractedRecipe(
            title: "Rice", ingredients: [
                ExtractedIngredient(
                    ingredient: "rice", originalPhrase: "9223372036854775808 kg rice",
                    amount: Double(Int.max), unit: "kg", vague: false
                ),
            ], steps: ["Cook rice."]
        )
        let json = String(decoding: try JSONEncoder().encode(extracted), as: UTF8.self)
        let recipe = Recipe(title: "Rice", rawTranscript: "", extractedJSON: json)

        // Initialization formats the stored quantity for the editable text field.
        _ = RecipeEditView(recipe: recipe)
    }
}
