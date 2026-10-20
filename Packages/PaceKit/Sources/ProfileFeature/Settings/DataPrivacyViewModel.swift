import Foundation
import Observation
import PaceCore

/// „Datenschutz & Daten“: Datenexport und endgültiges Löschen des Kontos.
///
/// Löschen läuft in einer festen Reihenfolge, damit nichts halb gelöscht zurückbleibt:
/// 1. eigene Dateien ermitteln (`AccountRepository.ownMedia()`) und über `MediaRepository.delete` entfernen,
/// 2. das Konto auf dem Server löschen (`deleteAccount()` – Profil, Tageswerte, Freundschaften, Gruppen, Chats),
/// 3. erst danach die Daten auf diesem iPhone: geplante Erinnerungen, Einstellungen, lokale Daten, Anmeldung.
///
/// Schlägt ein Schritt auf dem Server fehl, bleibt auf dem iPhone alles erhalten und das Konto besteht weiter.
@MainActor
@Observable
public final class DataPrivacyViewModel {
    public enum ExportState: Equatable, Sendable {
        case idle
        case exporting
        /// Fertige Datei zum Teilen bzw. Sichern.
        case ready(URL)
        case failed(String)
    }

    public enum DeletionStep: Equatable, Sendable {
        case idle
        case deletingMedia
        case deletingAccount
        case cleaningUp
        /// Abgeschlossen; die App kehrt zum Start zurück.
        case finished
    }

    public private(set) var exportState: ExportState = .idle
    public private(set) var deletionStep: DeletionStep = .idle
    public private(set) var deletionError: String?
    /// Eingabe zur Bestätigung (der eigene Benutzername).
    public var confirmationText = ""

    @ObservationIgnored private let store: ProfileStore
    @ObservationIgnored private let account: (any AccountRepository)?
    @ObservationIgnored private let media: (any MediaRepository)?
    @ObservationIgnored private let auth: (any AuthProviding)?
    @ObservationIgnored private let localData: any LocalAccountDataStoring
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let notifications: NotificationSettingsViewModel
    @ObservationIgnored private let appVersion: String
    @ObservationIgnored private let exportDirectory: URL
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Wird nach dem vollständigen Löschen aufgerufen (App-Rahmen: zurück zum Start).
    @ObservationIgnored var onAccountDeleted: (@MainActor () -> Void)?

    public init(
        store: ProfileStore,
        account: (any AccountRepository)?,
        media: (any MediaRepository)?,
        auth: (any AuthProviding)?,
        localData: any LocalAccountDataStoring,
        settings: AppSettings,
        notifications: NotificationSettingsViewModel,
        appVersion: String,
        exportDirectory: URL = FileManager.default.temporaryDirectory,
        now: @escaping @Sendable () -> Date = Date.init,
        onAccountDeleted: (@MainActor () -> Void)? = nil
    ) {
        self.store = store
        self.account = account
        self.media = media
        self.auth = auth
        self.localData = localData
        self.settings = settings
        self.notifications = notifications
        self.appVersion = appVersion
        self.exportDirectory = exportDirectory
        self.now = now
        self.onAccountDeleted = onAccountDeleted
    }

    /// Export und Löschen brauchen die Konto-Funktionen auf dem Server.
    public var isAvailable: Bool { account != nil }

    public var unavailableText: String {
        PaceLocalization.text(
            de: "Datenexport und Kontolöschung sind ohne Verbindung zum Pace-Server nicht verfügbar.",
            en: "Data export and account deletion aren't available without a connection to the Pace server.",
            ru: "Экспорт данных и удаление аккаунта недоступны без подключения к серверу Pace."
        )
    }

    // MARK: Export

    public var isExporting: Bool { exportState == .exporting }

    /// Holt die Daten vom Server, ergänzt die lokalen Daten und schreibt eine JSON-Datei.
    public func export() async {
        guard let account, !isExporting else { return }
        exportState = .exporting
        do {
            let server = try await account.exportData()
            let date = now()
            let document = try AccountExport.document(
                server: server,
                device: localData.exportSections(),
                exportedAt: date,
                appVersion: appVersion
            )
            let directory = exportDirectory.appendingPathComponent("pace-export", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(AccountExport.fileName(for: date))
            try document.write(to: file, options: .atomic)
            exportState = .ready(file)
        } catch {
            exportState = .failed(Self.exportMessage(for: error))
        }
    }

    /// Nach dem Teilen bzw. beim Verlassen der Seite: Datei entfernen, damit keine Kopie im Zwischenspeicher bleibt.
    public func discardExport() {
        if case .ready(let file) = exportState {
            try? FileManager.default.removeItem(at: file)
        }
        exportState = .idle
    }

    static func exportMessage(for error: Error) -> String {
        switch error as? AccountError {
        case .some(.unexpected), .none:
            PaceLocalization.text(
                de: "Der Export konnte nicht erstellt werden. Bitte versuche es erneut.",
                en: "The export couldn't be created. Please try again.",
                ru: "Не удалось создать экспорт. Попробуй снова."
            )
        case .some(let accountError):
            accountError.message
        }
    }

    // MARK: Konto löschen

    /// Benutzername, den man zur Bestätigung eintippt.
    public var requiredConfirmation: String { store.profile.username }

    public var isConfirmationValid: Bool {
        UsernameRules.normalized(confirmationText).lowercased() == store.profile.username.lowercased()
    }

    public var isDeleting: Bool {
        switch deletionStep {
        case .idle, .finished: false
        case .deletingMedia, .deletingAccount, .cleaningUp: true
        }
    }

    public var canDelete: Bool {
        isAvailable && isConfirmationValid && !isDeleting && deletionStep != .finished
    }

    /// Fortschritt für die Anzeige während des Löschens.
    public var deletionStatusText: String? {
        switch deletionStep {
        case .idle, .finished:
            nil
        case .deletingMedia:
            PaceLocalization.text(de: "Bilder werden gelöscht …", en: "Deleting images …", ru: "Удаляем изображения …")
        case .deletingAccount:
            PaceLocalization.text(de: "Konto wird gelöscht …", en: "Deleting account …", ru: "Удаляем аккаунт …")
        case .cleaningUp:
            PaceLocalization.text(
                de: "Daten auf diesem iPhone werden entfernt …",
                en: "Removing data from this iPhone …",
                ru: "Удаляем данные с этого iPhone …"
            )
        }
    }

    /// Löscht das Konto endgültig (nur nach gültiger Bestätigung).
    public func deleteAccount() async {
        guard let account, canDelete else { return }
        deletionError = nil

        // 1. Eigene Dateien (Profilbild, Chat-Anhänge, Bilder eigener Gruppen).
        deletionStep = .deletingMedia
        do {
            try await deleteOwnMedia(account: account)
        } catch {
            deletionStep = .idle
            deletionError = PaceLocalization.text(
                de: "Deine Bilder konnten nicht gelöscht werden. Dein Konto besteht weiter – bitte versuche es erneut.",
                en: "Your images couldn't be deleted. Your account still exists – please try again.",
                ru: "Не удалось удалить твои изображения. Аккаунт по-прежнему существует – попробуй снова."
            )
            return
        }

        // 2. Konto auf dem Server.
        deletionStep = .deletingAccount
        do {
            try await account.deleteAccount()
        } catch {
            deletionStep = .idle
            deletionError = Self.deletionMessage(for: error)
            return
        }

        // 3. Daten auf diesem iPhone – erst, wenn der Server das Konto gelöscht hat.
        deletionStep = .cleaningUp
        await notifications.cancelAll()
        settings.reset()
        localData.eraseAll()
        await auth?.signOut()
        deletionStep = .finished
        confirmationText = ""
        onAccountDeleted?()
    }

    private func deleteOwnMedia(account: any AccountRepository) async throws {
        let references: [MediaReference]
        do {
            references = try await account.ownMedia()
        } catch AccountError.unavailable {
            // Ohne Bilder-Speicher auf dem Server gibt es keine eigenen Dateien.
            return
        }
        guard let media else { return }
        for reference in references {
            do {
                try await media.delete(reference)
            } catch MediaError.notFound {
                continue
            }
        }
    }

    static func deletionMessage(for error: Error) -> String {
        switch error as? AccountError {
        case .some(.unexpected), .some(.invalidInput), .none:
            PaceLocalization.text(
                de: "Dein Konto konnte nicht gelöscht werden. Es besteht weiter – bitte versuche es erneut.",
                en: "Your account couldn't be deleted. It still exists – please try again.",
                ru: "Не удалось удалить аккаунт. Он по-прежнему существует – попробуй снова."
            )
        case .some(let accountError):
            accountError.message + " " + keptAccountNotice
        }
    }

    static var keptAccountNotice: String {
        PaceLocalization.text(
            de: "Dein Konto wurde nicht gelöscht.",
            en: "Your account has not been deleted.",
            ru: "Твой аккаунт не был удалён."
        )
    }

    /// Was beim Löschen entfernt wird.
    public var deletionConsequences: [String] {
        [
            PaceLocalization.text(
                de: "Dein Profil mit Namen, Profilbild und Region",
                en: "Your profile with names, profile picture and region",
                ru: "Твой профиль с именами, фото и регионом"
            ),
            PaceLocalization.text(
                de: "Deine Tagesschritte in allen Rankings",
                en: "Your daily steps in all rankings",
                ru: "Твои ежедневные шаги во всех рейтингах"
            ),
            PaceLocalization.text(
                de: "Freundschaften, Anfragen, Gruppenmitgliedschaften und Einladungen",
                en: "Friendships, requests, group memberships and invitations",
                ru: "Дружба, запросы, участие в группах и приглашения"
            ),
            PaceLocalization.text(
                de: "Deine Chatnachrichten und hochgeladenen Bilder",
                en: "Your chat messages and uploaded images",
                ru: "Твои сообщения в чатах и загруженные изображения"
            ),
            PaceLocalization.text(
                de: "Einstellungen, Tagesziel-Verlauf und Rekord auf diesem iPhone",
                en: "Settings, daily goal history and record on this iPhone",
                ru: "Настройки, история дневной цели и рекорд на этом iPhone"
            ),
        ]
    }

    public var deletionWarning: String {
        PaceLocalization.text(
            de: "Das Löschen kann nicht rückgängig gemacht werden. Deine Daten in Apple Health bleiben unverändert. Gruppen, die du erstellt hast, gehen an ein anderes Mitglied über oder werden gelöscht, wenn niemand mehr darin ist.",
            en: "Deleting can't be undone. Your data in Apple Health stays unchanged. Groups you created are passed on to another member or deleted if nobody is left.",
            ru: "Удаление нельзя отменить. Твои данные в Apple Health не изменятся. Созданные тобой группы перейдут другому участнику или будут удалены, если в них никого не останется."
        )
    }

    public var confirmationPrompt: String {
        PaceLocalization.text(
            de: "Gib zur Bestätigung deinen Benutzernamen „\(requiredConfirmation)“ ein.",
            en: "To confirm, enter your username “\(requiredConfirmation)”.",
            ru: "Для подтверждения введи своё имя пользователя «\(requiredConfirmation)»."
        )
    }
}
