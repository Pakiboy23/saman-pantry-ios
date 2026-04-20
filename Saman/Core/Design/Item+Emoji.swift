import Foundation

extension Item {
    /// Best-guess emoji based on item name and product category.
    var emoji: String {
        let n = name.lowercased()
        let cat = product?.category?.lowercased() ?? ""

        // Name-based matches
        let nameLookup: [(String, String)] = [
            ("milk", "🥛"), ("cream", "🥛"), ("yogurt", "🫙"), ("yoghurt", "🫙"),
            ("egg", "🥚"), ("bread", "🍞"), ("toast", "🍞"), ("bagel", "🥯"),
            ("butter", "🧈"), ("cheese", "🧀"),
            ("apple", "🍎"), ("banana", "🍌"), ("orange", "🍊"), ("lemon", "🍋"),
            ("grape", "🍇"), ("strawberr", "🍓"), ("berry", "🫐"), ("avocado", "🥑"),
            ("tomato", "🍅"), ("carrot", "🥕"), ("broccoli", "🥦"), ("onion", "🧅"),
            ("garlic", "🧄"), ("potato", "🥔"), ("pepper", "🌶️"), ("cucumber", "🥒"),
            ("lettuce", "🥬"), ("spinach", "🥬"), ("corn", "🌽"),
            ("chicken", "🍗"), ("beef", "🥩"), ("pork", "🥩"), ("lamb", "🥩"),
            ("meat", "🥩"), ("steak", "🥩"), ("sausage", "🌭"), ("bacon", "🥓"),
            ("fish", "🐟"), ("salmon", "🐟"), ("tuna", "🐟"), ("shrimp", "🍤"),
            ("rice", "🍚"), ("pasta", "🍝"), ("noodle", "🍜"), ("spaghetti", "🍝"),
            ("flour", "🌾"), ("oat", "🌾"), ("cereal", "🥣"), ("granola", "🥣"),
            ("coffee", "☕️"), ("espresso", "☕️"), ("tea", "🍵"),
            ("juice", "🧃"), ("water", "💧"), ("soda", "🥤"), ("wine", "🍷"),
            ("beer", "🍺"), ("kombucha", "🍶"),
            ("sugar", "🍬"), ("honey", "🍯"), ("jam", "🍓"), ("syrup", "🍁"),
            ("salt", "🧂"), ("pepper", "🧂"), ("spice", "🌶️"), ("herb", "🌿"),
            ("oil", "🫙"), ("vinegar", "🫙"), ("sauce", "🫙"), ("ketchup", "🍅"),
            ("mustard", "🌭"), ("mayo", "🫙"), ("dressing", "🫙"),
            ("chocolate", "🍫"), ("candy", "🍬"), ("cookie", "🍪"), ("cake", "🎂"),
            ("chip", "🍟"), ("cracker", "🍘"), ("nut", "🥜"), ("almond", "🥜"),
            ("peanut", "🥜"), ("cashew", "🥜"),
            ("soap", "🧼"), ("shampoo", "🧴"), ("detergent", "🧼"), ("cleaner", "🫧"),
            ("paper", "🧻"), ("tissue", "🧻"), ("towel", "🧻"),
            ("toothpaste", "🪥"), ("toothbrush", "🪥"),
            ("diaper", "👶"), ("baby", "👶"),
            ("dog", "🐕"), ("cat", "🐈"), ("pet", "🐾"),
        ]

        for (keyword, emoji) in nameLookup {
            if n.contains(keyword) { return emoji }
        }

        // Category fallback
        if cat.contains("dairy") { return "🥛" }
        if cat.contains("meat") || cat.contains("poultry") { return "🥩" }
        if cat.contains("seafood") || cat.contains("fish") { return "🐟" }
        if cat.contains("produce") || cat.contains("fruit") { return "🍎" }
        if cat.contains("vegetable") { return "🥦" }
        if cat.contains("bakery") || cat.contains("bread") { return "🍞" }
        if cat.contains("beverage") || cat.contains("drink") { return "🥤" }
        if cat.contains("snack") { return "🍪" }
        if cat.contains("frozen") { return "🧊" }
        if cat.contains("condiment") || cat.contains("sauce") { return "🫙" }
        if cat.contains("cereal") || cat.contains("grain") { return "🌾" }
        if cat.contains("cleaning") || cat.contains("household") { return "🧼" }
        if cat.contains("personal") || cat.contains("health") { return "🪥" }

        return "🛒"
    }
}
