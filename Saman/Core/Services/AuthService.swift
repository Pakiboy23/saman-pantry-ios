import Foundation
import Supabase

@Observable
final class AuthService {
    private(set) var isSignedIn = false
    private(set) var hasCheckedInitialSession = false
    var errorMessage: String?
    var isLoading = false

    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = .shared) {
        self.supabase = supabase
    }

    /// Call once on app launch — keeps `isSignedIn` in sync with Supabase auth state.
    func startListening() async {
        for await (event, session) in supabase.auth.authStateChanges {
            switch event {
            case .initialSession:
                isSignedIn = session != nil
                hasCheckedInitialSession = true
            case .signedIn, .tokenRefreshed, .userUpdated:
                isSignedIn = session != nil
            case .signedOut, .passwordRecovery, .userDeleted:
                isSignedIn = false
            default:
                break
            }
        }
    }

    func signIn(email: String, password: String) async {
        await run { try await self.supabase.auth.signIn(email: email, password: password) }
    }

    func signUp(email: String, password: String) async {
        await run { try await self.supabase.auth.signUp(email: email, password: password) }
    }

    func signOut() async {
        await run { try await self.supabase.auth.signOut() }
    }

    // MARK: - Private

    private func run(_ action: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
