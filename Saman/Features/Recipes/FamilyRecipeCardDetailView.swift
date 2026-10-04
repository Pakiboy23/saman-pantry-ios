import SwiftUI
import SwiftData

/// Read-only family book card. Shows title, steps, original phrases,
/// attribution, and who added it. Never shows raw_transcript.
/// Readers may add a note or push ingredients onto their own list.
struct FamilyRecipeCardDetailView: View {
    @Environment(\.appEnv) private var appEnv
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let card: FamilyRecipeBookCard

    @State private var notes: [FamilyRecipeBookNote] = []
    @State private var draftNote = ""
    @State private var showAddedBanner = false
    @State private var errorMessage: String?
    @State private var isSavingNote = false
    @State private var showRemoveConfirm = false

    private var isOwner: Bool {
        guard let me = appEnv.auth.currentUserID else { return false }
        return me.caseInsensitiveCompare(card.ownerId.uuidString) == .orderedSame
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBlock
                    .padding(.bottom, 20)

                if !card.ingredientPhrases.isEmpty {
                    phrasesSection
                }
                if !card.steps.isEmpty {
                    stepsSection
                }

                notesSection
                    .padding(.top, 8)

                Button("Add missing ingredients to my list") {
                    addIngredientsToMyList()
                }
                .buttonStyle(SamaanPrimaryButtonStyle())
                .disabled(card.ingredientPhrases.isEmpty)
                .padding(.top, 28)
                .padding(.bottom, 48)
            }
            .padding(.horizontal, Samaan.Space.md)
            .padding(.top, 12)
        }
        .background(Color.surfaceDoodh)
        .scrollContentBackground(.hidden)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) { showRemoveConfirm = true } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Remove from family book")
                }
            }
        }
        .confirmationDialog(
            "Remove \(card.title) from the family book?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { removeOwnCard() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes your saved recipe too. Other people will no longer see the card.")
        }
        .task { await loadNotes() }
        .overlay(alignment: .top) {
            if showAddedBanner {
                banner("Added to your shopping list")
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.35), value: showAddedBanner)
        .alert("Couldn't save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.custom("CormorantGaramond-Bold", size: 36))
                .foregroundStyle(Color.inkKohl)
                .lineLimit(3)

            HStack(spacing: 8) {
                if let attr = card.attribution, !attr.isEmpty {
                    Text("from \(attr)")
                        .font(.system(size: 13).italic())
                        .foregroundStyle(Color.brandSaag)
                }
                Text("added by \(card.addedByLabel)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkKohlSoft)
                Text(card.createdAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkKohlSoft)
            }

            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.borderAkhrotSoft.opacity(0.5))
                .padding(.top, 8)
        }
    }

    private var phrasesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Ingredients · \(card.ingredientPhrases.count)")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(card.ingredientPhrases.enumerated()), id: \.offset) { _, phrase in
                    Text(phrase)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.inkKohl)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("How to make it")
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(card.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(i + 1)")
                            .font(.samaanMono(12))
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

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Notes")
            if notes.isEmpty {
                Text("No notes yet. Add one without changing the steps.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkKohlSoft)
                    .padding(.bottom, 12)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(notes) { note in
                        Text(note.body)
                            .font(.system(size: 14).italic())
                            .foregroundStyle(Color.inkKohl)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 4)
                    }
                }
                .padding(.bottom, 12)
            }

            HStack(alignment: .top, spacing: 10) {
                TextField("Add a note", text: $draftNote, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.inkKohl)
                    .lineLimit(3...6)
                    .padding(10)
                    .background(Color.surfaceMalai, in: RoundedRectangle(cornerRadius: Samaan.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Samaan.Radius.md)
                            .stroke(Color.borderAkhrotSoft.opacity(0.5), lineWidth: 1)
                    )
                Button {
                    Task { await saveNote() }
                } label: {
                    Text(isSavingNote ? "…" : "Add")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.brandSaag)
                        .frame(minWidth: 44)
                }
                .disabled(isSavingNote || draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.bottom, 8)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.samaanMono(10))
            .foregroundStyle(Color.inkKohlSoft)
            .kerning(0.8)
            .padding(.bottom, 10)
            .padding(.top, 4)
    }

    private func banner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.brandSaag)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.inkKohl)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.surfaceMalai, in: Capsule())
        .overlay(Capsule().stroke(Color.borderAkhrotSoft.opacity(0.5), lineWidth: 1))
    }

    private func loadNotes() async {
        do {
            notes = try await FamilyRecipeBookService.shared.fetchNotes(cardId: card.id)
        } catch {
            // Keep the card readable even if notes fail.
            notes = []
        }
    }

    private func saveNote() async {
        let body = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSavingNote = true
        defer { isSavingNote = false }
        do {
            let note = try await FamilyRecipeBookService.shared.addNote(cardId: card.id, body: body)
            notes.append(note)
            draftNote = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Writes only this reader's shopping list. Never mutates the owner's data.
    private func addIngredientsToMyList() {
        let list = ShoppingList(name: card.title)
        context.insert(list)
        let ingredients = card.ingredientPhrases.map {
            ExtractedIngredient(
                ingredient: $0,
                originalPhrase: $0,
                amount: nil,
                unit: nil,
                vague: true
            )
        }
        PantryProductLink.appendIngredients(ingredients, to: list, in: context)
        try? context.save()
        appEnv.syncNow()
        withAnimation { showAddedBanner = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { withAnimation { showAddedBanner = false } }
        }
    }

    /// Owner remove deletes the underlying recipe (and the card via cascade).
    private func removeOwnCard() {
        let cardId = card.id
        let descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { $0.id == cardId }
        )
        if let recipe = try? context.fetch(descriptor).first {
            appEnv.deleteRecord(recipe, table: "recipes", id: recipe.id)
        } else {
            // Recipe may not be on this device. Tombstone the server row so the
            // card trigger can drop it for everyone.
            appEnv.syncManager.queueTombstone(table: "recipes", id: card.id)
            appEnv.syncNow()
        }
        dismiss()
    }
}
