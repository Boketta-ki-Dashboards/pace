import Foundation

/// Ergebnis des App-Starts nach der Health-Abfrage.
public enum BootstrapOutcome: Equatable, Sendable {
    /// Angemeldet, aber noch kein Profil.
    case needsProfile(UserID)
    /// Profil existiert, aber es fehlt die Region.
    case needsRegion(UserProfile)
    /// Alles vollständig.
    case ready(UserProfile)
}

public enum BootstrapError: Error, Equatable, Sendable {
    case auth(AuthError)
    case profile(ProfileError)
}

/// Stellt Sitzung und Profil sicher: vorhandene Sitzung nutzen, sonst anonym anmelden, dann Profil prüfen.
public struct SessionBootstrapper: Sendable {
    private let auth: any AuthProviding
    private let profiles: any ProfileRepository
    private let cache: any ProfileCaching

    public init(auth: any AuthProviding, profiles: any ProfileRepository, cache: any ProfileCaching) {
        self.auth = auth
        self.profiles = profiles
        self.cache = cache
    }

    public func run() async throws(BootstrapError) -> BootstrapOutcome {
        let session = try await ensureSession()

        // Ein vollständiges Profil aus dem Cache erlaubt den Start ohne Netz. Aktualisiert wird danach im Hintergrund.
        if let cached = cache.load(for: session.userID), cached.isComplete {
            return .ready(cached)
        }

        let profile: UserProfile?
        do {
            profile = try await profiles.fetchProfile(for: session.userID)
        } catch let error as ProfileError {
            throw .profile(error)
        } catch {
            throw .profile(.unexpected(String(describing: error)))
        }

        guard let profile else {
            return .needsProfile(session.userID)
        }
        cache.save(profile)
        return profile.isComplete ? .ready(profile) : .needsRegion(profile)
    }

    private func ensureSession() async throws(BootstrapError) -> AuthSession {
        if let session = await auth.restoreSession() {
            return session
        }
        do {
            return try await auth.signInAnonymously()
        } catch let error as AuthError {
            throw .auth(error)
        } catch {
            throw .auth(.unexpected(String(describing: error)))
        }
    }
}
