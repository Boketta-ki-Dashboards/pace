import Foundation
import PaceCore
import PaceTestSupport
@testable import ProfileFeature
import Testing

/// Konto & Profil: Namen ändern, Profilbild, Teilen, Kontoinformationen.
@MainActor
struct AccountSettingsTests {
    // MARK: Namen

    @Test func usernameRulesAreCheckedWhileTyping() {
        let env = ProfileSettingsEnvironment()
        let editor = env.viewModel.account.makeNameEditor()

        editor.username = "ab"
        #expect(editor.usernameStatus == .invalid(.tooShort))
        #expect(editor.usernameMessage == "Mindestens 3 Zeichen.")
        #expect(!editor.canSave)

        editor.username = "nik las"
        #expect(editor.usernameStatus == .invalid(.invalidCharacters))
        #expect(!editor.canSave)

        editor.username = "NIKLAS"
        #expect(editor.usernameStatus == .unchanged)
        #expect(editor.usernameMessage == nil)

        editor.username = ""
        #expect(editor.usernameStatus == .empty)
        #expect(!editor.canSave)
    }

    @Test func availabilityIsCheckedAndTakenNamesBlockSaving() async {
        let env = ProfileSettingsEnvironment()
        env.profiles.state.withLock { $0.takenUsernames = ["leon"] }
        let editor = env.viewModel.account.makeNameEditor()

        editor.username = "leon"
        #expect(editor.usernameStatus == .unchecked)
        await editor.checkUsernameAvailability()
        #expect(editor.usernameStatus == .taken)
        #expect(editor.usernameMessage == "Dieser Benutzername ist schon vergeben.")
        #expect(!editor.canSave)

        editor.username = "niklas_k"
        await editor.checkUsernameAvailability()
        #expect(editor.usernameStatus == .available)
        #expect(editor.canSave)
    }

    @Test func savingSendsOnlyChangedNamesAndUpdatesTheProfile() async {
        let env = ProfileSettingsEnvironment()
        let editor = env.viewModel.account.makeNameEditor()

        editor.displayName = "  Niklas   K. "
        #expect(editor.canSave)
        await editor.save()

        #expect(editor.didSave)
        #expect(editor.errorMessage == nil)
        let updates = env.profiles.state.withLock { $0.nameUpdates }
        #expect(updates.count == 1)
        #expect(updates.first?.username == nil)
        #expect(updates.first?.displayName == "Niklas K.")
        #expect(env.store.profile.displayName == "Niklas K.")
        #expect(env.viewModel.displayName == "Niklas K.")
        #expect(env.cache.load(for: Fixtures.userID)?.displayName == "Niklas K.")
    }

    @Test func usernameTakenOnTheServerIsShownAndRemembered() async {
        let env = ProfileSettingsEnvironment()
        env.profiles.state.withLock { $0.takenUsernames = ["marie"] }
        let editor = NameEditViewModel(store: env.store, profiles: nil, availabilityDebounce: .zero)

        editor.username = "Marie"
        #expect(editor.usernameStatus == .unchecked) // ohne Prüfung entscheidet der Server
        await editor.save()

        #expect(!editor.didSave)
        #expect(editor.errorMessage == ProfileError.usernameTaken.message)
        #expect(editor.usernameStatus == .taken)
        #expect(env.store.profile.username == "niklas")
    }

    @Test func networkErrorKeepsTheEditorOpen() async {
        let env = ProfileSettingsEnvironment()
        let editor = env.viewModel.account.makeNameEditor()
        env.profiles.state.withLock { $0.error = .network }

        editor.displayName = "Nik"
        await editor.save()

        #expect(!editor.didSave)
        #expect(editor.errorMessage == "Keine Verbindung. Prüfe deine Internetverbindung und versuche es erneut.")
    }

    @Test func nameMessagesExistInEnglishAndRussian() {
        let env = ProfileSettingsEnvironment()
        let editor = env.viewModel.account.makeNameEditor()
        editor.username = "ab"

        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(editor.usernameMessage == "At least 3 characters.")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(editor.usernameMessage == "Минимум 3 символа.")
            #expect(ProfileError.usernameTaken.message == "Это имя пользователя уже занято.")
        }
    }

    // MARK: Profilbild

    @Test func uploadingAnAvatarSetsItAndDeletesTheOldImage() async throws {
        var profile = Fixtures.profile()
        profile.avatarPath = "\(Fixtures.publicUserID.uuidString.lowercased())/old.jpg"
        let env = ProfileSettingsEnvironment(profile: profile)
        let account = env.viewModel.account
        #expect(account.supportsAvatar)

        let uploaded = try #require(await account.uploadAvatar(jpegData: Data(repeating: 1, count: 2_000)))

        #expect(account.avatarError == nil)
        #expect(account.avatarActivity == .idle)
        #expect(env.store.profile.avatarPath == uploaded.path)
        #expect(env.viewModel.avatar == uploaded)
        #expect(env.profiles.state.withLock { $0.avatarUpdates } == [uploaded.path])
        #expect(env.media.state.withLock { $0.deleted } == [MediaReference(bucket: .avatars, path: profile.avatarPath ?? "")])
        #expect(env.log.calls == ["media.upload", "media.delete:\(profile.avatarPath ?? "")"])
    }

    @Test func tooLargeImagesAreRejectedBeforeUploading() async {
        let env = ProfileSettingsEnvironment()

        let result = await env.viewModel.account.uploadAvatar(jpegData: Data(count: 5 * 1024 * 1024 + 1))

        #expect(result == nil)
        #expect(env.viewModel.account.avatarError == "Das Bild ist zu groß. Erlaubt sind höchstens 5 MB.")
        #expect(env.media.state.withLock { $0.uploads }.isEmpty)
    }

    @Test func failedProfileUpdateRemovesTheNewUpload() async {
        let env = ProfileSettingsEnvironment()
        env.profiles.state.withLock { $0.error = .network }

        let result = await env.viewModel.account.uploadAvatar(jpegData: Data(repeating: 1, count: 100))

        #expect(result == nil)
        #expect(env.viewModel.account.avatarError == ProfileError.network.message)
        #expect(env.store.profile.avatarPath == nil)
        let media = env.media.state.withLock { $0 }
        #expect(media.uploads.count == 1)
        #expect(media.deleted.count == 1)
        #expect(media.files.isEmpty)
    }

    @Test func failedUploadShowsAnError() async {
        let env = ProfileSettingsEnvironment(media: MediaRepositoryStub { $0.error = .unavailable })

        let result = await env.viewModel.account.uploadAvatar(jpegData: Data(repeating: 1, count: 100))

        #expect(result == nil)
        #expect(env.viewModel.account.avatarError == "Profilbilder sind auf dem Server noch nicht eingerichtet.")
        #expect(env.profiles.state.withLock { $0.avatarUpdates }.isEmpty)
    }

    @Test func removingTheAvatarClearsItAndDeletesTheFile() async {
        var profile = Fixtures.profile()
        profile.avatarPath = "\(Fixtures.publicUserID.uuidString.lowercased())/old.jpg"
        let env = ProfileSettingsEnvironment(profile: profile)

        await env.viewModel.account.removeAvatar()

        #expect(env.store.profile.avatarPath == nil)
        #expect(env.profiles.state.withLock { $0.avatarUpdates } == [nil])
        #expect(env.media.state.withLock { $0.deleted }.map(\.path) == [profile.avatarPath ?? ""])
    }

    @Test func withoutMediaBackendAvatarsAreHonestlyUnavailable() async {
        let env = ProfileSettingsEnvironment(withBackend: false)
        let account = env.viewModel.account

        #expect(!account.supportsAvatar)
        #expect(account.avatarHint.contains("noch nicht verfügbar"))
        #expect(await account.uploadAvatar(jpegData: Data(count: 10)) == nil)
        #expect(env.profiles.state.withLock { $0.avatarUpdates }.isEmpty)
    }

    // MARK: Teilen und Konto

    @Test func shareLinkIdentifiesTheProfile() {
        let env = ProfileSettingsEnvironment()
        let share = env.viewModel.share

        #expect(share.url.absoluteString == "pace://u/niklas")
        #expect(PaceLink(url: share.url) == .profile(username: "niklas"))
        #expect(share.message == "Füge mich in Pace hinzu – mein Benutzername: @niklas")
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(share.message == "Add me on Pace – my username: @niklas")
        }
    }

    @Test func accountInformationDescribesTheDeviceBoundAccount() async {
        let env = ProfileSettingsEnvironment()
        let account = env.viewModel.account

        await account.loadSession()

        #expect(account.session?.isAnonymous == true)
        #expect(account.accountKind == "Ohne Anmeldung, an dieses iPhone gebunden")
        #expect(account.memberSince == "1. Oktober 2026")
        #expect(account.publicID == Fixtures.publicUserID.uuidString.lowercased())
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(account.memberSince == "October 1, 2026")
            #expect(account.accountKind == "No sign-in, tied to this iPhone")
        }
    }
}
