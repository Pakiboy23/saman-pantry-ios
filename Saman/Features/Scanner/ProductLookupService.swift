import Foundation

struct FoundProduct {
    let name: String
    let brand: String?
    let category: String?
}

/// Queries Open Food Facts (no API key required).
final class ProductLookupService {
    static let shared = ProductLookupService()

    func lookup(barcode: String) async -> FoundProduct? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v0/product/\(barcode).json") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        guard let response = try? JSONDecoder().decode(OFFResponse.self, from: data),
              response.status == 1,
              let product = response.product else { return nil }

        let name = product.productName ?? product.genericName ?? "Unknown Product"
        let brand = product.brands?.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces)
        let category = product.categoriesTags?.first(where: { $0.hasPrefix("en:") })?
            .replacingOccurrences(of: "en:", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized

        return FoundProduct(name: name, brand: brand, category: category)
    }
}

// MARK: - Decodable models (file-scoped to avoid actor isolation issues)

private struct OFFResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

private struct OFFProduct: Decodable {
    let productName: String?
    let genericName: String?
    let brands: String?
    let categoriesTags: [String]?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case genericName = "generic_name"
        case brands
        case categoriesTags = "categories_tags"
    }
}
