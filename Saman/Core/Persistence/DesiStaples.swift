import SwiftData

/// A one-tap starter pack of common South Asian kitchen staples, inserted at
/// quantity 0 so they immediately surface under "Running low" as things to buy.
/// This is the highest-leverage fix for the empty-pantry cold start: typing
/// 20 items by hand before the app does anything useful is where pantry apps
/// get abandoned.
enum DesiStaples {

    /// name + a sensible default unit. quantity defaults to 0, minimum to 1,
    /// so every seeded item reads as `.out` until the user stocks it.
    static let items: [(name: String, unit: String)] = [
        ("Atta", "kg"),
        ("Basmati Rice", "kg"),
        ("Toor Dal", "kg"),
        ("Masoor Dal", "kg"),
        ("Chana Dal", "kg"),
        ("Ghee", "unit"),
        ("Cooking Oil", "L"),
        ("Haldi", "unit"),
        ("Jeera", "unit"),
        ("Dhaniya Powder", "unit"),
        ("Laal Mirch", "unit"),
        ("Garam Masala", "unit"),
        ("Salt", "unit"),
        ("Sugar", "kg"),
        ("Chai Patti", "unit"),
        ("Black Pepper", "unit"),
        ("Paneer", "unit"),
        ("Onions", "unit"),
        ("Garlic", "unit"),
        ("Ginger", "unit"),
    ]

    /// Insert the starter pack into the given context, then trigger a sync.
    @MainActor
    static func seed(into context: ModelContext, then sync: () -> Void) {
        for staple in items {
            context.insert(Item(name: staple.name, quantity: 0, unit: staple.unit, minimumQuantity: 1))
        }
        try? context.save()
        sync()
    }
}
