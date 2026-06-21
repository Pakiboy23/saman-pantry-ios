import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv)       private var appEnv
    @Bindable var recipe: Recipe

    @State private var extracted: ExtractedRecipe? = nil
    @State private var showAddedBanner = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBlock
                    .padding(.bottom, 20)

                if let ex = extracted {
                    ingredientsSection(ex.ingredients)
                    if !ex.steps.isEmpty     { stepsSection(ex.steps) }
                    if let notes = ex.notes  { notesSection(notes) }
                } else {
                    transcriptFallback
                }

                addToListButton
                    .padding(.top, 28)
                    .padding(.bottom, 48)
            }
            .padding(.horizontal, Saman.Space.md)
            .padding(.top, 12)
        }
        .background(Color.surfaceDoodh)
        .scrollContentBackground(.hidden)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { parseExtracted() }
        .overlay(alignment: .top) {
            if showAddedBanner {
                addedBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.35), value: showAddedBanner)
    }

    // MARK: - Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Recipe title", text: $recipe.title, axis: .vertical)
                .font(.custom("CormorantGaramond-Bold", size: 36))
                .foregroundStyle(Color.inkKohl)
                .textFieldStyle(.plain)
                .lineLimit(3)

            HStack(spacing: 8) {
                if let attr = extracted?.attribution {
                    Text(attr)
                        .font(.system(size: 13).italic())
                        .foregroundStyle(Color.inkKohlSoft)
                }
                Text(recipe.createdAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkKohlSoft)
            }

            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.borderAkhrotSoft.opacity(0.5))
                .padding(.top, 8)
        }
    }

    // MARK: - Ingredients

    private func ingredientsSection(_ ingredients: [ExtractedIngredient]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Ingredients · \(ingredients.count)")
            VStack(spacing: 0) {
                ForEach(Array(ingredients.enumerated()), id: \.offset) { _, ing in
                    IngredientDetailRow(ingredient: ing)
                    if ing.ingredient != ingredients.last?.ingredient {
                        Divider().overlay(Color.borderAkhrotSoft.opacity(0.3))
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Steps

    private func stepsSection(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("How to make it")
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(i + 1)")
                            .font(.samanMono(12))
                            .foregroundStyle(Color.brandSaag)
                            .frame(width: 20, alignment: .trailing)
                            .padding(.top, 2)
                        Text(step)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.inkKohl)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Notes

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Notes")
            Text(notes)
                .font(.system(size: 14).italic())
                .foregroundStyle(Color.inkKohl)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Fallback (no JSON stored — pre-detail-view captures)

    private var transcriptFallback: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Original transcript")
            Text(recipe.rawTranscript)
                .font(.system(size: 14))
                .foregroundStyle(Color.inkKohl)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Add to list

    private var addToListButton: some View {
        Button("Add to shopping list") { Task { await pushToList() } }
            .buttonStyle(SamanPrimaryButtonStyle())
            .disabled(extracted == nil)
    }

    private var addedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.brandSaag)
            Text("Added to shopping list")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.inkKohl)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.surfaceMalai, in: Capsule())
        .overlay(Capsule().stroke(Color.borderAkhrotSoft.opacity(0.5), lineWidth: 1))
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.samanMono(10))
            .foregroundStyle(Color.inkKohlSoft)
            .kerning(0.8)
            .padding(.bottom, 10)
            .padding(.top, 4)
    }

    private func parseExtracted() {
        guard let json = recipe.extractedJSON,
              let data = json.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(ExtractedRecipe.self, from: data)
        else { return }
        extracted = parsed
    }

    private func pushToList() async {
        guard let ex = extracted else { return }
        let list = ShoppingList(name: recipe.title)
        context.insert(list)
        for ing in ex.ingredients {
            let product = Product(name: ing.ingredient)
            context.insert(product)
            let qty  = max(1, Int((ing.amount ?? 1.0).rounded(.up)))
            let unit = ing.unit ?? "unit"
            let item = ShoppingListItem(quantity: qty, unit: unit, product: product, shoppingList: list)
            context.insert(item)
        }
        try? context.save()
        appEnv.syncNow()
        withAnimation { showAddedBanner = true }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        withAnimation { showAddedBanner = false }
    }
}

// MARK: - Ingredient row (read-only)

private struct IngredientDetailRow: View {
    let ingredient: ExtractedIngredient

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(ingredient.ingredient)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.inkKohl)
                Spacer()
                Text(ingredient.amountLabel)
                    .font(.samanMono(13))
                    .foregroundStyle(ingredient.vague ? Color.inkKohlSoft : Color.brandSaag)
            }
            Text(ingredient.originalPhrase)
                .font(.system(size: 12).italic())
                .foregroundStyle(Color.inkKohlSoft)
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: Recipe(
            title: "Chicken Karahi",
            rawTranscript: "Beta listen, chicken karahi bahut easy hai…"
        ))
        .environment(\.appEnv, AppEnvironment(modelContainer: .preview))
        .modelContainer(.preview)
    }
}
