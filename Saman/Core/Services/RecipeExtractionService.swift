import Foundation

// MARK: - Extraction result types

struct ExtractedIngredient: Decodable {
    let ingredient: String
    let originalPhrase: String
    let amount: Double?
    let unit: String?
    let vague: Bool

    enum CodingKeys: String, CodingKey {
        case ingredient, amount, unit, vague
        case originalPhrase = "original_phrase"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ingredient    = try  c.decode(String.self,  forKey: .ingredient)
        originalPhrase = try c.decode(String.self,  forKey: .originalPhrase)
        amount        = try  c.decodeIfPresent(Double.self, forKey: .amount)
        unit          = try  c.decodeIfPresent(String.self, forKey: .unit)
        // Guard against a model that omits vague: infer from amount being nil
        vague = (try? c.decode(Bool.self, forKey: .vague)) ?? (amount == nil)
    }

    var amountLabel: String {
        guard let a = amount, let u = unit else { return "—" }
        let s = a.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(a))" : "\(a)"
        return "\(s) \(u)"
    }
}

struct ExtractedRecipe: Decodable {
    let title: String
    let attribution: String?
    let ingredients: [ExtractedIngredient]
    let steps: [String]
    let notes: String?
}

// MARK: - Service

struct ExtractionResult {
    let recipe: ExtractedRecipe
    let rawJSON: String
}

final class RecipeExtractionService {
    static let shared = RecipeExtractionService()
    private init() {}

    private let endpoint = URL(string: Config.recipeExtractionEndpoint)!

    func extract(transcript: String) async throws -> ExtractionResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(RequestBody(transcript: transcript))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ExtractionError.apiError }
        guard (200...299).contains(http.statusCode) else {
            if let error = try? JSONDecoder().decode(ExtractionErrorResponse.self, from: data), !error.message.isEmpty {
                throw ExtractionError.serviceError(error.message)
            }
            throw ExtractionError.apiError
        }

        let serviceResp = try JSONDecoder().decode(EdgeFunctionResponse.self, from: data)
        return ExtractionResult(recipe: serviceResp.recipe, rawJSON: serviceResp.rawJSON)
    }

    enum ExtractionError: LocalizedError {
        case apiError, noContent, parseError, serviceError(String)
        var errorDescription: String? {
            switch self {
            case .apiError:   return "Couldn't reach the extraction service. Check your connection and try again."
            case .noContent:  return "Got an empty response. Please try again."
            case .parseError: return "Couldn't parse the recipe. Try a cleaner transcript."
            case .serviceError(let message): return message
            }
        }
    }
}

// MARK: - Private request / response types

private extension RecipeExtractionService {
    struct RequestBody: Encodable {
        let transcript: String
    }

    struct EdgeFunctionResponse: Decodable {
        let recipe: ExtractedRecipe
        let rawJSON: String

        enum CodingKeys: String, CodingKey {
            case recipe
            case rawJSON = "raw_json"
        }
    }

    struct ExtractionErrorResponse: Decodable {
        let message: String

        enum CodingKeys: String, CodingKey {
            case message
            case error
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            message = (try? c.decode(String.self, forKey: .message))
                ?? (try? c.decode(String.self, forKey: .error))
                ?? "Recipe extraction failed. Please try again."
        }
    }
}
