import Foundation
import PaceCore
import PaceTestSupport
@testable import ProfileFeature
import Testing

/// Datenschutz & Daten: Export, Konto löschen (Reihenfolge, Fehler) und Rückmeldungen.
@MainActor
struct DataPrivacyTests {
    private static let avatar = MediaReference(bucket: .avatars, path: "me/avatar.jpg")
    private static let chatImage = MediaReference(bucket: .chatMedia, path: "c1/image")

    // MARK: Export

    @Test func exportCombinesServerAndDeviceDataInAFile() async throws {
        let env = ProfileSettingsEnvironment()
        defer { env.cleanUp() }
        let data = env.viewModel.dataPrivacy

        await data.export()

        guard case .ready(let file) = data.exportState else {
            Issue.record("Expected a ready export, got \(data.exportState)")
            return
        }
        #expect(file.lastPathComponent == "pace-export-2026-10-20.json")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(json["format"] as? String == "pace-export")
        #expect(json["appVersion"] as? String == "0.1.0 (1)")
        let server = try #require(json["server"] as? [String: Any])
        #expect((server["profile"] as? [String: Any])?["username"] as? String == "niklas")
        let device = try #require(json["device"] as? [String: Any])
        #expect((device["settings"] as? [String: Any])?["appearance"] as? String == "dark")
        #expect((device["streakRecord"] as? [String: Any])?["days"] as? Int == 12)

        data.discardExport()
        #expect(data.exportState == .idle)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func failedExportShowsTheReason() async {
        let env = ProfileSettingsEnvironment(account: AccountRepositoryStub { $0.exportError = .network })
        defer { env.cleanUp() }

        await env.viewModel.dataPrivacy.export()

        #expect(env.viewModel.dataPrivacy.exportState == .failed(AccountError.network.message))
    }

    @Test func invalidServerDataIsReportedAsFailure() async {
        let env = ProfileSettingsEnvironment(account: AccountRepositoryStub { $0.exportJSON = Data("kein json".utf8) })
        defer { env.cleanUp() }

        await env.viewModel.dataPrivacy.export()

        #expect(env.viewModel.dataPrivacy.exportState == .failed("Der Export konnte nicht erstellt werden. Bitte versuche es erneut."))
    }

    // MARK: Konto löschen

    @Test func deletionNeedsTheUsernameAsConfirmation() async {
        let env = ProfileSettingsEnvironment()
        let data = env.viewModel.dataPrivacy
        #expect(data.requiredConfirmation == "niklas")
        #expect(!data.canDelete)

        data.confirmationText = "nikla"
        await data.deleteAccount()
        #expect(env.account.state.withLock { $0.deleteCalls } == 0)
        #expect(env.log.calls.isEmpty)

        data.confirmationText = " Niklas "
        #expect(data.isConfirmationValid)
        #expect(data.canDelete)
    }

    @Test func deletionRemovesMediaThenAccountThenLocalData() async {
        let account = AccountRepositoryStub { $0.media = [Self.avatar, Self.chatImage] }
        let notifications = NotificationSchedulerStub { $0.authorization = .authorized }
        let env = ProfileSettingsEnvironment(
            preferences: AppPreferences(appearance: .dark, language: .fixed(.english)),
            notifications: notifications,
            account: account
        )
        let data = env.viewModel.dataPrivacy
        data.confirmationText = "niklas"
        let deleted = Locked(0)
        data.onAccountDeleted = { deleted.withLock { $0 += 1 } }

        await data.deleteAccount()

        #expect(env.log.calls == [
            "account.ownMedia",
            "media.delete:me/avatar.jpg",
            "media.delete:c1/image",
            "account.delete",
            "notifications.cancel",
            "local.erase",
            "auth.signOut",
        ])
        #expect(deleted.current == 1)
        #expect(data.deletionStep == .finished)
        #expect(data.deletionError == nil)
        #expect(data.confirmationText.isEmpty)
        #expect(env.localData.erasures == 1)
        #expect(env.localData.exportSections().isEmpty)
        // Einstellungen zurückgesetzt (Darstellung automatisch, Sprache wie iPhone).
        #expect(env.settings.preferences == AppPreferences())
        #expect(env.appliedLanguages.current.last == .german)
        #expect(env.auth.state.withLock { $0.storedSession } == nil)
    }

    @Test func serverFailureKeepsEverythingOnThisPhone() async {
        let env = ProfileSettingsEnvironment(account: AccountRepositoryStub { state in
            state.media = [Self.avatar]
            state.deleteError = .network
        })
        let data = env.viewModel.dataPrivacy
        data.confirmationText = "niklas"
        let deleted = Locked(0)
        data.onAccountDeleted = { deleted.withLock { $0 += 1 } }

        await data.deleteAccount()

        #expect(env.log.calls == ["account.ownMedia", "media.delete:me/avatar.jpg", "account.delete"])
        #expect(deleted.current == 0)
        #expect(data.deletionStep == .idle)
        #expect(data.deletionError == AccountError.network.message + " Dein Konto wurde nicht gelöscht.")
        #expect(env.localData.erasures == 0)
        #expect(env.auth.state.withLock { $0.signOutCalls } == 0)
        #expect(env.settings.language == .fixed(.german))
        #expect(data.canDelete) // erneut versuchen
    }

    @Test func failedMediaDeletionStopsBeforeTheAccountIsDeleted() async {
        let env = ProfileSettingsEnvironment(
            account: AccountRepositoryStub { $0.media = [Self.avatar] },
            media: MediaRepositoryStub { $0.error = .network }
        )
        let data = env.viewModel.dataPrivacy
        data.confirmationText = "niklas"

        await data.deleteAccount()

        #expect(env.log.calls == ["account.ownMedia", "media.delete:me/avatar.jpg"])
        #expect(env.account.state.withLock { $0.deleteCalls } == 0)
        #expect(data.deletionError?.contains("Dein Konto besteht weiter") == true)
        #expect(env.localData.erasures == 0)
    }

    @Test func missingFilesAndMissingStorageDoNotBlockDeletion() async {
        let missingFile = ProfileSettingsEnvironment(
            account: AccountRepositoryStub { $0.media = [Self.avatar] },
            media: MediaRepositoryStub { $0.error = .notFound }
        )
        missingFile.viewModel.dataPrivacy.confirmationText = "niklas"
        await missingFile.viewModel.dataPrivacy.deleteAccount()
        #expect(missingFile.account.state.withLock { $0.deleteCalls } == 1)
        #expect(missingFile.viewModel.dataPrivacy.deletionStep == .finished)

        let noStorage = ProfileSettingsEnvironment(account: AccountRepositoryStub { $0.ownMediaError = .unavailable })
        noStorage.viewModel.dataPrivacy.confirmationText = "niklas"
        await noStorage.viewModel.dataPrivacy.deleteAccount()
        #expect(noStorage.account.state.withLock { $0.deleteCalls } == 1)
        #expect(noStorage.localData.erasures == 1)
    }

    @Test func withoutBackendExportAndDeletionAreUnavailable() async {
        let env = ProfileSettingsEnvironment(withBackend: false)
        let data = env.viewModel.dataPrivacy
        data.confirmationText = "niklas"

        await data.export()
        await data.deleteAccount()

        #expect(!data.isAvailable)
        #expect(!data.canDelete)
        #expect(data.exportState == .idle)
        #expect(env.localData.erasures == 0)
    }

    @Test func deletionTextsAreLocalized() {
        let env = ProfileSettingsEnvironment()
        let data = env.viewModel.dataPrivacy
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(data.confirmationPrompt == "To confirm, enter your username “niklas”.")
            #expect(data.deletionConsequences.count == 5)
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(data.confirmationPrompt == "Для подтверждения введи своё имя пользователя «niklas».")
        }
    }

    // MARK: Rückmeldung

    @Test func feedbackIsValidatedAndSent() async {
        let env = ProfileSettingsEnvironment()
        let feedback = env.viewModel.makeFeedback(.problem)
        #expect(feedback.kind.title == "Problem melden")
        #expect(!feedback.canSend)

        feedback.message = "kurz"
        #expect(feedback.validationMessage == "Bitte beschreibe es etwas genauer (mindestens 10 Zeichen).")
        #expect(!feedback.canSend)

        feedback.message = "  Die Statistik lädt nicht.  "
        #expect(feedback.validationMessage == nil)
        #expect(feedback.counterText == "25/2.000")
        await feedback.send()

        #expect(feedback.state == .sent)
        #expect(feedback.message.isEmpty)
        let sent = env.account.state.withLock { $0.feedback }
        #expect(sent.count == 1)
        #expect(sent.first?.0 == .problem)
        #expect(sent.first?.1 == "Die Statistik lädt nicht.")
        #expect(sent.first?.2 == "0.1.0 (1)")
    }

    @Test func tooLongFeedbackCannotBeSent() {
        let env = ProfileSettingsEnvironment()
        let feedback = env.viewModel.makeFeedback(.idea)

        feedback.message = String(repeating: "a", count: FeedbackRules.maximumLength + 1)

        #expect(feedback.isTooLong)
        #expect(!feedback.canSend)
        #expect(feedback.validationMessage == "Höchstens 2.000 Zeichen.")
    }

    @Test func failedFeedbackKeepsTheTextAndCanBeRetried() async {
        let env = ProfileSettingsEnvironment(account: AccountRepositoryStub { $0.feedbackError = .rateLimited })
        let feedback = env.viewModel.makeFeedback(.idea)
        feedback.message = "Bitte einen Wochenvergleich."

        await feedback.send()

        #expect(feedback.state == .failed(AccountError.rateLimited.message))
        #expect(feedback.message == "Bitte einen Wochenvergleich.")
        feedback.resume()
        #expect(feedback.state == .editing)
        #expect(feedback.canSend)
    }

    @Test func feedbackWithoutBackendIsUnavailable() async {
        let env = ProfileSettingsEnvironment(withBackend: false)
        let feedback = env.viewModel.makeFeedback(.problem)
        feedback.message = "Etwas funktioniert nicht."

        await feedback.send()

        #expect(!feedback.isAvailable)
        #expect(!feedback.canSend)
        #expect(feedback.state == .editing)
    }
}
