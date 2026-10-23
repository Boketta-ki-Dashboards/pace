import Foundation
import PaceCore
import Storage
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Bilder und Sprachnachrichten in Supabase Storage (private Buckets, Migrationen 20261019100300 und 20261023100100).
/// Format und Größe werden vor dem Upload geprüft; der Server erzwingt dieselben Grenzen (Bucket-Einstellungen) und
/// die Berechtigungen (Policies).
///
/// Pfade: `<Ordner>/<zufällige UUID>.<Endung>` – Ordner ist die eigene öffentliche ID (Profilbild), die Gruppen-ID
/// (Gruppenbild) bzw. die Unterhaltung (Chat-Anhang: Bild, GIF oder Sprachnachricht als `.m4a`/`.aac`). Dateien
/// werden nie überschrieben.
struct SupabaseMediaRepository: MediaRepository {
    let storage: SupabaseStorageClient
    let ownPublicID: OwnPublicID
    /// Zufälliger Dateiname (in Tests fest).
    var makeFileName: @Sendable () -> String = { UUID().uuidString.lowercased() }

    func upload(_ data: Data, contentType: String, to target: MediaUploadTarget) async throws -> MediaReference {
        let type = contentType.lowercased()
        guard let fileExtension = Self.fileExtensions[type], MediaRules.allowedContentTypes(for: target).contains(type) else {
            throw MediaError.unsupportedType
        }
        guard !data.isEmpty else { throw MediaError.unexpected("Leere Datei.") }
        guard data.count <= MediaRules.maximumBytes(for: target) else { throw MediaError.tooLarge }

        return try await mapped {
            let (bucket, folder) = try await location(for: target)
            let path = "\(folder)/\(makeFileName()).\(fileExtension)"
            try await storage.from(bucket.rawValue).upload(
                path,
                data: data,
                options: FileOptions(cacheControl: "3600", contentType: type, upsert: false)
            )
            return MediaReference(bucket: bucket, path: path)
        }
    }

    func data(for reference: MediaReference) async throws -> Data {
        try await mapped {
            try await storage.from(reference.bucket.rawValue).download(path: reference.path)
        }
    }

    /// Storage antwortet auch ohne Berechtigung mit Erfolg, löscht dann aber nichts – das wird zu `.notFound`.
    func delete(_ reference: MediaReference) async throws {
        let removed = try await mapped {
            try await storage.from(reference.bucket.rawValue).remove(paths: [reference.path])
        }
        if removed.isEmpty {
            throw MediaError.notFound
        }
    }

    private func location(for target: MediaUploadTarget) async throws -> (MediaBucket, String) {
        switch target {
        case .avatar:
            do {
                return (.avatars, try await ownPublicID.value().uuidString.lowercased())
            } catch is OwnPublicIDError {
                throw MediaError.notAllowed
            }
        case .groupImage(let groupID):
            return (.groupImages, groupID.uuidString.lowercased())
        case .chat(let conversationID):
            return (.chatMedia, conversationID.uuidString.lowercased())
        }
    }

    private func mapped<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw BackendErrorMapping.mediaError(error)
        }
    }

    /// Endungen passend zu `MediaRules.allowedContentTypes(for:)` (wie die Pfadprüfung auf dem Server).
    static let fileExtensions: [String: String] = [
        "image/jpeg": "jpg",
        "image/png": "png",
        "image/gif": "gif",
        "image/heic": "heic",
        "image/webp": "webp",
        "audio/mp4": "m4a",
        "audio/x-m4a": "m4a",
        "audio/aac": "aac",
    ]
}

extension SupabaseStorageClient {
    /// Storage-Client, der wie PostgREST nur mit Sitzung `Authorization: Bearer <Access Token>` sendet und den
    /// Publishable Key ausschließlich im Header `apikey`.
    static func pace(configuration: BackendConfiguration, session: URLSession, tokens: AccessTokenProvider) -> SupabaseStorageClient {
        let authorized: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            var request = request
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            if let token = try await tokens.accessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return try await session.data(for: request)
        }
        return SupabaseStorageClient(configuration: StorageClientConfiguration(
            url: configuration.storageURL,
            headers: ["apikey": configuration.publishableKey],
            session: StorageHTTPSession(
                fetch: authorized,
                upload: { request, data in
                    var request = request
                    request.httpBody = data
                    return try await authorized(request)
                }
            ),
            logger: nil
        ))
    }
}
