import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PaceBackend
import PaceCore
import Testing

/// Supabase Storage (Migration 20261019100300) und Datenschutz-RPCs (Migration 20261019100400).
struct MediaRepositoryTests {
    private static let ownPublicID = "9b2d0c1e-5f3a-4b7c-8d9e-0a1b2c3d4e5f"
    private static let groupID = UUID(uuidString: "CCCCCCCC-0000-4000-8000-000000000001")!

    @Test func avatarUploadGoesIntoTheOwnFolderWithARandomName() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("GET", "/rest/v1/profiles", .json(#"{"public_id":"\#(Self.ownPublicID)"}"#))
        harness.stub("POST", pathPrefix: "/storage/v1/object/avatars/", .json(#"{"Key":"avatars/x.jpg","Id":"5d8f6a0e-0000-4000-8000-000000000001"}"#))

        let reference = try await harness.backend.media.upload(Data([0xFF, 0xD8, 0xFF]), contentType: "image/JPEG", to: .avatar)

        #expect(reference.bucket == .avatars)
        #expect(reference.path.range(of: #"^\#(Self.ownPublicID)/[0-9a-f-]{36}\.jpg$"#, options: .regularExpression) != nil)
        let upload = try #require(harness.requests("POST", pathPrefix: "/storage/v1/object/avatars/").last)
        #expect(upload.path == "/storage/v1/object/avatars/\(reference.path)")
        #expect(upload.header("Authorization") == "Bearer \(BackendTestHarness.accessToken)")
        #expect(upload.header("apikey") == BackendTestHarness.publishableKey)
        #expect(upload.header("x-upsert") == "false")
        let body = String(decoding: try #require(upload.body), as: UTF8.self)
        #expect(body.contains("image/jpeg"))
        #expect(harness.lastRequest("GET", "/rest/v1/profiles")?.query("select") == "public_id")

        // Die öffentliche ID wird nur einmal gelesen.
        _ = try await harness.backend.media.upload(Data([1]), contentType: "image/png", to: .avatar)
        #expect(harness.requests("GET", pathPrefix: "/rest/v1/profiles").count == 1)
    }

    @Test func groupAndChatUploadsUseTheirFolders() async throws {
        let harness = BackendTestHarness()
        let conversationID = UUID(uuidString: "DDDDDDDD-0000-4000-8000-000000000001")!
        harness.stub("POST", pathPrefix: "/storage/v1/object/", .json(#"{"Key":"k","Id":"5d8f6a0e-0000-4000-8000-000000000001"}"#))

        let group = try await harness.backend.media.upload(Data([1]), contentType: "image/webp", to: .groupImage(groupID: Self.groupID))
        let chat = try await harness.backend.media.upload(Data([1]), contentType: "image/gif", to: .chat(conversationID: conversationID))

        #expect(group.bucket == .groupImages)
        #expect(group.path.hasPrefix("cccccccc-0000-4000-8000-000000000001/") && group.path.hasSuffix(".webp"))
        #expect(chat.bucket == .chatMedia)
        #expect(chat.path.hasPrefix("dddddddd-0000-4000-8000-000000000001/") && chat.path.hasSuffix(".gif"))
    }

    @Test func formatAndSizeAreCheckedBeforeUploading() async {
        let harness = BackendTestHarness()

        await #expect(throws: MediaError.unsupportedType) {
            try await harness.backend.media.upload(Data([1]), contentType: "image/tiff", to: .chat(conversationID: Self.groupID))
        }
        await #expect(throws: MediaError.tooLarge) {
            try await harness.backend.media.upload(
                Data(count: 5 * 1024 * 1024 + 1), contentType: "image/png", to: .groupImage(groupID: Self.groupID)
            )
        }
        #expect(harness.recorded.isEmpty)
    }

    @Test func avatarUploadWithoutSessionIsNotAllowed() async {
        let harness = BackendTestHarness()

        await #expect(throws: MediaError.notAllowed) {
            try await harness.backend.media.upload(Data([1]), contentType: "image/png", to: .avatar)
        }
    }

    @Test func downloadAndDelete() async throws {
        let harness = BackendTestHarness()
        let reference = MediaReference(bucket: .groupImages, path: "cccccccc-0000-4000-8000-000000000001/titel.png")
        harness.stub("GET", "/storage/v1/object/group-images/\(reference.path)", .response(status: 200, headers: ["Content-Type": "image/png"], body: Data([7, 8, 9])))
        harness.stub("DELETE", "/storage/v1/object/group-images", .json(#"[{"name":"\#(reference.path)"}]"#))

        #expect(try await harness.backend.media.data(for: reference) == Data([7, 8, 9]))
        try await harness.backend.media.delete(reference)
        #expect(try harness.lastRequest("DELETE", "/storage/v1/object/group-images")?.jsonBody()
            == .object(["prefixes": .array([.string(reference.path)])]))

        // Storage meldet Erfolg ohne gelöschte Datei, wenn sie fehlt oder fremd ist.
        harness.stub("DELETE", "/storage/v1/object/group-images", .json("[]"))
        await #expect(throws: MediaError.notFound) {
            try await harness.backend.media.delete(reference)
        }
    }

    struct StorageErrorCase: Sendable, CustomTestStringConvertible {
        let status: Int
        let body: String
        let expected: MediaError
        var testDescription: String { "\(status) \(expected)" }
    }

    @Test(arguments: [
        StorageErrorCase(status: 400, body: #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"#, expected: .notAllowed),
        StorageErrorCase(status: 413, body: #"{"statusCode":"413","error":"Payload too large","message":"The object exceeded the maximum allowed size"}"#, expected: .tooLarge),
        StorageErrorCase(status: 400, body: #"{"statusCode":"415","error":"invalid_mime_type","message":"mime type image/tiff is not supported"}"#, expected: .unsupportedType),
        StorageErrorCase(status: 400, body: #"{"statusCode":"404","error":"Bucket not found","message":"Bucket not found"}"#, expected: .unavailable),
        StorageErrorCase(status: 400, body: #"{"statusCode":"404","error":"not_found","message":"Object not found"}"#, expected: .notFound),
    ])
    func storageErrorsAreMapped(_ testCase: StorageErrorCase) async {
        let harness = BackendTestHarness()
        harness.stub("GET", pathPrefix: "/storage/v1/object/", .json(testCase.body, status: testCase.status))

        await #expect(throws: testCase.expected) {
            try await harness.backend.media.data(for: MediaReference(bucket: .chatMedia, path: "a/b.jpg"))
        }
    }

    @Test func networkErrorsAreMapped() async {
        let harness = BackendTestHarness()
        harness.stub("GET", pathPrefix: "/storage/v1/object/", .failure(URLError(.notConnectedToInternet)))

        await #expect(throws: MediaError.network) {
            try await harness.backend.media.data(for: MediaReference(bucket: .avatars, path: "a/b.jpg"))
        }
    }
}

struct AccountRepositoryTests {
    @Test func exportIsPrettyPrintedJSON() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/account_export", .json(#"{"profile":{"username":"niklas"},"exported_at":"2026-10-19T10:00:00Z"}"#))

        let data = try await harness.backend.account.exportData()

        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\n"))
        let exportedAt = try #require(text.range(of: "exported_at"))
        let profile = try #require(text.range(of: "profile"))
        #expect(exportedAt.lowerBound < profile.lowerBound)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["profile"] as? [String: Any])?["username"] as? String == "niklas")
    }

    @Test func ownMediaSkipsUnknownBuckets() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/account_own_media", .json(#"""
        [{"bucket":"avatars","path":"p/a.jpg"},{"bucket":"videos","path":"x/y.mp4"},{"bucket":"chat-media","path":"c/b.gif"}]
        """#))

        let media = try await harness.backend.account.ownMedia()

        #expect(media == [MediaReference(bucket: .avatars, path: "p/a.jpg"), MediaReference(bucket: .chatMedia, path: "c/b.gif")])
    }

    @Test func deleteAccountRemovesFilesThenTheAccountAndSignsOut() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("POST", "/rest/v1/rpc/account_own_media", .json(#"""
        [{"bucket":"avatars","path":"p/a.jpg"},{"bucket":"chat-media","path":"c/1.jpg"},{"bucket":"chat-media","path":"c/2.gif"}]
        """#))
        harness.stub("DELETE", "/storage/v1/object/avatars", .json(#"[{"name":"p/a.jpg"}]"#))
        harness.stub("DELETE", "/storage/v1/object/chat-media", .json(#"[{"name":"c/1.jpg"},{"name":"c/2.gif"}]"#))
        harness.stub("POST", "/rest/v1/rpc/account_delete", .json("null"))

        try await harness.backend.account.deleteAccount()

        #expect(try harness.lastRequest("DELETE", "/storage/v1/object/chat-media")?.jsonBody()
            == .object(["prefixes": .array([.string("c/1.jpg"), .string("c/2.gif")])]))
        let order = harness.recorded.map(\.path).filter { $0.hasPrefix("/storage") || $0.hasSuffix("account_delete") }
        #expect(order.last == "/rest/v1/rpc/account_delete")
        #expect(await harness.backend.auth.restoreSession() == nil)
    }

    @Test func deleteAccountStopsWhenFilesCannotBeRemoved() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("POST", "/rest/v1/rpc/account_own_media", .json(#"[{"bucket":"avatars","path":"p/a.jpg"}]"#))
        harness.stub("DELETE", "/storage/v1/object/avatars", .failure(URLError(.networkConnectionLost)))

        await #expect(throws: AccountError.network) {
            try await harness.backend.account.deleteAccount()
        }
        #expect(harness.lastRequest("POST", "/rest/v1/rpc/account_delete") == nil)
        #expect(await harness.backend.auth.restoreSession() != nil)
    }

    @Test func feedbackIsTrimmedAndTheVersionSanitized() async throws {
        let harness = BackendTestHarness()
        harness.stub("POST", "/rest/v1/rpc/submit_feedback", .json("null"))

        try await harness.backend.account.submitFeedback(kind: .idea, message: "  Mehr Widgets  ", appVersion: "– (–)")
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/submit_feedback")?.jsonBody() == .object([
            "p_kind": .string("idea"), "p_message": .string("Mehr Widgets"), "p_app_version": .string("()"),
        ]))

        try await harness.backend.account.submitFeedback(kind: .problem, message: "Absturz", appVersion: "1.4 (12)")
        #expect(try harness.lastRequest("POST", "/rest/v1/rpc/submit_feedback")?.jsonBody()["p_app_version"] == .string("1.4 (12)"))
    }

    @Test func feedbackValidationAndServerErrors() async {
        let harness = BackendTestHarness()

        await #expect(throws: AccountError.invalidInput) {
            try await harness.backend.account.submitFeedback(kind: .problem, message: "   ", appVersion: "1.0")
        }
        await #expect(throws: AccountError.invalidInput) {
            try await harness.backend.account.submitFeedback(kind: .problem, message: String(repeating: "x", count: 2_001), appVersion: "1.0")
        }
        #expect(harness.recorded.isEmpty)

        harness.stub("POST", "/rest/v1/rpc/submit_feedback", .postgrestError(status: 400, code: "P0001", message: "rate_limited"))
        await #expect(throws: AccountError.rateLimited) {
            try await harness.backend.account.submitFeedback(kind: .problem, message: "Text", appVersion: "1.0")
        }
        harness.stub("POST", "/rest/v1/rpc/account_export", .postgrestError(
            status: 404, code: "PGRST202", message: "Could not find the function public.account_export without parameters"
        ))
        await #expect(throws: AccountError.unavailable) {
            try await harness.backend.account.exportData()
        }
    }
}
