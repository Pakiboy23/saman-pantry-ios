import SwiftUI
import SwiftData

struct RecipesView: View {
    private enum Shelf: String, CaseIterable, Identifiable {
        case yours = "Yours"
        case familyBook = "Family book"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.appEnv) private var appEnv
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var shelf: Shelf = .yours
    @State private var showCapture = false
    @State private var recipePrompt: RecipePrompt?
    @State private var familyBookAuth = FamilyBookAuthIntent()
    @State private var showFamilyBookAuth = false
    @State private var familyBookError: String?
    @State private var isUpdatingFamilyBook = false
    @State private var openSwipeID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                switch shelf {
                case .yours:
                    if recipes.isEmpty {
                        emptyState
                    } else {
                        recipeList
                    }
                case .familyBook:
                    FamilyRecipeBookView()
                }
            }
            .background(Color.surfaceDoodh)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    SamaanHeader(
                        subtitle: headerSubtitle
                    ) { showCapture = true }
                    Picker("Recipes shelf", selection: $shelf) {
                        ForEach(Shelf.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Samaan.Space.md)
                    .padding(.bottom, 10)
                    Rectangle().frame(height: 1).foregroundStyle(Color.borderAkhrotSoft.opacity(0.5))
                }
                .background(Color.surfaceDoodh)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCapture) { RecipeCaptureView() }
            .fullScreenCover(isPresented: $showFamilyBookAuth, onDismiss: {
                guard let recipeID = familyBookAuth.resolve(signedIn: appEnv.auth.isSignedIn) else { return }
                Task { @MainActor in
                    guard let recipe = recipes.first(where: { $0.id == recipeID }) else { return }
                    presentFamilyBookPrompt(for: recipe)
                }
            }) {
                AuthView()
            }
            .confirmationDialog(
                recipePrompt?.title ?? "",
                isPresented: Binding(
                    get: { recipePrompt != nil },
                    set: { if !$0 { recipePrompt = nil } }
                ),
                titleVisibility: .visible,
                presenting: recipePrompt
            ) { prompt in
                switch prompt {
                case .delete(let recipe):
                    Button("Delete", role: .destructive) {
                        appEnv.deleteRecord(recipe, table: "recipes", id: recipe.id)
                        recipePrompt = nil
                    }
                case .addToFamilyBook(let recipe):
                    Button(FamilyBookShareCopy.addAction) {
                        Task { await commitFamilyBookShare(true, recipe: recipe) }
                    }
                    .disabled(isUpdatingFamilyBook)
                case .removeFromFamilyBook(let recipe):
                    Button(FamilyBookShareCopy.removeAction) {
                        Task { await commitFamilyBookShare(false, recipe: recipe) }
                    }
                    .disabled(isUpdatingFamilyBook)
                }
                Button("Cancel", role: .cancel) { recipePrompt = nil }
            } message: { prompt in
                if let message = prompt.message {
                    Text(message)
                }
            }
            .alert(FamilyBookShareCopy.uploadFailedTitle, isPresented: Binding(
                get: { familyBookError != nil },
                set: { if !$0 { familyBookError = nil } }
            )) {
                Button("OK") { familyBookError = nil }
            } message: {
                Text(familyBookError ?? "")
            }
        }
    }

    private var headerSubtitle: String {
        switch shelf {
        case .yours:
            return recipes.isEmpty
                ? "Capture a family recipe"
                : "\(recipes.count) recipe\(recipes.count == 1 ? "" : "s") saved"
        case .familyBook:
            return "Transcripts and links a cook shared"
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Text("نسخہ")
                    .font(.custom("NotoNastaliqUrdu-Regular", size: 52))
                    .foregroundStyle(Color.brandSaag)
                VStack(spacing: 8) {
                    Text("Capture a recipe")
                        .font(.cormorant(size: 30))
                        .foregroundStyle(Color.inkKohl)
                    Text("Record it, paste a link, or paste the words. Code-switched,\nandaza and all.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.inkKohlSoft)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.bottom, 32)
            Button("Capture a Recipe") { showCapture = true }
                .buttonStyle(SamaanPrimaryButtonStyle())
                .padding(.horizontal, Samaan.Space.md)
            Spacer()
        }
    }

    // MARK: - Recipe list

    private var recipeList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(recipes) { recipe in
                    SamaanSwipeToDelete(id: recipe.id, openID: $openSwipeID) {
                        recipePrompt = .delete(recipe)
                    } content: {
                        NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                            RecipeRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                    .contextMenu {
                        if recipe.sourceKindValue == .url {
                            Button {
                                requestFamilyBookChange(for: recipe)
                            } label: {
                                Label(
                                    recipe.shareInFamilyBook
                                        ? FamilyBookShareCopy.removeAction
                                        : FamilyBookShareCopy.addAction,
                                    systemImage: recipe.shareInFamilyBook ? "book.closed" : "book"
                                )
                            }
                        }
                        Button(role: .destructive) { recipePrompt = .delete(recipe) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .padding(.horizontal, Samaan.Space.md)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    private func requestFamilyBookChange(for recipe: Recipe) {
        guard recipe.sourceKindValue == .url else { return }
        guard appEnv.auth.isSignedIn else {
            familyBookAuth.remember(recipe.id)
            showFamilyBookAuth = true
            return
        }
        presentFamilyBookPrompt(for: recipe)
    }

    private func presentFamilyBookPrompt(for recipe: Recipe) {
        recipePrompt = recipe.shareInFamilyBook
            ? .removeFromFamilyBook(recipe)
            : .addToFamilyBook(recipe)
    }

    private func commitFamilyBookShare(_ share: Bool, recipe: Recipe) async {
        guard !isUpdatingFamilyBook else { return }
        isUpdatingFamilyBook = true
        defer { isUpdatingFamilyBook = false }
        recipePrompt = nil
        do {
            try await FamilyBookShareCommit.send(share, recipe: recipe, context: context, sync: appEnv.syncManager)
        } catch {
            familyBookError = error.localizedDescription
        }
    }
}

private enum RecipePrompt: Identifiable {
    case delete(Recipe)
    case addToFamilyBook(Recipe)
    case removeFromFamilyBook(Recipe)

    var id: String {
        switch self {
        case .delete(let recipe):
            return "delete-\(recipe.id.uuidString)"
        case .addToFamilyBook(let recipe):
            return "add-\(recipe.id.uuidString)"
        case .removeFromFamilyBook(let recipe):
            return "remove-\(recipe.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .delete(let recipe):
            return "Delete \(recipe.title)?"
        case .addToFamilyBook:
            return FamilyBookShareCopy.addTitle
        case .removeFromFamilyBook:
            return FamilyBookShareCopy.removeTitle
        }
    }

    var message: String? {
        switch self {
        case .delete:
            return nil
        case .addToFamilyBook:
            return FamilyBookShareCopy.addMessage
        case .removeFromFamilyBook:
            return FamilyBookShareCopy.removeMessage
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
                    .fill(Color.brandSaagSoft.opacity(0.3))
                    .frame(width: 46, height: 46)
                Text("🍲")
                    .font(.system(size: 22))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.inkKohl)
                HStack(spacing: 4) {
                    Text(recipe.myBookStatusLabel)
                    Text("·")
                    if let attribution = recipe.attribution {
                        Text("from \(attribution)")
                            .italic()
                        Text("·")
                    }
                    Text(recipe.createdAt, format: .dateTime.day().month(.abbreviated).year())
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.inkKohlSoft)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .samaanCard()
    }
}

#Preview { RecipesView().modelContainer(.preview) }
