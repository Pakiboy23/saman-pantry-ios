import Foundation
import Supabase

@Observable
final class AuthService {
    private(set) var isSignedIn = false
    private(set) var hasCheckedInitialSession = false
    private(set) var currentUserID: String? = nil
    private(set) var pendingEmailConfirmation = false
    private(set) var pendingPasswordReset = false
    private(set) var isRecoveringPassword = false
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
            case .signedIn, .tokenRefreshed:
                isSignedIn = session != nil
                currentUserID = session?.user.id.uuidString
                pendingEmailConfirmation = false
                pendingPasswordReset = false
            case .userUpdated:
                isSignedIn = session != nil
                currentUserID = session?.user.id.uuidString
                pendingEmailConfirmation = false
                pendingPasswordReset = false
                isRecoveringPassword = false
            case .passwordRecovery:
                // A recovery session is a real session. Do not treat it as a
                // sign-out — the app has to show the set-new-password form.
                isSignedIn = session != nil
                currentUserID = session?.user.id.uuidString
                isRecoveringPassword = true
                pendingPasswordReset = false
            case .signedOut, .userDeleted:
                isSignedIn = false
                currentUserID = nil
                isRecoveringPassword = false
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
            // Same deep link as resetPassword. Without redirectTo, Supabase
            // embeds Site URL (localhost) and testers open Safari, not the app.
            // Site URL + Redirect URLs in the dashboard must include this URL.
            try await supabase.auth.signUp(
                email: email,
                password: password,
                redirectTo: URL(string: Config.authCallbackURL)
            )
            pendingEmail = email
            pendingEmailConfirmation = true
        } catch {
            errorMessage = Self.friendly(error)
        }
        isLoading = false
    }

    func resetPassword(email: String) async {
        isLoading = true
        errorMessage = nil
        do {
            try await supabase.auth.resetPasswordForEmail(
                email,
                redirectTo: URL(string: Config.authCallbackURL)
            )
            pendingEmail = email
            pendingPasswordReset = true
        } catch {
            errorMessage = Self.friendly(error)
        }
        isLoading = false
    }

    func updatePassword(_ password: String) async {
        await run {
            try await self.supabase.auth.update(user: UserAttributes(password: password))
        }
    }

    /// Called from the app's `onOpenURL`. Recovers the session from a
    /// `samaan://auth-callback` redirect (signup confirmation or password reset).
    func handleAuthURL(_ url: URL) async {
        do {
            _ = try await supabase.auth.session(from: url)
        } catch {
            errorMessage = Self.friendly(error)
        }
    }

    func cancelConfirmation() {
        pendingEmailConfirmation = false
        pendingEmail = ""
        errorMessage = nil
    }

    func cancelPasswordReset() {
        pendingPasswordReset = false
        pendingEmail = ""
        errorMessage = nil
    }

    func resendConfirmation() async {
        guard !pendingEmail.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await supabase.auth.resend(
                email: pendingEmail,
                type: .signup,
                emailRedirectTo: URL(string: Config.authCallbackURL)
            )
        } catch {
            errorMessage = Self.friendly(error)
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

    /// Map provider errors to a short line a person can act on.
    static func friendly(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("invalid login") || raw.contains("invalid credentials") || raw.contains("invalid email or password") {
            return "Email or password is wrong."
        }
        if raw.contains("already registered") || raw.contains("user already") || raw.contains("already been registered") {
            return "That email already has an account. Try signing in."
        }
        if raw.contains("rate limit") || raw.contains("too many") {
            return "Too many attempts. Wait a minute and try again."
        }
        if raw.contains("network") || raw.contains("offline") || raw.contains("not connected") || raw.contains("internet") {
            return "Couldn't reach the server. Check your connection."
        }
        if raw.contains("password") && (raw.contains("6") || raw.contains("least") || raw.contains("short") || raw.contains("weak")) {
            return "Use a password with at least 6 characters."
        }
        return "Something went wrong. Please try again."
    }

    // MARK: - Private

    private func run(_ action: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await action()
        } catch {
            errorMessage = Self.friendly(error)
        }
        isLoading = false
    }
}
