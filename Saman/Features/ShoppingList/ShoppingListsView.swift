import SwiftUI
import SwiftData

struct ShoppingListsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv) private var appEnv
    @Query(sort: \ShoppingList.createdAt, order: .reverse) private var lists: [ShoppingList]
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(lists) { list in
                        NavigationLink(destination: ShoppingListDetailView(list: list)) {
                            ShoppingListCard(list: list)
                        }
                        .buttonStyle(.plain)
                    }

                    if lists.isEmpty {
                        SamanEmptyState(
                            emoji: "📋",
                            title: "No shopping lists",
                            message: "Tap + to create your first list."
                        )
                    }
                }
                .padding(.horizontal, Saman.Space.md)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.samanBg)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    SamanHeader(subtitle: listSubtitle) { showAdd = true }
                    Rectangle().frame(height: 1).foregroundStyle(Color.samanBorder)
                }
                .background(Color.samanBg)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAdd) { AddShoppingListView() }
        }
    }

    private var listSubtitle: String {
        lists.isEmpty ? "Plan your next shop" : "\(lists.count) list\(lists.count == 1 ? "" : "s")"
    }
}

// MARK: - List card

private struct ShoppingListCard: View {
    let list: ShoppingList

    var body: some View {
        HStack(spacing: 14) {
            // Status icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(list.isCompleted ? Color.samanGreen.opacity(0.15) : Color.samanAccentLight)
                    .frame(width: 46, height: 46)
                Image(systemName: list.isCompleted ? "checkmark.circle.fill" : "cart")
                    .font(.system(size: 20))
                    .foregroundStyle(list.isCompleted ? Color.samanGreen : Color.samanAccent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(list.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(list.isCompleted ? Color.samanMuted : Color.samanPrimary)
                    .strikethrough(list.isCompleted)
                HStack(spacing: 4) {
                    if let store = list.store {
                        Text(store.name)
                        Text("·")
                    }
                    Text(list.isCompleted ? "Completed" : "\(list.pendingCount) item\(list.pendingCount == 1 ? "" : "s") left")
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.samanMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.samanMuted.opacity(0.6))
        }
        .padding(14)
        .samanCard()
    }
}

#Preview { ShoppingListsView().modelContainer(.preview) }
