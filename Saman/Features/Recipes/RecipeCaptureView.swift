import SwiftUI
import SwiftData

struct RecipeCaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv)       private var appEnv
    @Environment(\.dismiss)      private var dismiss

    @State private var transcript   = ""
    @State private var recipeTitle  = ""
    @State private var selections:  [IngredientSelection] = []
    @State private var phase:       Phase = .idle
    @State private var showError    = false
    @State private var errorMessage = ""

    enum Phase { case idle, extracting, reviewing, adding, done }

    struct IngredientSelection: Identifiable {
        let id         = UUID()
        var ingredient: ExtractedIngredient
        var isSelected  = true
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.samanBg.ignoresSafeArea()
                switch phase {
                case .idle:                idleContent
                case .extracting, .adding: loadingContent
                case .reviewing:           reviewContent
                case .done:                doneContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(navTitle)
                        .font(.cormorant(20))
                        .foregroundStyle(Color.samanPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    if phase != .done {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(Color.samanAccent)
                    }
                }
            }
            .alert("Extraction failed", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var navTitle: String {
        switch phase {
        case .idle:       return "Capture Recipe"
        case .extracting: return "Reading…"
        case .reviewing:  return "Review"
        case .adding:     return "Saving…"
        case .done:       return "Done"
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Paste the recipe transcript below.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.samanPrimary)
                Text("Code-switched Urdu/Hindi/Punjabi and vague\nmeasurements are fine — even expected.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.samanMuted)
            }
            .padding(.horizontal, Saman.Space.md)
            .padding(.top, Saman.Space.md)
            .padding(.bottom, 12)

            ZStack(alignment: .topLeading) {
                if transcript.isEmpty {
                    Text("Beta listen, chicken karahi bahut easy hai…")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.samanMuted.opacity(0.55))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $transcript)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.samanPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
            }
            .frame(minHeight: 220)
            .background(Color.samanCard, in: RoundedRectangle(cornerRadius: Saman.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Saman.Radius.md).stroke(Color.samanBorder, lineWidth: 1))
            .padding(.horizontal, Saman.Space.md)

            Spacer()

            Button("Extract Recipe") { Task { await runExtraction() } }
                .buttonStyle(SamanPrimaryButtonStyle())
                .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, Saman.Space.md)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Loading

    private var loadingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.samanAccent)
                .scaleEffect(1.3)
            Text(phase == .adding ? "Saving to your list…" : "Reading the recipe…")
                .font(.system(size: 14))
                .foregroundStyle(Color.samanMuted)
        }
    }

    // MARK: - Review

    private var reviewContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {

                // Editable title
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECIPE TITLE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.samanMuted)
                        .kerning(0.8)
                    TextField("Recipe title", text: $recipeTitle)
                        .font(.cormorant(26))
                        .foregroundStyle(Color.samanPrimary)
                        .textFieldStyle(.plain)
                }
                .padding(Saman.Space.md)
                .samanCard()
                .padding(.horizontal, Saman.Space.md)
                .padding(.top, Saman.Space.md)

                SamanSectionHeader(
                    title: "\(selections.filter(\.isSelected).count) of \(selections.count) selected",
                    color: .samanAccent
                )

                ForEach($selections) { $sel in
                    IngredientRow(selection: $sel)
                        .padding(.horizontal, Saman.Space.md)
                        .padding(.bottom, 6)
                }

                Spacer(minLength: 100)
            }
        }
        .overlay(alignment: .bottom) {
            addButton
        }
    }

    private var addButton: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.samanBg.opacity(0), Color.samanBg],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 40)
            .allowsHitTesting(false)

            Button("Add to Shopping List") { Task { await pushToList() } }
                .buttonStyle(SamanPrimaryButtonStyle())
                .disabled(selections.filter(\.isSelected).isEmpty)
                .padding(.horizontal, Saman.Space.md)
                .padding(.bottom, 32)
                .background(Color.samanBg)
        }
    }

    // MARK: - Done

    private var doneContent: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.samanGreen.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.samanGreen)
                }
                VStack(spacing: 6) {
                    Text("Ingredients saved")
                        .font(.cormorant(26))
                        .foregroundStyle(Color.samanPrimary)
                    Text("\"\(recipeTitle)\" added to your shopping list.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.samanMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(SamanPrimaryButtonStyle())
                .padding(.horizontal, Saman.Space.md)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Actions

    private func runExtraction() async {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        phase = .extracting
        do {
            let result = try await RecipeExtractionService.shared.extract(transcript: text)
            recipeTitle = result.title
            selections  = result.ingredients.map { IngredientSelection(ingredient: $0) }
            phase = .reviewing
        } catch {
            errorMessage = error.localizedDescription
            showError    = true
            phase        = .idle
        }
    }

    private func pushToList() async {
        let chosen = selections.filter(\.isSelected)
        guard !chosen.isEmpty else { return }
        phase = .adding

        let list = ShoppingList(name: recipeTitle)
        context.insert(list)

        for sel in chosen {
            let ing     = sel.ingredient
            let product = Product(name: ing.ingredient)
            context.insert(product)
            let qty  = max(1, Int((ing.amount ?? 1.0).rounded(.up)))
            let unit = ing.unit ?? "unit"
            let item = ShoppingListItem(quantity: qty, unit: unit, product: product, shoppingList: list)
            context.insert(item)
        }

        let recipe = Recipe(title: recipeTitle, rawTranscript: transcript)
        context.insert(recipe)

        try? context.save()
        appEnv.syncNow()
        phase = .done
    }
}

// MARK: - Ingredient row

private struct IngredientRow: View {
    @Binding var selection: RecipeCaptureView.IngredientSelection

    var body: some View {
        let ing = selection.ingredient
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selection.isSelected.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selection.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selection.isSelected ? Color.samanAccent : Color.samanMuted.opacity(0.4))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ing.ingredient)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.samanPrimary)
                        Spacer()
                        Text(ing.amountLabel)
                            .font(.samanMono(13))
                            .foregroundStyle(ing.vague ? Color.samanMuted : Color.samanAccent)
                    }
                    Text(ing.originalPhrase)
                        .font(.system(size: 12))
                        .italic()
                        .foregroundStyle(Color.samanMuted)
                }
            }
            .padding(12)
            .samanCard()
            .opacity(selection.isSelected ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RecipeCaptureView()
        .environment(\.appEnv, AppEnvironment(modelContainer: .preview))
        .modelContainer(.preview)
}
