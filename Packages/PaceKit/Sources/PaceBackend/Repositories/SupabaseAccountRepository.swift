import Auth
import Foundation
import PaceCore
import PostgREST
import Storage

/// Datenschutz-Funktionen (Migration 20261019100400): Auskunft, eigene Dateien, Konto löschen, Rückmeldungen.
struct SupabaseAccountRepository: AccountRepository {
    let client: PostgrestClient
    let storage: SupabaseStorageClient
    let auth: AuthClient

    /// JSON aller personenbezogenen Serverdaten, lesbar formatiert (Schlüssel sortiert).
    func exportData() async throws -> Data {
        let raw = try await mapped {
            try await client.rpc("account_export").execute().data
        }
        guard let object = try? JSONSerialization.jsonObject(with: raw),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else {
            return raw
        }
        return pretty
    }

    func ownMedia() async throws -> [MediaReference] {
        let rows: [MediaReferenceRow] = try await mapped {
            try await client.rpc("account_own_media").execute().value
        }
        return rows.compactMap(\.reference)
    }

    /// Entfernt zuerst die eigenen Dateien aus Storage (direktes Löschen in der Datenbank erlaubt Supabase nicht),
    /// dann das Konto mit allen verknüpften Daten, und meldet zuletzt lokal ab.
    func deleteAccount() async throws {
        let media = try await ownMedia()
        for bucket in MediaBucket.allCases {
            let paths = media.filter { $0.bucket == bucket }.map(\.path)
            guard !paths.isEmpty else { continue }
            do {
                try await storage.from(bucket.rawValue).remove(paths: paths)
            } catch {
                throw Self.accountError(fromStorage: error)
            }
        }
        try await mapped {
            try await client.rpc("account_delete").execute()
        }
        // Die Sitzung gehört zu einem gelöschten Nutzer; das Token ist auf dem Server ungültig.
        try? await auth.signOut(scope: .local)
    }

    func submitFeedback(kind: FeedbackKind, message: String, appVersion: String) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= FeedbackRules.maximumLength else { throw AccountError.invalidInput }
        try await mapped {
            try await client.rpc("submit_feedback", params: FeedbackParams(
                kind: kind.rawValue,
                message: trimmed,
                appVersion: Self.sanitizedVersion(appVersion)
            )).execute()
        }
    }

    /// Nur Zeichen, die der Server für die App-Version zulässt (z. B. `1.4 (12)`), höchstens 40.
    static func sanitizedVersion(_ version: String) -> String {
        let allowed = CharacterSet(charactersIn: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ .()_-")
        var result = ""
        for scalar in version.unicodeScalars where allowed.contains(scalar) && result.unicodeScalars.count < 40 {
            result.unicodeScalars.append(scalar)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func accountError(fromStorage error: any Error) -> AccountError {
        switch BackendErrorMapping.mediaError(error) {
        case .network: .network
        case .unavailable: .unavailable
        default: .unexpected(String(describing: error))
        }
    }

    @discardableResult
    private func mapped<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as AccountError {
            throw error
        } catch {
            throw BackendErrorMapping.accountError(error)
        }
    }
}

private struct FeedbackParams: Encodable {
    let kind: String
    let message: String
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case kind = "p_kind"
        case message = "p_message"
        case appVersion = "p_app_version"
    }
}
