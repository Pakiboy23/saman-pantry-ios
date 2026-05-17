import SwiftUI
import SwiftData

struct PantryListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv) private var appEnv
    @Query(sort: \Item.name) private var allItems: [Item]
    @Query(sort: \Pantry.name) private var pantries: [Pantry]
    @State private var selectedLocation = "pantry"
    @State private var showAdd = false
    @State private var showPaywall = false
    @State private var showManage = false
    @State private var showAddPantry = false
    @State private var showPantryPaywall = false

    private let locationTabs: [(id: String, label: String)] = [
        ("pantry",  "Pantry"),
        ("fridge",  "Fridge"),
        ("freezer", "Freezer"),
    ]

    // MARK: - Derived

    private var lowCount: Int { allItems.filter(\.isLow).count }

    private var filteredItems: [Item] {
        allItems.filter { item in
            guard let pantryName = item.pantry?.name.lowercased() else { return false }
            return pantryName.contains(selectedLocation)
        }
    }

    private var lowFiltered:     [Item] { filteredItems.filter(\.isLow) }
    private var stockedFiltered: [Item] { filteredItems.filter { !$0.isLow } }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Running low
                    if !lowFiltered.isEmpty {
                        SamanSectionHeader(title: "Running low", color: .accentAnaar)
                        ForEach(lowFiltered) { item in
                            NavigationLink(destination: ItemDetailView(item: item)) {
                                ItemCard(item: item)
                                    .padding(.horizontal, Saman.Space.md)
                                    .padding(.top, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Well stocked
                    if !stockedFiltered.isEmpty {
                        SamanSectionHeader(title: "Well stocked", color: .brandSaag)
                        ForEach(stockedFiltered) { item in
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
                            emoji: locationTabs.first(where: { $0.id == selectedLocation })
                                .map { tabEmoji($0.id) } ?? "📦",
                            title: "Nothing in \(selectedLocation.capitalized)",
                            message: "Items assigned to a \(selectedLocation.capitalized) pantry will appear here."
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
            .sheet(isPresented: $showAddPantry) { AddPantryView() }
            .sheet(isPresented: $showPantryPaywall) { SamanPaywallView() }
            .sheet(isPresented: $showManage) { managePantriesSheet }
        }
    }

    // MARK: - Top header

    private var topHeader: some View {
        VStack(spacing: 0) {
            // Title row
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saman")
                        .font(.pantryDisplay)
                        .foregroundStyle(Color.inkKohl)
                    Text("Storage locations")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.inkKohlSoft)
                }
                Spacer()
                Button {
                    if allItems.count >= 30 && !appEnv.purchases.isPro {
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

            // Low stock banner
            if lowCount > 0 {
                LowStockBanner(count: lowCount)
                    .padding(.bottom, 8)
            }

            // Pantry / Fridge / Freezer tabs
            PillTabBar(tabs: locationTabs, selection: $selectedLocation)

            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.borderAkhrotSoft.opacity(0.5))
                .padding(.top, 4)
        }
        .background(Color.surfaceDoodh)
    }

    // MARK: - Manage pantries sheet

    private var managePantriesSheet: some View {
        NavigationStack {
            List {
                ForEach(pantries) { pantry in
                    HStack(spacing: 10) {
                        Image(systemName: "cabinet")
                            .foregroundStyle(Color.brandSaag)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pantry.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.inkKohl)
                            Text("\(pantry.items.count) item\(pantry.items.count == 1 ? "" : "s")")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.inkKohlSoft)
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Manage Pantries")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { showManage = false }
                        .foregroundStyle(Color.brandSaag)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton().foregroundStyle(Color.brandSaag)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showManage = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            if pantries.count >= 1 && !appEnv.purchases.isPro {
                                showPantryPaywall = true
                            } else {
                                showAddPantry = true
                            }
                        }
                    } label: {
                        Label("New Pantry", systemImage: "plus")
                            .foregroundStyle(Color.brandSaag)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func tabEmoji(_ id: String) -> String {
        switch id {
        case "fridge":  return "🧊"
        case "freezer": return "❄️"
        default:        return "🗄️"
        }
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(pantries[i]) }
        try? context.save()
        appEnv.syncNow()
    }
}

// MARK: - Pantry detail (items filtered to this pantry)

struct PantryDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv) private var appEnv
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Item.name) private var allItems: [Item]
    @Bindable var pantry: Pantry
    @State private var showAdd = false
    @State private var showPaywall = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                let sorted = pantry.items.sorted { $0.name < $1.name }
                let lowItems     = sorted.filter(\.isLow)
                let stockedItems = sorted.filter { !$0.isLow }

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

                if sorted.isEmpty {
                    SamanEmptyState(
                        emoji: "🗄️",
                        title: "Empty pantry",
                        message: "Tap + to add your first item to \(pantry.name)."
                    )
                }

                Spacer(minLength: 32)
            }
        }
        .background(Color.surfaceDoodh)
        .scrollContentBackground(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.brandSaag)
                    }
                    Text(pantry.name)
                        .font(.pantrySectionHead)
                        .foregroundStyle(Color.inkKohl)
                    Spacer()
                    Button {
                        if allItems.count >= 30 && !appEnv.purchases.isPro {
                            showPaywall = true
                        } else {
                            showAdd = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.surfaceDoodh)
                            .frame(width: 32, height: 32)
                            .background(Color.brandSaag, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, Saman.Space.md)
                .padding(.vertical, 12)
                Rectangle().frame(height: 1).foregroundStyle(Color.borderAkhrotSoft.opacity(0.5))
            }
            .background(Color.surfaceDoodh)
        }
        .sheet(isPresented: $showAdd) {
            AddItemView(defaultPantry: pantry)
        }
        .sheet(isPresented: $showPaywall) { SamanPaywallView() }
    }
}
