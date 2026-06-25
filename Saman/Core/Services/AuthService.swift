import Foundation
import Supabase

@Observable
final class AuthService {
    private(set) var isSignedIn = false
    private(set) var hasCheckedInitialSession = false
    private(set) var currentUserID: String? = nil
    private(set) var pendingEmailConfirmation = false
    private(set) var pendingEmail = ""
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
                currentUserID = session?.user.id.uuidString
                hasCheckedInitialSession = true
            case .signedIn, .tokenRefreshed, .userUpdated:
                isSignedIn = session != nil
                currentUserID = session?.user.id.uuidString
                pendingEmailConfirmation = false
            case .signedOut, .passwordRecovery, .userDeleted:
                isSignedIn = false
                currentUserID = nil
            default:
                break
            }
        }
    }

    func signIn(email: String, password: String) async {
        await run { try await self.supabase.auth.signIn(email: email, password: password) }
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            try await supabase.auth.signUp(email: email, password: password)
            pendingEmail = email
            pendingEmailConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func cancelConfirmation() {
        pendingEmailConfirmation = false
        pendingEmail = ""
        errorMessage = nil
    }

    func resendConfirmation() async {
        guard !pendingEmail.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await supabase.auth.resend(email: pendingEmail, type: .signup)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signOut() async {
        await run { try await self.supabase.auth.signOut() }
    }

    /// Permanently delete the signed-in account via the delete-account Edge
    /// Function (App Store 5.1.1(v)). On success the user is signed out; the
    /// caller is responsible for wiping the local store. Returns true on success.
    @discardableResult
    func deleteAccount() async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let token = try await supabase.auth.session.accessToken
            guard let url = URL(string: Config.deleteAccountEndpoint) else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try? await supabase.auth.signOut()
            return true
        } catch {
            errorMessage = "Couldn't delete your account. Please try again."
            return false
        }
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
