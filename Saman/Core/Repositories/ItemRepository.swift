import Foundation
import SwiftData

struct ItemRepository {

    func fetchAll(in pantry: Pantry?, context: ModelContext) throws -> [Item] {
        let all = try context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\.name)]))
        guard let pantry else { return all }
        return all.filter { $0.pantry?.id == pantry.id }
    }

    func fetchLowStock(context: ModelContext) throws -> [Item] {
        try context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\.name)]))
            .filter(\.isLow)
    }

    func add(_ item: Item, context: ModelContext) {
        item.markDirty()
        context.insert(item)
    }

    func delete(_ item: Item, context: ModelContext) {
        context.delete(item)
    }
}
