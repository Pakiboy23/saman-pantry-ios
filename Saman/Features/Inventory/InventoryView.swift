import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.name) private var items: [Item]
    @Query(sort: \Pantry.name) private var pantries: [Pantry]
    @State private var showAdd = false
    @State private var selectedTab = "all"

    // MARK: - Derived

    private var tabs: [(id: String, label: String)] {
        [("all", "All")] + pantries.map { ($0.id.uuidString, $0.name) }
    }

    private var filteredItems: [Item] {
        guard selectedTab != "all",
              let id = UUID(uuidString: selectedTab) else { return items }
        return items.filter { $0.pantry?.id == id }
    }

    private var lowItems:     [Item] { filteredItems.filter(\.isLow) }
    private var stockedItems: [Item] { filteredItems.filter { !$0.isLow } }
    private var allLowCount:  Int    { items.filter(\.isLow).count }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    // Running low section
                    if !lowItems.isEmpty {
                        SamanSectionHeader(title: "Running low", color: .samanRed)
                        ForEach(lowItems) { item in
                            NavigationLink(destination: ItemDetailView(item: item)) {
                                ItemCard(item: item)
                                    .padding(.horizontal, Saman.Space.md)
                                    .padding(.top, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Well stocked section
                    if !stockedItems.isEmpty {
                        SamanSectionHeader(title: "Well stocked", color: .samanGreen)
                        ForEach(stockedItems) { item in
                            NavigationLink(destination: ItemDetailView(item: item)) {
                                ItemCard(item: item)
                                    .padding(.horizontal, Saman.Space.md)
                                    .padding(.top, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Empty state
                    if filteredItems.isEmpty {
                        SamanEmptyState(
                            emoji: "🛒",
                            title: "Nothing here yet",
                            message: "Tap + to add your first item, or scan a barcode."
                        )
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Color.samanBg)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                topHeader
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAdd) { AddItemView() }
        }
    }

    // MARK: - Sticky top header

    private var topHeader: some View {
        VStack(spacing: 0) {
            SamanHeader(subtitle: greetingSubtitle) { showAdd = true }

            if allLowCount > 0 {
                LowStockBanner(count: allLowCount)
                    .padding(.bottom, 8)
            }

            if tabs.count > 1 {
                PillTabBar(tabs: tabs, selection: $selectedTab)
            }

            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.samanBorder)
                .padding(.top, 4)
        }
        .background(Color.samanBg)
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
