import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv) private var appEnv
    @Query(sort: \Item.name) private var items: [Item]
    @State private var showAdd = false
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var pendingDeleteItem: Item?
    @State private var openSwipeID: UUID?

    // MARK: - Derived

    private var lowItems:     [Item] { items.filter { $0.stockStatus.isAttention } }
    private var stockedItems: [Item] { items.filter { !$0.stockStatus.isAttention } }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    if !lowItems.isEmpty {
                        SamaanSectionHeader(title: "Running low", color: .accentAnaar)
                        ForEach(lowItems) { item in
                            SamaanSwipeToDelete(id: item.id, openID: $openSwipeID) {
                                pendingDeleteItem = item
                            } content: {
                                NavigationLink(destination: ItemDetailView(item: item)) {
                                    ItemCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, Samaan.Space.md)
                            .padding(.top, 8)
                            .contextMenu {
                                Button(role: .destructive) { pendingDeleteItem = item } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    if !stockedItems.isEmpty {
                        SamaanSectionHeader(title: "Well stocked", color: .brandSaag)
                        ForEach(stockedItems) { item in
                            SamaanSwipeToDelete(id: item.id, openID: $openSwipeID) {
                                pendingDeleteItem = item
                            } content: {
                                NavigationLink(destination: ItemDetailView(item: item)) {
                                    ItemCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, Samaan.Space.md)
                            .padding(.top, 8)
                            .contextMenu {
                                Button(role: .destructive) { pendingDeleteItem = item } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    if items.isEmpty {
                        VStack(spacing: 16) {
                            SamaanEmptyState(
                                emoji: "🛒",
                                title: "Nothing here yet",
                                message: "Tap + to add your first item."
                            )
                            Button("Add desi staples") {
                                DesiStaples.seed(into: context) { appEnv.syncNow() }
                            }
                            .buttonStyle(SamaanSecondaryButtonStyle())
                            .padding(.horizontal, Samaan.Space.md)
                        }
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Color.surfaceDoodh)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("screenshot.pantry")
            .safeAreaInset(edge: .top, spacing: 0) {
                topHeader
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAdd) { AddItemView() }
            .sheet(isPresented: $showPaywall) { SamaanPaywallView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .confirmationDialog(
                "Delete \(pendingDeleteItem?.name ?? "item")?",
                isPresented: Binding(
                    get: { pendingDeleteItem != nil },
                    set: { if !$0 { pendingDeleteItem = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeleteItem
            ) { item in
                Button("Delete", role: .destructive) {
                    appEnv.deleteRecord(item, table: "items", id: item.id)
                    pendingDeleteItem = nil
                }
                Button("Cancel", role: .cancel) { pendingDeleteItem = nil }
            }
        }
    }

    // MARK: - Sticky top header

    private var topHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Samaan")
                        .font(.pantryDisplay)
                        .foregroundStyle(Color.inkKohl)
                    Text(greetingSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.inkKohlSoft)
                }
                Spacer()
                // Settings
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.inkKohlSoft)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Settings")
                // Add item
                Button {
                    if FreeLimits.canAddPantryItem(existingCount: items.count, isPro: appEnv.purchases.isPro) {
                        showAdd = true
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.surfaceDoodh)
                        .frame(width: 36, height: 36)
                        .background(Color.brandSaag, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, Samaan.Space.md)
            .padding(.vertical, 12)

            if !lowItems.isEmpty {
                LowStockBanner(count: lowItems.count)
                    .padding(.bottom, 8)
            }

            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.borderAkhrotSoft.opacity(0.5))
                .padding(.top, 4)
        }
        .background(Color.surfaceDoodh)
    }

    private var greetingSubtitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }
}

#Preview { InventoryView().modelContainer(.preview) }
