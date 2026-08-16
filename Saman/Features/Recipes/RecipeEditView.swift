import SwiftUI
import SwiftData

/// Post-extraction editor: title, source, ingredients, steps, and notes.
/// Edits are re-serialized into `recipe.extractedJSON` so the detail view and
/// the shopping-list push read the same corrected data.
struct RecipeEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let recipe: Recipe

    @State private var title: String
    @State private var source: String
    @State private var ingredients: [EditableIngredient]
    @State private var steps: [EditableStep]
    @State private var notes: String

    struct EditableIngredient: Identifiable {
        let id = UUID()
        var name: String
        var amountText: String
        var unit: String
        var originalPhrase: String
    }

    struct EditableStep: Identifiable {
        let id = UUID()
        var text: String
    }

    init(recipe: Recipe) {
        self.recipe = recipe
        let parsed: ExtractedRecipe? = {
            guard let json = recipe.extractedJSON,
                  let data = json.data(using: .utf8)
            else { return nil }
            return try? JSONDecoder().decode(ExtractedRecipe.self, from: data)
        }()
        _title = State(initialValue: recipe.title)
        _source = State(initialValue: recipe.attribution ?? parsed?.attribution ?? "")
        _ingredients = State(initialValue: (parsed?.ingredients ?? []).map {
            EditableIngredient(
                name: $0.ingredient,
                amountText: Self.amountText($0.amount),
                unit: $0.unit ?? "",
                originalPhrase: $0.originalPhrase
            )
        })
        _steps = State(initialValue: (parsed?.steps ?? []).map { EditableStep(text: $0) })
        _notes = State(initialValue: parsed?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    TextField("Title", text: $title)
                    TextField("From — e.g. Mom", text: $source)
                }

                Section {
                    ForEach($ingredients) { $ing in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Ingredient", text: $ing.name)
                            HStack(spacing: 8) {
                                TextField("Amount", text: $ing.amountText)
                                    .keyboardType(.numbersAndPunctuation)
                                    .frame(maxWidth: 90)
                                    .foregroundStyle(Self.isInvalidAmount(ing.amountText) ? Color.accentAnaar : Color.inkKohlSoft)
                                TextField("Unit (cup, tsp…)", text: $ing.unit)
                            }
                            .font(.system(size: 14))
                            .foregroundStyle(Color.inkKohlSoft)
                            if !ing.originalPhrase.isEmpty && ing.originalPhrase != ing.name {
                                Text(ing.originalPhrase)
                                    .font(.system(size: 12).italic())
                                    .foregroundStyle(Color.inkKohlSoft)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }
                    .onMove { ingredients.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        ingredients.append(EditableIngredient(name: "", amountText: "", unit: "", originalPhrase: ""))
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.brandSaag)
                    }
                } header: {
                    Text("Ingredients")
                } footer: {
                    if hasInvalidAmounts {
                        Text("Check the amounts marked in red — use numbers like 2, 0.5, or 1/2.")
                            .foregroundStyle(Color.accentAnaar)
                    } else {
                        Text("Swipe left to remove. Fractions like 1/2 are fine. Leave the amount empty for andaza — “to taste”.")
                    }
                }

                Section {
                    ForEach($steps) { $step in
                        TextField("Step", text: $step.text, axis: .vertical)
                            .lineLimit(1...6)
                    }
                    .onDelete { steps.remove(atOffsets: $0) }
                    .onMove { steps.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        steps.append(EditableStep(text: ""))
                    } label: {
                        Label("Add Step", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.brandSaag)
                    }
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Tap Edit to reorder ingredients and steps.")
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...6)
                }
            }
            .navigationTitle("Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    EditButton()
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasInvalidAmounts)
                }
            }
        }
    }

    // MARK: - Amount parsing

    /// Accepts decimals ("0.5", "0,5"), fractions ("1/2"), and mixed numbers
    /// ("1 1/2"). Returns nil when the text can't be read as a quantity.
    static func parseAmount(_ raw: String) -> Double? {
        let text = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty else { return nil }
        var total = 0.0
        for part in text.split(separator: " ") {
            if let d = Double(part) {
                total += d
            } else {
                let frac = part.split(separator: "/")
                guard frac.count == 2,
                      let num = Double(frac[0]),
                      let den = Double(frac[1]),
                      den != 0
                else { return nil }
                total += num / den
            }
        }
        return total
    }

    static func isInvalidAmount(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && parseAmount(trimmed) == nil
    }

    private var hasInvalidAmounts: Bool {
        ingredients.contains { Self.isInvalidAmount($0.amountText) }
    }

    // MARK: - Save

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !hasInvalidAmounts else { return }

        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let attribution = trimmedSource.isEmpty ? nil : trimmedSource

        let outIngredients: [ExtractedIngredient] = ingredients.compactMap { row in
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let amount = Self.parseAmount(row.amountText)
            let unit = row.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let phrase = row.originalPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            return ExtractedIngredient(
                ingredient: name,
                originalPhrase: phrase.isEmpty ? name : phrase,
                amount: amount,
                unit: unit.isEmpty ? nil : unit,
                vague: amount == nil
            )
        }
        let outSteps = steps
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        recipe.title = trimmedTitle
        recipe.attribution = attribution

        // Don't fabricate an empty structure for transcript-only recipes — the
        // detail view falls back to showing the raw transcript when JSON is nil.
        let hasContent = !outIngredients.isEmpty || !outSteps.isEmpty || !trimmedNotes.isEmpty
        if recipe.extractedJSON != nil || hasContent {
            let out = ExtractedRecipe(
                title: trimmedTitle,
                attribution: attribution,
                ingredients: outIngredients,
                steps: outSteps,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            if let data = try? JSONEncoder().encode(out),
               let json = String(data: data, encoding: .utf8) {
                recipe.extractedJSON = json
            }
        }

        recipe.isDirty = true
        try? context.save()
        dismiss()
    }

    private static func amountText(_ amount: Double?) -> String {
        guard let a = amount else { return "" }
        return a.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(a)) : String(a)
    }
}

#Preview {
    RecipeEditView(recipe: Recipe(
        title: "Chicken Karahi",
        rawTranscript: "Beta listen, chicken karahi bahut easy hai…",
        extractedJSON: #"{"title":"Chicken Karahi","attribution":"Mom","ingredients":[{"ingredient":"chicken","original_phrase":"ek kilo chicken","amount":1,"unit":"kg","vague":false},{"ingredient":"turmeric","original_phrase":"haldi andaza se","amount":null,"unit":null,"vague":true}],"steps":["Fry the onions until golden.","Add the chicken."],"notes":null}"#
    ))
    .modelContainer(.preview)
}
