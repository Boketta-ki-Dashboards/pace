import Foundation
import PaceBackend
import PaceCore
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Medien (private Buckets und Policies), Auskunft, Rückmeldung und Kontolöschung gegen den lokalen Stack
/// (Migrationen 20261019100300 und 20261019100400).
@Suite(.enabled(if: IntegrationEnvironment.configuration != nil, "PACE_SUPABASE_URL/PACE_SUPABASE_PUBLISHABLE_KEY fehlen"))
struct MediaAccountIntegrationTests {
    /// Kleinste gültige PNG-Datei (1 × 1 Pixel).
    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    @Test func avatarUploadDownloadAndFolderRules() async throws {
        let anna = try await IntegrationUser.make("Bild", steps: 0)
        let ben = try await IntegrationUser.make("Betrachter", steps: 0)

        let avatar = try await anna.media.upload(Self.png, contentType: "image/png", to: .avatar)
        #expect(avatar.bucket == .avatars)
        #expect(avatar.path.hasPrefix(anna.publicID.uuidString.lowercased() + "/"))
        #expect(avatar.path.hasSuffix(".png"))
        #expect(try await anna.profiles.updateAvatar(path: avatar.path, for: anna.session.userID).avatarPath == avatar.path)

        // Angemeldete mit Profil sehen das Profilbild; die Suche liefert den Pfad mit.
        #expect(try await ben.media.data(for: avatar) == Self.png)
        #expect(try await ben.social.findProfile(username: anna.username)?.profile.avatarPath == avatar.path)

        // Fremde Dateien: nicht als eigenes Profilbild verwendbar, nicht löschbar.
        let bensAvatar = try await ben.media.upload(Self.png, contentType: "image/png", to: .avatar)
        await #expect(throws: ProfileError.self) {
            try await anna.profiles.updateAvatar(path: bensAvatar.path, for: anna.session.userID)
        }
        await #expect(throws: MediaError.notFound) {
            try await anna.media.delete(bensAvatar)
        }
        #expect(try await ben.media.data(for: bensAvatar) == Self.png)

        // Wer blockiert wurde, sieht das Profilbild nicht mehr.
        try await anna.social.block(ben.publicID)
        await #expect(throws: MediaError.self) {
            try await ben.media.data(for: avatar)
        }
        try await anna.social.unblock(ben.publicID)

        // Format und Größe prüft schon die App (der Server erzwingt dieselben Grenzen, siehe unten).
        await #expect(throws: MediaError.unsupportedType) {
            try await anna.media.upload(Data("kein Bild".utf8), contentType: "text/plain", to: .avatar)
        }
        await #expect(throws: MediaError.tooLarge) {
            try await anna.media.upload(Data(count: MediaRules.maximumBytes(for: .avatar) + 1), contentType: "image/jpeg", to: .avatar)
        }

        // Entfernen: Profil ohne Bild, Datei gelöscht.
        #expect(try await anna.profiles.updateAvatar(path: nil, for: anna.session.userID).avatarPath == nil)
        try await anna.media.delete(avatar)
        await #expect(throws: MediaError.notFound) {
            try await anna.media.data(for: avatar)
        }
    }

    @Test func chatMediaAndGroupImagesFollowMembership() async throws {
        let anna = try await IntegrationUser.make("Fotografin", steps: 0)
        let ben = try await IntegrationUser.make("Freund", steps: 0)
        let outsider = try await IntegrationUser.make("Fremd", steps: 0)
        try await anna.befriend(ben)

        // Chat-Anhang: hochladen, als Bild senden, Gegenüber lädt herunter; Fremde weder lesen noch hochladen.
        let direct = try await anna.chat.openDirectConversation(with: ben.publicID)
        let attachment = try await anna.media.upload(Self.png, contentType: "image/png", to: .chat(conversationID: direct.id))
        #expect(attachment.bucket == .chatMedia)
        #expect(attachment.path.hasPrefix(direct.id.uuidString.lowercased() + "/"))
        let image = try await anna.chat.send(ChatMessageDraft(kind: .image, mediaPath: attachment.path), to: direct.id)
        #expect(image.kind == .image)
        #expect(image.media == attachment)
        let seenByBen = try #require(try await ben.chat.messages(in: direct.id, before: nil, limit: 10).first)
        #expect(seenByBen.media == attachment)
        #expect(try await ben.media.data(for: attachment) == Self.png)
        await #expect(throws: MediaError.self) {
            try await outsider.media.data(for: attachment)
        }
        await #expect(throws: MediaError.notAllowed) {
            try await outsider.media.upload(Self.png, contentType: "image/png", to: .chat(conversationID: direct.id))
        }
        // Als GIF senden geht nur mit einer GIF-Datei; fremde Anhänge lassen sich nicht senden.
        await #expect(throws: SocialError.invalidInput) {
            try await anna.chat.send(ChatMessageDraft(kind: .gif, mediaPath: attachment.path), to: direct.id)
        }
        await #expect(throws: SocialError.invalidInput) {
            try await ben.chat.send(ChatMessageDraft(kind: .image, mediaPath: attachment.path), to: direct.id)
        }
        // Profil teilen per öffentlicher ID.
        let shared = try await ben.chat.send(ChatMessageDraft(kind: .profile, sharedProfileID: anna.publicID), to: direct.id)
        #expect(shared.sharedProfile?.publicID == anna.publicID)

        // Nachricht löschen entfernt auch die Datei.
        try await anna.chat.deleteMessage(image.id)
        #expect(try await !ben.chat.messages(in: direct.id, before: nil, limit: 10).contains { $0.id == image.id })
        await #expect(throws: MediaError.notFound) {
            try await anna.media.data(for: attachment)
        }

        // Gruppenbild: nur die Eigentümerin lädt hoch und setzt es; Mitglieder und Eingeladene sehen es.
        let group = try await anna.social.createGroup(GroupDraft(name: "Fotogruppe", privacy: .code), timeZone: "Europe/Berlin")
        let groupImage = try await anna.media.upload(Self.png, contentType: "image/png", to: .groupImage(groupID: group.id))
        #expect(groupImage.path.hasPrefix(group.id.uuidString.lowercased() + "/"))
        #expect(try await anna.social.setGroupImage(group.id, path: groupImage.path).imagePath == groupImage.path)
        await #expect(throws: MediaError.self) {
            try await ben.media.data(for: groupImage)
        }
        _ = try await anna.social.invite(ben.publicID, to: group.id)
        #expect(try await ben.media.data(for: groupImage) == Self.png)
        #expect(try await ben.social.groupInvitations().first { $0.groupID == group.id }?.groupImagePath == groupImage.path)
        _ = try await ben.social.joinGroup(inviteCode: group.inviteCode)
        #expect(try await ben.media.data(for: groupImage) == Self.png)
        await #expect(throws: MediaError.notAllowed) {
            try await ben.media.upload(Self.png, contentType: "image/png", to: .groupImage(groupID: group.id))
        }
        await #expect(throws: SocialError.notAllowed) {
            try await ben.social.setGroupImage(group.id, path: nil)
        }
        // Pfad einer anderen Gruppe wird abgelehnt.
        let other = try await anna.social.createGroup(GroupDraft(name: "Zweite Gruppe"), timeZone: "Europe/Berlin")
        await #expect(throws: (any Error).self) {
            try await anna.social.setGroupImage(other.id, path: groupImage.path)
        }
        // Privatsphäre und Details ändern.
        let updated = try await anna.social.updateGroupDetails(group.id, name: "Fotogruppe 2", description: "Neu", kind: .club, privacy: .inviteOnly)
        #expect(updated.name == "Fotogruppe 2")
        #expect(updated.privacy == .inviteOnly)
        #expect(updated.imagePath == groupImage.path)
    }

    @Test func serverEnforcesBucketTypesAndSizes() async throws {
        let raw = try await RawSupabaseUser.make()
        let folder = raw.publicID.uuidString.lowercased()
        // Erlaubt: kleines PNG im eigenen Ordner.
        #expect(try await raw.upload(bucket: "avatars", path: "\(folder)/ok.png", contentType: "image/png", data: Self.png) == 200)
        // Abgelehnt: anderes Format, zu groß, fremder Ordner (unabhängig von den Prüfungen der App).
        #expect(try await raw.upload(bucket: "avatars", path: "\(folder)/text.png", contentType: "text/plain", data: Data("x".utf8)) != 200)
        let tooLarge = Data(count: 5 * 1024 * 1024 + 1)
        #expect(try await raw.upload(bucket: "avatars", path: "\(folder)/gross.jpg", contentType: "image/jpeg", data: tooLarge) != 200)
        let foreign = UUID().uuidString.lowercased()
        #expect(try await raw.upload(bucket: "avatars", path: "\(foreign)/fremd.png", contentType: "image/png", data: Self.png) != 200)
        #expect(try await raw.upload(bucket: "chat-media", path: "\(foreign)/fremd.png", contentType: "image/png", data: Self.png) != 200)
        #expect(try await raw.upload(bucket: "group-images", path: "\(foreign)/fremd.png", contentType: "image/png", data: Self.png) != 200)
    }

    /// Chat-Medien liest die hochladende Person immer (Vorschau vor dem Senden), alle anderen nur über eine sichtbare
    /// Nachricht – auch über signierte URLs (`createSignedURL` prüft dieselbe Storage-Policy).
    @Test func chatMediaIsOnlyReadableThroughVisibleMessages() async throws {
        let anna = try await RawSupabaseUser.make()
        let ben = try await RawSupabaseUser.make()
        let outsider = try await RawSupabaseUser.make()
        let request = try #require(try await anna.rpc("social_send_friend_request", ["p_public_id": ben.publicID.uuidString]) as? [String: Any])
        let requestID = try #require(request["request_id"] as? String)
        try await ben.rpc("social_respond_friend_request", ["p_request_id": requestID, "p_accept": true])
        let direct = try #require(try await anna.rpc("chat_open_direct", ["p_public_id": ben.publicID.uuidString]) as? [String: Any])
        let conversationID = try #require(direct["id"] as? String)
        let path = "\(conversationID)/\(UUID().uuidString.lowercased()).png"
        #expect(try await anna.upload(bucket: "chat-media", path: path, contentType: "image/png", data: Self.png) == 200)

        // Vor dem Senden: nur Anna (Vorschau), weder Ben noch Fremde.
        #expect(try await anna.downloadStatus(bucket: "chat-media", path: path) == 200)
        #expect(try await anna.signedURLStatus(bucket: "chat-media", path: path) == 200)
        #expect(try await ben.downloadStatus(bucket: "chat-media", path: path) != 200)
        #expect(try await ben.signedURLStatus(bucket: "chat-media", path: path) != 200)

        // Nach dem Senden: auch Ben, Fremde weiterhin nicht.
        let message = try #require(try await anna.rpc("chat_send", [
            "p_conversation_id": conversationID, "p_client_id": UUID().uuidString, "p_kind": "image", "p_media_path": path,
        ]) as? [String: Any])
        let messageID = try #require(message["id"] as? String)
        #expect(try await ben.downloadStatus(bucket: "chat-media", path: path) == 200)
        #expect(try await ben.signedURLStatus(bucket: "chat-media", path: path) == 200)
        #expect(try await outsider.downloadStatus(bucket: "chat-media", path: path) != 200)
        #expect(try await outsider.signedURLStatus(bucket: "chat-media", path: path) != 200)

        // Nach dem Löschen der Nachricht: nur noch Anna (sie löscht die Datei danach).
        try await anna.rpc("chat_delete_message", ["p_message_id": messageID])
        #expect(try await ben.downloadStatus(bucket: "chat-media", path: path) != 200)
        #expect(try await ben.signedURLStatus(bucket: "chat-media", path: path) != 200)
        #expect(try await anna.signedURLStatus(bucket: "chat-media", path: path) == 200)
    }

    @Test func exportFeedbackAndAccountDeletion() async throws {
        let leaving = try await IntegrationUser.make("Abschied", steps: 7_000)
        let friend = try await IntegrationUser.make("Bleibt", steps: 3_000)
        try await leaving.befriend(friend)

        let avatar = try await leaving.media.upload(Self.png, contentType: "image/png", to: .avatar)
        _ = try await leaving.profiles.updateAvatar(path: avatar.path, for: leaving.session.userID)
        let direct = try await leaving.chat.openDirectConversation(with: friend.publicID)
        let attachment = try await leaving.media.upload(Self.png, contentType: "image/png", to: .chat(conversationID: direct.id))
        _ = try await leaving.chat.send(ChatMessageDraft(kind: .image, mediaPath: attachment.path), to: direct.id)
        _ = try await leaving.chat.send(.text("Letzte Nachricht"), to: direct.id)
        let answer = try await friend.chat.send(.text("Schade!"), to: direct.id)
        let group = try await leaving.social.createGroup(GroupDraft(name: "Abschiedsrunde", privacy: .code), timeZone: "Europe/Berlin")
        let groupImage = try await leaving.media.upload(Self.png, contentType: "image/png", to: .groupImage(groupID: group.id))
        _ = try await leaving.social.setGroupImage(group.id, path: groupImage.path)
        _ = try await friend.social.joinGroup(inviteCode: group.inviteCode)

        try await leaving.account.submitFeedback(kind: .idea, message: "Mehr Abzeichen bitte!", appVersion: "1.0 (7)")
        await #expect(throws: AccountError.invalidInput) {
            try await leaving.account.submitFeedback(kind: .problem, message: "   ", appVersion: "1.0")
        }
        try await leaving.social.report(.message(id: answer.id), reason: .other, details: nil)

        // Auskunft: alle eigenen Serverdaten, nichts von anderen.
        let export = try await leaving.account.exportData()
        let json = try #require(try JSONSerialization.jsonObject(with: export) as? [String: Any])
        let profile = try #require(json["profile"] as? [String: Any])
        #expect(profile["username"] as? String == leaving.username)
        #expect(profile["avatar_path"] as? String == avatar.path)
        #expect((json["daily_activity"] as? [Any])?.count == 1)
        #expect((json["friends"] as? [Any])?.count == 1)
        #expect((json["groups"] as? [Any])?.count == 1)
        #expect((json["reports"] as? [Any])?.count == 1)
        #expect((json["feedback"] as? [[String: Any]])?.first?["message"] as? String == "Mehr Abzeichen bitte!")
        let bodies = try #require(json["chat_messages"] as? [[String: Any]]).compactMap { $0["body"] as? String }
        #expect(bodies == ["Letzte Nachricht"])
        #expect((json["media"] as? [Any])?.count == 3)

        // Eigene Dateien inkl. Bild der eigenen Gruppe.
        let own = Set(try await leaving.account.ownMedia())
        #expect(own == [avatar, attachment, groupImage])

        // Löschen: Dateien, Konto und verknüpfte Daten weg; Gruppe geht an das verbliebene Mitglied.
        try await leaving.account.deleteAccount()
        #expect(await leaving.backend.auth.restoreSession() == nil)
        #expect(try await friend.social.friends().isEmpty)
        let inherited = try await friend.social.group(group.id)
        #expect(inherited.isOwner)
        #expect(inherited.memberCount == 1)
        #expect(inherited.imagePath == nil)
        let remaining = try await friend.chat.messages(in: direct.id, before: nil, limit: 10)
        #expect(remaining.map(\.text) == ["Schade!"])
        #expect(try await friend.chat.conversations().first { $0.id == direct.id }?.canSend == false)
        await #expect(throws: MediaError.self) {
            try await friend.media.data(for: attachment)
        }
        await #expect(throws: MediaError.self) {
            try await friend.media.data(for: avatar)
        }
        #expect(try await friend.social.findProfile(username: leaving.username) == nil)
    }
}

// MARK: - Direkter HTTP-Zugriff

/// Nutzer, der ohne die App-Schicht direkt mit Auth, PostgREST und Storage spricht – um Grenzen zu prüfen, die die
/// App schon vorab abfängt (Format, Größe, Ordner).
private struct RawSupabaseUser {
    let configuration: BackendConfiguration
    let accessToken: String
    let publicID: UUID

    static func make() async throws -> RawSupabaseUser {
        let configuration = try #require(IntegrationEnvironment.configuration)
        // Anonyme Anmeldung: POST /auth/v1/signup ohne E-Mail und Telefonnummer.
        let signUp = try await send(
            configuration: configuration,
            path: "auth/v1/signup",
            method: "POST",
            token: nil,
            headers: ["Content-Type": "application/json"],
            body: Data("{}".utf8)
        )
        let session = try #require(try JSONSerialization.jsonObject(with: signUp.data) as? [String: Any])
        let token = try #require(session["access_token"] as? String)
        let user = try #require(session["user"] as? [String: Any])
        let userID = try #require(user["id"] as? String)

        let username = "raw_\(UUID().uuidString.prefix(8))".replacingOccurrences(of: "-", with: "")
        let profileBody = try JSONSerialization.data(withJSONObject: ["id": userID, "username": username, "display_name": "Raw"])
        let created = try await send(
            configuration: configuration,
            path: "rest/v1/profiles",
            method: "POST",
            token: token,
            headers: ["Content-Type": "application/json", "Prefer": "return=representation"],
            body: profileBody
        )
        let rows = try #require(try JSONSerialization.jsonObject(with: created.data) as? [[String: Any]])
        let publicIDText = try #require(rows.first?["public_id"] as? String)
        let publicID = try #require(UUID(uuidString: publicIDText))
        return RawSupabaseUser(configuration: configuration, accessToken: token, publicID: publicID)
    }

    /// HTTP-Status des Uploads (200 = gespeichert).
    func upload(bucket: String, path: String, contentType: String, data: Data) async throws -> Int {
        try await Self.send(
            configuration: configuration,
            path: "storage/v1/object/\(bucket)/\(path)",
            method: "POST",
            token: accessToken,
            headers: ["Content-Type": contentType, "x-upsert": "false"],
            body: data
        ).status
    }

    /// RPC über PostgREST aufrufen; liefert das JSON der Antwort (`nil` bei leerer Antwort, z. B. `void`).
    @discardableResult
    func rpc(_ name: String, _ parameters: [String: Any]) async throws -> Any? {
        let response = try await Self.send(
            configuration: configuration,
            path: "rest/v1/rpc/\(name)",
            method: "POST",
            token: accessToken,
            headers: ["Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: parameters)
        )
        #expect([200, 204].contains(response.status), "\(name): \(String(decoding: response.data, as: UTF8.self))")
        guard !response.data.isEmpty else { return nil }
        return try JSONSerialization.jsonObject(with: response.data, options: .fragmentsAllowed)
    }

    /// HTTP-Status beim Erstellen einer signierten URL (`createSignedURL`; 200 = erstellt).
    func signedURLStatus(bucket: String, path: String) async throws -> Int {
        try await Self.send(
            configuration: configuration,
            path: "storage/v1/object/sign/\(bucket)/\(path)",
            method: "POST",
            token: accessToken,
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"expiresIn":60}"#.utf8)
        ).status
    }

    /// HTTP-Status des angemeldeten Downloads (wie `MediaRepository.data(for:)`; 200 = gelesen).
    func downloadStatus(bucket: String, path: String) async throws -> Int {
        try await Self.send(
            configuration: configuration,
            path: "storage/v1/object/authenticated/\(bucket)/\(path)",
            method: "GET",
            token: accessToken,
            headers: [:],
            body: nil
        ).status
    }

    private static func send(
        configuration: BackendConfiguration,
        path: String,
        method: String,
        token: String?,
        headers: [String: String],
        body: Data?
    ) async throws -> (status: Int, data: Data) {
        var request = URLRequest(url: configuration.supabaseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}
