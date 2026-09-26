import Foundation

extension Item {
    /// Best-guess emoji from the item name. Desi names stay above the generic grocery tail.
    var emoji: String {
        let n = name.lowercased()

        // Name-based matches. Desi names and aliases stay above the generic grocery tail.
        let nameLookup: [(String, String)] = [
            ("atta", "🌾"), ("aata", "🌾"),
            ("daal", "🫘"), ("dal", "🫘"),
            ("ghee", "🧈"),
            ("haldi", "🟡"), ("turmeric", "🟡"),
            ("jeera", "🌿"), ("cumin", "🌿"),
            ("dhaniya", "🌿"), ("dhania", "🌿"), ("coriander", "🌿"),
            ("mirch", "🌶️"), ("chilli", "🌶️"), ("chili", "🌶️"),
            ("chai", "🍵"),
            ("masala", "🌶️"),
            ("paneer", "🧀"),
            ("adrak", "🫚"), ("ginger", "🫚"),
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
            ("salt", "🧂"), ("spice", "🌶️"), ("herb", "🌿"),
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

        return "🛒"
    }
}
