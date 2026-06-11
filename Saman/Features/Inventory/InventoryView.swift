import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv) private var appEnv
    @Query(sort: \Item.name) private var items: [Item]
    @Query(sort: \Pantry.name) private var pantries: [Pantry]
    @State private var showAdd = false
    @State private var showPaywall = false
    @State private var showScanner = false
    @State private var showSettings = false
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

    private var lowItems:     [Item] { filteredItems.filter { $0.stockStatus.isAttention } }
    private var stockedItems: [Item] { filteredItems.filter { !$0.stockStatus.isAttention } }
    private var allLowCount:  Int    { items.filter { $0.stockStatus.isAttention }.count }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    if !lowItems.isEmpty {
                        SamanSectionHeader(title: "Running low", color: .accentAnaar)
                        ForEach(lowItems) { item in
                            NavigationLink(destination: ItemDetailView(item: item)) {
                                ItemCard(item: item)
                                    .padding(.horizontal, Saman.Space.md)
                                    .padding(.top, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !stockedItems.isEmpty {
                        SamanSectionHeader(title: "Well stocked", color: .brandSaag)
                        ForEach(stockedItems) { item in
                            NavigationLink(destination: ItemDetailView(item: item)) {
                                ItemCard(item: item)
                                    .padding(.horizontal, Saman.Space.md)
                                    .padding(.top, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }

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
            .background(Color.surfaceDoodh)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                topHeader
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAdd) { AddItemView() }
            .sheet(isPresented: $showPaywall) { SamanPaywallView() }
            .sheet(isPresented: $showScanner) { ScannerView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    // MARK: - Sticky top header

    private var topHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saman")
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
                // Scanner
                Button { showScanner = true } label: {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.inkKohl)
                        .frame(width: 36, height: 36)
                }
                // Add item
                Button {
                    if items.count >= 30 && !appEnv.purchases.isPro {
                        showPaywall = true
                    } else {
                        showAdd = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.surfaceDoodh)
                        .frame(width: 36, height: 36)
                        .background(Color.brandSaag, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, Saman.Space.md)
            .padding(.vertical, 12)

            if allLowCount > 0 {
                LowStockBanner(count: allLowCount)
                    .padding(.bottom, 8)
            }

            if tabs.count > 1 {
                PillTabBar(tabs: tabs, selection: $selectedTab)
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
