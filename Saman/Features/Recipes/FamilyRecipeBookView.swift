import SwiftUI

/// Signed-in readers browse the public Community book, newest first.
/// A recipe shows up only after its cook shares it.
struct FamilyRecipeBookView: View {
    @Environment(\.appEnv) private var appEnv
    @State private var cards: [FamilyRecipeBookCard] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if !appEnv.auth.isSignedIn {
                signInPrompt
            } else if isLoading && cards.isEmpty {
                ProgressView()
                    .tint(Color.brandSaag)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, cards.isEmpty {
                errorState(errorMessage)
            } else if cards.isEmpty {
                emptyState
            } else {
                cardList
            }
        }
        .background(Color.surfaceDoodh)
        .task(id: appEnv.auth.isSignedIn) {
            guard appEnv.auth.isSignedIn else {
                cards = []
                return
            }
            await reload()
        }
        .fullScreenCover(isPresented: Binding(
            get: { appEnv.isAuthPresented },
            set: { appEnv.isAuthPresented = $0 }
        )) {
            AuthView()
        }
        .heycatchScreen("Family Recipe Book")
    }

    private var signInPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Community")
                .font(.cormorant(size: 28))
                .foregroundStyle(Color.inkKohl)
            Text("Sign in to read recipes other cooks have shared.")
                .font(.system(size: 14))
                .foregroundStyle(Color.inkKohlSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Sign in") { appEnv.requireAccount() }
                .buttonStyle(SamaanPrimaryButtonStyle())
                .padding(.horizontal, Samaan.Space.md)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("No shared recipes yet")
                .font(.cormorant(size: 28))
                .foregroundStyle(Color.inkKohl)
            Text("Recipes show up here when a cook shares one to Community. Yours stay private until you do.")
                .font(.system(size: 14))
                .foregroundStyle(Color.inkKohlSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.inkKohl)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") { Task { await reload() } }
                .buttonStyle(SamaanPrimaryButtonStyle())
                .padding(.horizontal, Samaan.Space.md)
            Spacer()
        }
    }

    private var cardList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(cards) { card in
                    NavigationLink(destination: FamilyRecipeCardDetailView(card: card)) {
                        FamilyRecipeBookRow(card: card)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Samaan.Space.md)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable { await reload() }
    }

    private func reload() async {
        guard appEnv.auth.isSignedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            cards = try await FamilyRecipeBookService.shared.fetchCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FamilyRecipeBookRow: View {
    let card: FamilyRecipeBookCard

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
                Text(card.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.inkKohl)
                HStack(spacing: 4) {
                    if card.sourceLink != nil {
                        Text("link")
                        Text("·")
                    }
                    if let attribution = card.attribution, !attribution.isEmpty {
                        Text("from \(attribution)")
                            .italic()
                        Text("·")
                    }
                    Text("added by \(card.addedByLabel)")
                    Text("·")
                    Text(card.createdAt, format: .dateTime.day().month(.abbreviated).year())
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
