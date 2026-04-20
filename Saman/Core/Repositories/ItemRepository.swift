import Foundation
import SwiftData

/// Abstracts CRUD for `Item` so features stay testable without touching SwiftData directly.
protocol ItemRepositoryProtocol {
    func fetchAll(in pantry: Pantry?) throws -> [Item]
    func fetchLowStock() throws -> [Item]
    func add(_ item: Item, context: ModelContext)
    func delete(_ item: Item, context: ModelContext)
}

struct ItemRepository: ItemRepositoryProtocol {

    func fetchAll(in pantry: Pantry?) throws -> [Item] {
        fatalError("Inject ModelContext before use — call fetchAll(in:context:)")
    }

    func fetchAll(in pantry: Pantry?, context: ModelContext) throws -> [Item] {
        let all = try context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\.name)]))
        guard let pantry else { return all }
        return all.filter { $0.pantry?.id == pantry.id }
    }

    func fetchLowStock(context: ModelContext) throws -> [Item] {
        try context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\.name)]))
            .filter(\.isLow)
    }

    func fetchLowStock() throws -> [Item] { [] }

    func add(_ item: Item, context: ModelContext) {
        item.markDirty()
        context.insert(item)
    }

    func delete(_ item: Item, context: ModelContext) {
        context.delete(item)
    }
}
