import Foundation
import Supabase
import Testing
@testable import Saman

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct AuthSessionRaceTests {
    private let storageKey = "auth-race-test"

    @Test(arguments: [false, true])
    func delayedRefreshCannotRestoreSignedOutAccount(signInAgain: Bool) async throws {
        let storage = AuthTestStorage()
        let old = session("old")
        let replacement = session("new")
        try storage.store(key: storageKey, value: JSONEncoder().encode(old))
        let transport = HeldRefreshResponse(refreshed: session("refreshed", user: old.user), replacement: replacement)
        let client = AuthClient(configuration: .init(
            url: URL(string: "https://auth.invalid"),
            storageKey: storageKey,
            localStorage: storage,
            fetch: { try await transport.fetch($0) },
            autoRefreshToken: false,
            emitLocalSessionAsInitialSession: true
        ))
        let refresh = Task { try await client.refreshSession() }
        await transport.waitUntilRequested()
        try await client.signOut()
        #expect(client.currentSession == nil)
        if signInAgain {
            try await client.signIn(email: "new@example.invalid", password: "synthetic-password")
        }
        await transport.release()
        let result = await refresh.result
        switch result {
        case .success:
            Issue.record("A refresh from before logout must be discarded")
        case .failure(let error):
            #expect(error as? AuthError == .refreshDiscarded)
        }
        #expect(client.currentSession?.accessToken == (signInAgain ? replacement.accessToken : nil))
        // A fresh client uses the same persistent store: logout must survive relaunch too.
        let restored = AuthClient(configuration: .init(
            storageKey: storageKey, localStorage: storage, autoRefreshToken: false,
            emitLocalSessionAsInitialSession: true
        ))
        #expect(restored.currentSession?.accessToken == (signInAgain ? replacement.accessToken : nil))
    }

    @Test func bufferedEventsCannotRestoreClearedSession() throws {
        let (auth, storage) = service()
        let old = session("old")
        try storage.store(key: storageKey, value: JSONEncoder().encode(old))
        auth.handleAuthStateChange(.initialSession, session: old)
        #expect(auth.isSignedIn)
        try storage.remove(key: storageKey)
        auth.handleAuthStateChange(.signedOut, session: nil)
        for event: AuthChangeEvent in [.initialSession, .signedIn, .tokenRefreshed, .userUpdated, .passwordRecovery] {
            auth.handleAuthStateChange(event, session: old)
            #expect(!auth.isSignedIn)
            #expect(auth.currentUserID == nil)
            #expect(!auth.isRecoveringPassword)
        }
        #expect(auth.hasCheckedInitialSession)
    }

    @Test func currentSessionStillSupportsSignInRefreshAndRecovery() throws {
        let (auth, storage) = service()
        let old = session("old")
        let current = session("current")
        try storage.store(key: storageKey, value: JSONEncoder().encode(current))
        auth.handleAuthStateChange(.signedIn, session: current)
        auth.handleAuthStateChange(.tokenRefreshed, session: old)
        #expect(auth.currentUserID == current.user.id.uuidString)
        auth.handleAuthStateChange(.tokenRefreshed, session: current)
        #expect(auth.isSignedIn)
        auth.handleAuthStateChange(.passwordRecovery, session: current)
        #expect(auth.isRecoveringPassword)
        auth.handleAuthStateChange(.userUpdated, session: current)
        #expect(!auth.isRecoveringPassword)
        #expect(auth.isSignedIn)
    }

    private func service() -> (AuthService, AuthTestStorage) {
        let storage = AuthTestStorage()
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://auth.invalid")!, supabaseKey: "synthetic-key",
            options: .init(auth: .init(
                storage: storage, storageKey: storageKey, autoRefreshToken: false,
                emitLocalSessionAsInitialSession: true
            ))
        )
        return (AuthService(supabase: client), storage)
    }

    private func session(_ name: String, user: User? = nil) -> Session {
        Session(
            accessToken: "\(name)-access", tokenType: "bearer", expiresIn: 3600,
            expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970,
            refreshToken: "\(name)-refresh",
            user: user ?? User(id: UUID(), appMetadata: [:], userMetadata: [:], aud: "authenticated",
                       createdAt: Date(), updatedAt: Date())
        )
    }
}

private final class AuthTestStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = nil
    }
}

/// A deterministic response barrier, with no live server or timing sleeps.
private actor HeldRefreshResponse {
    private let requested = AsyncStream<Void>.makeStream()
    private let released = AsyncStream<Void>.makeStream()
    private let refreshed: Session
    private let replacement: Session

    init(refreshed: Session, replacement: Session) {
        self.refreshed = refreshed
        self.replacement = replacement
    }

    func waitUntilRequested() async {
        for await _ in requested.stream { return }
    }

    func release() {
        released.continuation.yield(())
        released.continuation.finish()
    }

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        if url.query?.contains("grant_type=refresh_token") == true {
            requested.continuation.yield(())
            requested.continuation.finish()
            for await _ in released.stream { break }
            return try response(refreshed, url: url)
        }
        if url.path.hasSuffix("/logout") {
            return (Data(), HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!)
        }
        if url.query?.contains("grant_type=password") == true {
            return try response(replacement, url: url)
        }
        throw URLError(.unsupportedURL)
    }

    private func response(_ session: Session, url: URL) throws -> (Data, URLResponse) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return (try encoder.encode(session),
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
