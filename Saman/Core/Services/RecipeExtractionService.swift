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

final class RecipeExtractionService {
    static let shared = RecipeExtractionService()
    private init() {}

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model    = "claude-sonnet-4-6"

    func extract(transcript: String) async throws -> ExtractedRecipe {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(Config.anthropicAPIKey,  forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",            forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json",      forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(transcript: transcript, model: model))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ExtractionError.apiError
        }

        let apiResp = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = apiResp.content.first(where: { $0.type == "text" })?.text else {
            throw ExtractionError.noContent
        }

        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else { throw ExtractionError.parseError }
        return try JSONDecoder().decode(ExtractedRecipe.self, from: jsonData)
    }

    enum ExtractionError: LocalizedError {
        case apiError, noContent, parseError
        var errorDescription: String? {
            switch self {
            case .apiError:   return "Couldn't reach the extraction service. Check your connection and try again."
            case .noContent:  return "Got an empty response. Please try again."
            case .parseError: return "Couldn't parse the recipe. Try a cleaner transcript."
            }
        }
    }
}

// MARK: - Private request / response types

private extension RecipeExtractionService {

    struct RequestBody: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [Message]

        init(transcript: String, model: String) {
            self.model     = model
            self.maxTokens = 2000
            self.system    = RecipeExtractionService.systemPrompt
            self.messages  = [Message(
                role:    "user",
                content: "Transcript:\n\n\(transcript)\n\nReturn the structured recipe as JSON."
            )]
        }

        enum CodingKeys: String, CodingKey {
            case model, system, messages
            case maxTokens = "max_tokens"
        }

        struct Message: Encodable { let role: String; let content: String }
    }

    struct AnthropicResponse: Decodable {
        let content: [ContentBlock]
        struct ContentBlock: Decodable { let type: String; let text: String? }
    }

    // Exact port of extraction.py SYSTEM_PROMPT + OUTPUT_SCHEMA
    static let systemPrompt = """
    You convert a spoken, phone-call recipe into a structured recipe. The speaker \
    is a South Asian parent. The transcript is code-switched (Urdu/Hindi/Punjabi + \
    English) and the measurements are mostly approximate.

    You will follow three rules without exception:

    RULE 1 - NEVER INVENT A NUMBER.
    If the speaker gave a vague measurement ("andaza se", "thori si", "a handful", \
    "to taste", "apne hisaab se", "mutthi bhar", "chutki bhar"), set amount to null \
    and vague to true. Do NOT convert vague amounts into grams, cups, or any number. \
    Inventing "30g" for "a fistful" is the single worst thing you can do.
    A number is allowed ONLY when the speaker actually said one: "ek pyaaz" -> 1, \
    "do cup" -> 2, "half teaspoon" -> 0.5 tsp, "ek kilo" -> 1 kg.

    RULE 2 - NEVER DISCARD HER WORDS.
    For every ingredient, original_phrase holds the speaker's exact phrasing, \
    code-switch intact ("haldi just a little, andaza se").

    RULE 3 - MAP THE NAME FOR THE GROCERY LIST.
    ingredient is the English shopping term so it can go on a list \
    (haldi -> turmeric, pyaaz -> onion, zeera/jeera -> cumin, lehsun -> garlic, \
    adrak -> ginger, tamatar -> tomato, dhaniya -> cilantro/coriander, \
    chawal -> rice, doodh -> milk, cheeni -> sugar, elaichi -> cardamom, \
    namak -> salt, laal mirch -> red chili, gobi -> cauliflower, aloo -> potato, \
    dahi -> yogurt). original_phrase still keeps the original word.

    Return ONLY valid JSON matching this schema, no prose, no markdown fences:
    {"title":"string - recipe name","attribution":"string|null","ingredients":[{"ingredient":"string - English grocery-list term","original_phrase":"string - speaker's exact words","amount":"number|null - ONLY if a real quantity was spoken, else null","unit":"string|null","vague":"boolean - true if measurement was approximate"}],"steps":["string - loose step, no invented precision"],"notes":"string|null"}
    """
}
