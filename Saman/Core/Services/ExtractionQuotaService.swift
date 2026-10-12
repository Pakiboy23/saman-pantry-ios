import Foundation
import Supabase

/// Free-tier extraction counter for the capture screen.
/// Pro callers should hide the counter; this only describes free quota.
struct ExtractionQuotaStatus: Equatable, Sendable {
    var used: Int
    var limit: Int
    var grandfathered: Bool

    var resetsDaily: Bool { grandfathered }

    var counterLabel: String {
        FreeLimits.extractionCounterLabel(used: used, grandfathered: grandfathered)
    }

    var isExhausted: Bool { used >= limit }

    static let empty = ExtractionQuotaStatus(used: 0, limit: FreeLimits.extractLimit, grandfathered: false)
}

@Observable
final class ExtractionQuotaService {
    private(set) var status: ExtractionQuotaStatus = .empty
    private(set) var isLoading = false

    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = .shared) {
        self.supabase = supabase
    }

    @MainActor
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await supabase
                .rpc("my_extraction_quota_status")
                .execute()
            if let decoded = try? JSONDecoder().decode(RPCStatus.self, from: response.data) {
                status = ExtractionQuotaStatus(
                    used: max(0, decoded.used),
                    limit: decoded.limit > 0 ? decoded.limit : FreeLimits.extractLimit,
                    grandfathered: decoded.grandfathered
                )
            }
        } catch {
            AppLogger.error("[Quota] refresh: \(error)")
        }
    }

    @MainActor
    func noteLocalExtraction() {
        status = ExtractionQuotaStatus(
            used: min(status.used + 1, status.limit),
            limit: status.limit,
            grandfathered: status.grandfathered
        )
    }

    @MainActor
    func resetForSignOut() {
        status = .empty
    }

    private struct RPCStatus: Decodable {
        let grandfathered: Bool
        let used: Int
        let limit: Int
    }
}
