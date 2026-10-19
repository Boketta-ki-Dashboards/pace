import Foundation
import PaceCore
import PostgREST

/// Öffentliche ID des angemeldeten Nutzers – Ordner für Profilbilder und Topic `user:<public_id>` für Echtzeit-
/// Hinweise. Wird einmal je Nutzer aus der eigenen Profilzeile gelesen (RLS: nur die eigene Zeile) und gemerkt.
///
/// `@unchecked Sendable`: `Mutex` gibt es erst ab iOS 18. `cache` wird ausschließlich unter `lock` gelesen und
/// geschrieben.
final class OwnPublicID: @unchecked Sendable {
    private let client: PostgrestClient
    private let currentUserID: @Sendable () -> UUID?
    private let lock = NSLock()
    private var cache: (userID: UUID, publicID: UUID)?

    init(client: PostgrestClient, currentUserID: @escaping @Sendable () -> UUID?) {
        self.client = client
        self.currentUserID = currentUserID
    }

    /// - Throws: `OwnPublicIDError.notSignedIn` ohne Sitzung, `.profileMissing` ohne Profil, sonst den Fehler der
    ///   Anfrage.
    func value() async throws -> UUID {
        guard let userID = currentUserID() else { throw OwnPublicIDError.notSignedIn }
        if let cached = cached(for: userID) {
            return cached
        }
        let row: PublicIDRow? = try await client
            .from("profiles")
            .select("public_id")
            .eq("id", value: userID.uuidString.lowercased())
            .maybeSingle()
            .execute()
            .value
        guard let publicID = row?.publicID else { throw OwnPublicIDError.profileMissing }
        store(publicID, for: userID)
        return publicID
    }

    private func cached(for userID: UUID) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        return cache?.userID == userID ? cache?.publicID : nil
    }

    private func store(_ publicID: UUID, for userID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        cache = (userID, publicID)
    }
}

enum OwnPublicIDError: Error, Equatable {
    case notSignedIn
    case profileMissing
}

private struct PublicIDRow: Decodable {
    let publicID: UUID

    enum CodingKeys: String, CodingKey {
        case publicID = "public_id"
    }
}
