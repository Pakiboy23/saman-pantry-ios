import Foundation
import Supabase

// MARK: - Extraction result types

struct ExtractedIngredient: Codable {
    var ingredient: String
    var originalPhrase: String
    var amount: Double?
    var unit: String?
    var vague: Bool

    enum CodingKeys: String, CodingKey {
        case ingredient, amount, unit, vague
        case originalPhrase = "original_phrase"
    }

    init(ingredient: String, originalPhrase: String, amount: Double?, unit: String?, vague: Bool) {
        self.ingredient = ingredient
        self.originalPhrase = originalPhrase
        self.amount = amount
        self.unit = unit
        self.vague = vague
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
        guard let a = amount, let u = unit else { return "" }
        let s = Int(exactly: a).map { String($0) } ?? String(a)
        return "\(s) \(u)"
    }
}

struct ExtractedRecipe: Codable {
    var title: String
    var attribution: String?
    var ingredients: [ExtractedIngredient]
    var steps: [String]
    var notes: String?
}

// MARK: - Service

struct ExtractionResult {
    let recipe: ExtractedRecipe
    let rawJSON: String
    /// The server's transcript of an uploaded recording. Nil for text and links.
    var transcript: String? = nil
}

final class RecipeExtractionService {
    static let shared = RecipeExtractionService()
    private init() {}

    private let endpoint = URL(string: Config.recipeExtractionEndpoint)!

    func extract(transcript: String) async throws -> ExtractionResult {
        try await perform(RequestBody(transcript: transcript, url: nil), route: .transcript)
    }

    func extract(url: String) async throws -> ExtractionResult {
        try await perform(RequestBody(transcript: nil, url: url), route: .url)
    }

    /// Uploads a recording. The server transcribes it, then runs the same
    /// extraction as a transcript; the result carries that transcript.
    func extract(recording: RecipeRecording) async throws -> ExtractionResult {
        let audio: Data
        do {
            audio = try Data(contentsOf: recording.url)
        } catch {
            throw RecipeAudioError.unreadableFile
        }
        let boundary = "samaan-\(UUID().uuidString)"
        let body = Self.multipartBody(
            audio: audio,
            filename: recording.uploadFilename,
            mimeType: recording.mimeType,
            boundary: boundary
        )
        return try await send(
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            // Transcription (up to 60 s) plus the model call.
            timeout: 150,
            route: .audio
        )
    }

    /// One `audio` part, as `extract-recipe` expects.
    static func multipartBody(audio: Data, filename: String, mimeType: String, boundary: String) -> Data {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    /// Sends a JSON extraction request (transcript or link).
    private func perform(_ body: RequestBody, route: RecipeExtractionRoute) async throws -> ExtractionResult {
        try await send(
            body: try JSONEncoder().encode(body),
            contentType: "application/json",
            timeout: 60,
            route: route
        )
    }

    /// Posts to `extract-recipe` with the user JWT and decodes the recipe, mapping failures to `ExtractionError`.
    private func send(body: Data, contentType: String, timeout: TimeInterval, route: RecipeExtractionRoute) async throws -> ExtractionResult {
        let token: String
        do {
            token = try await SupabaseClient.shared.auth.session.accessToken
        } catch {
            throw ExtractionError.unauthorized
        }
        try Task.checkCancellation()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: request, from: body)
        } catch let error as URLError where error.code != .cancelled {
            // Offline or timed out. For a recording, the file is kept for a retry.
            throw ExtractionError.apiError
        }
        guard let http = response as? HTTPURLResponse else { throw ExtractionError.apiError }
        guard (200...299).contains(http.statusCode) else {
            throw Self.failure(status: http.statusCode, data: data, route: route)
        }

        let serviceResp = try JSONDecoder().decode(EdgeFunctionResponse.self, from: data)
        return ExtractionResult(recipe: serviceResp.recipe, rawJSON: serviceResp.rawJSON, transcript: serviceResp.transcript)
    }

    /// Maps an HTTP error status and response body to the matching `ExtractionError`.
    static func failure(status: Int, data: Data, route: RecipeExtractionRoute) -> ExtractionError {
        let body = try? JSONDecoder().decode(ExtractionErrorResponse.self, from: data)
        if status == 401 { return .unauthorized }
        if status == 402 { return .quotaExceeded }
        if let code = body?.code, let known = KnownExtractionCode(rawValue: code) {
            switch known {
            case .quotaExceeded:
                return .quotaExceeded
            case .instagramCaptionUnavailable:
                return .instagramCaptionUnavailable
            case .urlNotAllowed:
                return .urlNotAllowed
            case .urlFetchFailed:
                return .urlFetchFailed
            case .noRecipeText:
                let resolved = resolvedRoute(from: body?.source, fallback: route)
                if resolved == .audio {
                    return .noRecipeInRecording(transcript: body?.transcript)
                }
                return .noRecipeText(resolved)
            case .audioTooLarge:
                return .audioTooLarge
            case .audioUnsupportedType, .audioMissing:
                return .audioUnreadable
            case .audioNoSpeech:
                return .audioNoSpeech
            case .transcriptionFailed:
                return .transcriptionFailed
            }
        }
        if status == 413 { return .audioTooLarge }
        if let message = body?.message, !message.isEmpty {
            return .serviceError(message)
        }
        return .apiError
    }

    /// Server `source` wins when the deployed function sends it. Older
    /// functions omit it, so the route this call actually used is the fallback.
    private static func resolvedRoute(from source: String?, fallback: RecipeExtractionRoute) -> RecipeExtractionRoute {
        switch source {
        case RecipeExtractionRoute.url.rawValue:
            return .url
        case RecipeExtractionRoute.transcript.rawValue:
            return .transcript
        case RecipeExtractionRoute.audio.rawValue:
            return .audio
        default:
            return fallback
        }
    }

    enum ExtractionError: LocalizedError {
        case apiError, serviceError(String), quotaExceeded, unauthorized
        case instagramCaptionUnavailable, urlNotAllowed, urlFetchFailed
        case noRecipeText(RecipeExtractionRoute)
        case audioTooLarge, audioUnreadable, audioNoSpeech, transcriptionFailed
        /// The recording became text but held no recipe. The slot is spent,
        /// so the transcript comes back for the cook to fix and resend.
        case noRecipeInRecording(transcript: String?)

        /// Whether a recording is worth keeping for a retry after this error.
        var keepsRecordingForRetry: Bool {
            switch self {
            case .apiError, .serviceError, .quotaExceeded, .unauthorized, .transcriptionFailed:
                return true
            case .audioTooLarge, .audioUnreadable, .audioNoSpeech, .noRecipeInRecording,
                 .instagramCaptionUnavailable, .urlNotAllowed, .urlFetchFailed, .noRecipeText:
                return false
            }
        }

        var captureAlertTitle: String {
            switch self {
            case .quotaExceeded:
                return "Upgrade to continue"
            case .instagramCaptionUnavailable:
                return "Paste the caption"
            case .urlNotAllowed, .urlFetchFailed, .noRecipeText(.url):
                return "Couldn't open that link"
            case .noRecipeText(.transcript), .noRecipeText(.audio), .noRecipeInRecording:
                return "Couldn't find a recipe"
            case .audioTooLarge, .audioUnreadable:
                return "Couldn't send the recording"
            case .audioNoSpeech:
                return "Didn't catch that"
            case .transcriptionFailed:
                return "Couldn't read the recording"
            case .apiError, .serviceError, .unauthorized:
                return "Extraction failed"
            }
        }

        var errorDescription: String? {
            switch self {
            case .apiError:
                return "Couldn't reach the extraction service. Check your connection and try again."
            case .serviceError(let message):
                return message
            case .quotaExceeded:
                return FreeLimits.paywallContextExtractionLimit
            case .unauthorized:
                return "Please sign in again, then retry."
            case .instagramCaptionUnavailable:
                return "Couldn't read the caption on this Instagram link. Paste the caption text instead and I'll pull the recipe from that."
            case .urlNotAllowed:
                return "That link isn't one I can open. Paste a public http or https recipe link."
            case .urlFetchFailed:
                return "Couldn't open that link. Check it and try again, or paste the recipe text."
            case .noRecipeText(.transcript), .noRecipeText(.audio):
                return "I only caught part of that. Try recording again, or type the ingredients and steps."
            case .noRecipeText(.url):
                return "Couldn't find a recipe in that link. Paste the description or caption text and I'll try from that."
            case .noRecipeInRecording(let transcript):
                if let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "I couldn't find a recipe in that. The words I heard are in the box below. Fix them and tap Extract Recipe."
                }
                return "I only caught part of that. Try recording again, or type the ingredients and steps."
            case .audioTooLarge:
                return "That recording is too big to send. Keep it under 10 minutes."
            case .audioUnreadable:
                return "Couldn't read that recording. Try an m4a or mp3 file, or record it in the app."
            case .audioNoSpeech:
                return "I didn't catch any words. Record again, or type the recipe."
            case .transcriptionFailed:
                return "Couldn't turn your recording into text. It's saved, so you can try again."
            }
        }
    }
}

enum RecipeExtractionRoute: String, Equatable {
    case transcript
    case url
    case audio
}

// MARK: - Link field

enum RecipeLinkInput {
    /// A single http(s) link. A bare YouTube, Instagram, or www paste gets https.
    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains(where: \.isWhitespace) else { return nil }
        let withScheme = ensureScheme(trimmed)
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else { return nil }
        return withScheme
    }

    static func hostLabel(_ raw: String) -> String? {
        guard let host = URL(string: raw)?.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { return String(host.dropFirst(4)) }
        return host
    }

    private static func ensureScheme(_ value: String) -> String {
        if value.contains("://") { return value }
        let lower = value.lowercased()
        let prefixes = [
            "youtu.be/", "youtube.com/", "www.youtube.com/", "m.youtube.com/",
            "instagram.com/", "www.instagram.com/", "www.",
        ]
        if prefixes.contains(where: { lower.hasPrefix($0) }) {
            return "https://" + value
        }
        return value
    }
}


// MARK: - Capture route

/// Decides whether extract uses a link or the transcript.
/// A recording or picked audio file always uses the transcript, even if a link is still typed.
enum RecipeCaptureRoute: Equatable {
    case url(String)
    case transcript(String)
    case invalidLink
    case empty

    static func route(linkRaw: String, transcriptRaw: String, fromAudio: Bool) -> RecipeCaptureRoute {
        if fromAudio {
            guard let text = RecipeAudioTranscript.readyForExtract(transcriptRaw) else { return .empty }
            return .transcript(text)
        }
        let linkField = linkRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = transcriptRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !linkField.isEmpty {
            guard let link = RecipeLinkInput.normalized(linkField) else { return .invalidLink }
            return .url(link)
        }
        if let link = RecipeLinkInput.normalized(text) {
            return .url(link)
        }
        if let spoken = RecipeAudioTranscript.readyForExtract(text) {
            return .transcript(spoken)
        }
        return .empty
    }
}

// MARK: - Private request / response types

private extension RecipeExtractionService {
    struct RequestBody: Encodable {
        var transcript: String?
        var url: String?

        enum CodingKeys: String, CodingKey {
            case transcript, url
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(transcript, forKey: .transcript)
            try container.encodeIfPresent(url, forKey: .url)
        }
    }

    enum KnownExtractionCode: String {
        case quotaExceeded = "quota_exceeded"
        case instagramCaptionUnavailable = "instagram_caption_unavailable"
        case urlNotAllowed = "url_not_allowed"
        case urlFetchFailed = "url_fetch_failed"
        case noRecipeText = "no_recipe_text"
        case audioTooLarge = "audio_too_large"
        case audioUnsupportedType = "audio_unsupported_type"
        case audioMissing = "audio_missing"
        case audioNoSpeech = "audio_no_speech"
        case transcriptionFailed = "transcription_failed"
    }

    struct EdgeFunctionResponse: Decodable {
        let recipe: ExtractedRecipe
        let rawJSON: String
        let transcript: String?

        enum CodingKeys: String, CodingKey {
            case recipe
            case rawJSON = "raw_json"
            case transcript
        }
    }

    struct ExtractionErrorResponse: Decodable {
        let message: String
        let code: String?
        let source: String?
        let transcript: String?

        enum CodingKeys: String, CodingKey {
            case message
            case error
            case code
            case source
            case transcript
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            message = (try? c.decode(String.self, forKey: .message))
                ?? (try? c.decode(String.self, forKey: .error))
                ?? "Recipe extraction failed. Please try again."
            code = try? c.decode(String.self, forKey: .code)
            source = try c.decodeIfPresent(String.self, forKey: .source)
            transcript = try? c.decodeIfPresent(String.self, forKey: .transcript)
        }
    }
}
