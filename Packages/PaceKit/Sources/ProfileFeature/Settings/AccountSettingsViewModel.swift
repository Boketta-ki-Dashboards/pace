import Foundation
import Observation
import PaceCore

/// Link und Text zum Teilen des eigenen Profils, z. B. `pace://u/niklas`.
public struct ProfileShare: Equatable, Sendable {
    public let username: String

    public init(username: String) {
        self.username = username
    }

    /// Öffnet in Pace das Profil (Social-Tab); ob man die Person sehen oder hinzufügen darf, prüft der Server.
    public var url: URL {
        PaceLink.profile(username: username).url
    }

    public var subject: String {
        PaceLocalization.text(de: "Mein Pace-Profil", en: "My Pace profile", ru: "Мой профиль в Pace")
    }

    public var message: String {
        PaceLocalization.text(
            de: "Füge mich in Pace hinzu – mein Benutzername: @\(username)",
            en: "Add me on Pace – my username: @\(username)",
            ru: "Добавь меня в Pace – моё имя пользователя: @\(username)"
        )
    }
}

/// „Konto & Profil“: Namen, Profilbild, Teilen, Kontoinformationen und Anmeldung.
@MainActor
@Observable
public final class AccountSettingsViewModel {
    public enum AvatarActivity: Equatable, Sendable {
        case idle
        case uploading
        case removing
    }

    public private(set) var avatarActivity: AvatarActivity = .idle
    public private(set) var avatarError: String?
    /// Angemeldete Sitzung (für die Konto-Art); `nil`, solange nicht geladen.
    public private(set) var session: AuthSession?

    @ObservationIgnored private let store: ProfileStore
    @ObservationIgnored private let profiles: (any ProfileRepository)?
    @ObservationIgnored private let media: (any MediaRepository)?
    @ObservationIgnored private let auth: (any AuthProviding)?
    @ObservationIgnored private let availabilityDebounce: Duration

    public init(
        store: ProfileStore,
        profiles: (any ProfileRepository)?,
        media: (any MediaRepository)?,
        auth: (any AuthProviding)?,
        availabilityDebounce: Duration = .milliseconds(400)
    ) {
        self.store = store
        self.profiles = profiles
        self.media = media
        self.auth = auth
        self.availabilityDebounce = availabilityDebounce
    }

    public var displayName: String { store.profile.displayName }
    public var username: String { "@\(store.profile.username)" }
    public var avatar: MediaReference? { store.profile.avatar }
    /// Stabiler Wert für die Farbe der Initialen.
    public var avatarSeed: String { store.profile.publicID.uuidString }
    public var share: ProfileShare { ProfileShare(username: store.profile.username) }

    /// Profilbilder brauchen den Bilder-Speicher auf dem Server.
    public var supportsAvatar: Bool { media != nil }
    public var isAvatarBusy: Bool { avatarActivity != .idle }

    public var avatarHint: String {
        if supportsAvatar {
            return PaceLocalization.text(
                de: "Das Foto wird quadratisch zugeschnitten. Alle angemeldeten Pace-Nutzer können dein Profilbild sehen.",
                en: "The photo is cropped to a square. Everyone signed in to Pace can see your profile picture.",
                ru: "Фото обрезается до квадрата. Твоё фото профиля видят все пользователи Pace."
            )
        }
        return PaceLocalization.text(
            de: "Profilbilder sind noch nicht verfügbar, weil der Bilder-Speicher auf dem Server noch nicht eingerichtet ist.",
            en: "Profile pictures aren't available yet because image storage isn't set up on the server.",
            ru: "Фото профиля пока недоступны: хранилище изображений на сервере ещё не настроено."
        )
    }

    /// Neuer Dialog zum Ändern der Namen (mit dem aktuellen Stand vorausgefüllt).
    public func makeNameEditor() -> NameEditViewModel {
        NameEditViewModel(store: store, profiles: profiles, availabilityDebounce: availabilityDebounce)
    }

    // MARK: Kontoinformationen

    public func loadSession() async {
        session = await auth?.restoreSession()
    }

    /// Bisher gibt es nur die gerätegebundene Anmeldung ohne Login-Methode.
    public var accountKind: String {
        if session?.isAnonymous == false {
            return PaceLocalization.text(de: "Dauerhaft angemeldet", en: "Permanently signed in", ru: "Постоянный вход")
        }
        return PaceLocalization.text(
            de: "Ohne Anmeldung, an dieses iPhone gebunden",
            en: "No sign-in, tied to this iPhone",
            ru: "Без входа, привязан к этому iPhone"
        )
    }

    /// z. B. „1. Oktober 2026“.
    public var memberSince: String {
        store.profile.createdAt.formatted(Date.FormatStyle.pace(Date.FormatStyle(date: .long, time: .omitted)))
    }

    /// Öffentliche ID (erscheint z. B. in Rankings); kein Geheimnis, wird aber nur klein angezeigt.
    public var publicID: String {
        store.profile.publicID.uuidString.lowercased()
    }

    public var securityExplanation: String {
        PaceLocalization.text(
            de: "Dein Pace-Konto ist derzeit an dieses iPhone gebunden. Wenn du Pace löschst oder ein neues iPhone einrichtest, lässt sich dieses Konto nicht wiederherstellen – Freunde, Gruppen und Chats wären dann nicht mehr erreichbar.",
            en: "Your Pace account is currently tied to this iPhone. If you delete Pace or set up a new iPhone, this account can't be restored – your friends, groups and chats would no longer be reachable.",
            ru: "Сейчас твой аккаунт Pace привязан к этому iPhone. Если удалить Pace или настроить новый iPhone, аккаунт нельзя будет восстановить – друзья, группы и чаты станут недоступны."
        )
    }

    public var permanentSignInNotice: String {
        PaceLocalization.text(
            de: "Eine dauerhafte Anmeldung (z. B. „Mit Apple anmelden“), mit der du dein Konto auf ein neues iPhone mitnehmen kannst, ist in Vorbereitung. Sie soll dein bestehendes Konto mit Freunden, Gruppen und Verlauf übernehmen. Bis dahin gibt es hier bewusst keinen Anmelde-Knopf.",
            en: "A permanent sign-in (e.g. “Sign in with Apple”) that lets you take your account to a new iPhone is being prepared. It is meant to keep your existing account with friends, groups and history. Until then there is deliberately no sign-in button here.",
            ru: "Постоянный вход (например, «Вход с Apple»), с которым аккаунт можно перенести на новый iPhone, находится в разработке. Он должен сохранить твой аккаунт с друзьями, группами и историей. До тех пор кнопки входа здесь намеренно нет."
        )
    }

    // MARK: Profilbild

    /// Lädt ein bereits zugeschnittenes JPEG hoch, setzt es als Profilbild und löscht danach das alte Bild.
    /// - Returns: Der neue Verweis (damit die Ansicht das Bild direkt zwischenspeichern kann); `nil` bei Fehlern.
    @discardableResult
    public func uploadAvatar(jpegData: Data) async -> MediaReference? {
        guard let media, avatarActivity == .idle else { return nil }
        guard jpegData.count <= MediaRules.maximumBytes(for: .avatar) else {
            avatarError = Self.avatarMessage(for: MediaError.tooLarge)
            return nil
        }
        avatarActivity = .uploading
        avatarError = nil
        defer { avatarActivity = .idle }

        let previous = store.profile.avatar
        let uploaded: MediaReference
        do {
            uploaded = try await media.upload(jpegData, contentType: "image/jpeg", to: .avatar)
        } catch {
            avatarError = Self.avatarMessage(for: error)
            return nil
        }

        do {
            try await store.updateAvatar(path: uploaded.path)
        } catch {
            // Das neue Bild wird nicht verwendet – nicht als verwaiste Datei liegen lassen.
            try? await media.delete(uploaded)
            avatarError = Self.avatarMessage(for: error)
            return nil
        }

        if let previous, previous != uploaded {
            // Schlägt das fehl, bleibt die alte Datei liegen; sie wird spätestens beim Löschen des Kontos entfernt.
            try? await media.delete(previous)
        }
        return uploaded
    }

    /// Entfernt das Profilbild (danach erscheinen wieder die Initialen) und löscht die Datei.
    public func removeAvatar() async {
        guard let previous = store.profile.avatar, avatarActivity == .idle else { return }
        avatarActivity = .removing
        avatarError = nil
        defer { avatarActivity = .idle }

        do {
            try await store.updateAvatar(path: nil)
        } catch {
            avatarError = Self.avatarMessage(for: error)
            return
        }
        try? await media?.delete(previous)
    }

    /// Das gewählte Foto ließ sich nicht lesen oder verkleinern.
    public func reportUnreadablePhoto() {
        avatarError = PaceLocalization.text(
            de: "Das Foto konnte nicht gelesen werden. Bitte wähle ein anderes.",
            en: "The photo couldn't be read. Please choose a different one.",
            ru: "Не удалось прочитать фото. Пожалуйста, выбери другое."
        )
    }

    static func avatarMessage(for error: Error) -> String {
        if let error = error as? ProfileError { return error.message }
        switch error as? MediaError {
        case .tooLarge:
            return PaceLocalization.text(
                de: "Das Bild ist zu groß. Erlaubt sind höchstens 5 MB.",
                en: "The image is too large. The maximum is 5 MB.",
                ru: "Изображение слишком большое. Максимум 5 МБ."
            )
        case .unsupportedType:
            return PaceLocalization.text(
                de: "Dieses Bildformat wird nicht unterstützt.",
                en: "This image format isn't supported.",
                ru: "Этот формат изображения не поддерживается."
            )
        case .network:
            return ProfileError.network.message
        case .unavailable:
            return PaceLocalization.text(
                de: "Profilbilder sind auf dem Server noch nicht eingerichtet.",
                en: "Profile pictures aren't set up on the server yet.",
                ru: "Фото профиля ещё не настроены на сервере."
            )
        case .notAllowed, .notFound, .unexpected, nil:
            return PaceLocalization.text(
                de: "Das Profilbild konnte nicht gespeichert werden. Bitte versuche es erneut.",
                en: "The profile picture couldn't be saved. Please try again.",
                ru: "Не удалось сохранить фото профиля. Попробуй снова."
            )
        }
    }
}
