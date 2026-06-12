import SwiftUI
import SwiftData

struct RecipesView: View {
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var showCapture = false

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    emptyState
                } else {
                    recipeList
                }
            }
            .background(Color.samanBg)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    SamanHeader(
                        subtitle: recipes.isEmpty
                            ? "Capture a family recipe"
                            : "\(recipes.count) recipe\(recipes.count == 1 ? "" : "s") saved"
                    ) { showCapture = true }
                    Rectangle().frame(height: 1).foregroundStyle(Color.samanBorder)
                }
                .background(Color.samanBg)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCapture) { RecipeCaptureView() }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Text("نسخہ")
                    .font(.custom("NotoNastaliqUrdu-Regular", size: 52))
                    .foregroundStyle(Color.samanAccent)
                VStack(spacing: 8) {
                    Text("Capture a recipe")
                        .font(.cormorant(30))
                        .foregroundStyle(Color.samanPrimary)
                    Text("Paste a spoken recipe — code-switched,\nandaza and all.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.samanMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.bottom, 32)
            Button("Capture a Recipe") { showCapture = true }
                .buttonStyle(SamanPrimaryButtonStyle())
                .padding(.horizontal, Saman.Space.md)
            Spacer()
        }
    }

    // MARK: - Recipe list

    private var recipeList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(recipes) { recipe in
                    NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                        RecipeRow(recipe: recipe)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Saman.Space.md)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Row

private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.samanAccentLight)
                    .frame(width: 46, height: 46)
                Text("🍲")
                    .font(.system(size: 22))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.samanPrimary)
                Text(recipe.createdAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(.system(size: 12))
                    .foregroundStyle(Color.samanMuted)
            }
            Spacer()
        }
        .padding(14)
        .samanCard()
    }
}

#Preview { RecipesView().modelContainer(.preview) }
