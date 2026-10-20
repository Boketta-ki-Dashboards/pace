import Foundation
import Observation
import PaceCore

/// Erster Onboarding-Schritt: Anzeigename und Benutzername wählen und das Profil anlegen.
///
/// Die Regeln werden schon beim Tippen geprüft; verbindlich entscheidet der Server (u. a. über die Eindeutigkeit
/// des Benutzernamens ohne Beachtung der Groß-/Kleinschreibung).
@MainActor
@Observable
public final class ProfileSetupViewModel {
    public enum UsernameStatus: Equatable {
        /// Noch nichts eingegeben.
        case empty
        case invalid(UsernameRules.Violation)
        /// Die Verfügbarkeit wird gerade geprüft.
        case checking
        case available
        case taken
        /// Gültig, Verfügbarkeit (noch) unbekannt. Der Server prüft beim Anlegen.
        case unchecked
    }

    public var username = ""
    public var displayName = ""

    public private(set) var isSubmitting = false
    public private(set) var errorMessage: String?

    /// Ergebnisse der Verfügbarkeitsprüfung, Schlüssel in Kleinbuchstaben.
    private var availability: [String: Bool] = [:]
    private var checkingUsername: String?

    @ObservationIgnored private let userID: UserID
    @ObservationIgnored private let profiles: any ProfileRepository
    @ObservationIgnored private let availabilityDebounce: Duration
    @ObservationIgnored private let onCreated: @MainActor (UserProfile) -> Void

    public init(
        userID: UserID,
        profiles: any ProfileRepository,
        availabilityDebounce: Duration = .milliseconds(400),
        onCreated: @escaping @MainActor (UserProfile) -> Void
    ) {
        self.userID = userID
        self.profiles = profiles
        self.availabilityDebounce = availabilityDebounce
        self.onCreated = onCreated
    }

    public var usernameStatus: UsernameStatus {
        let name = UsernameRules.normalized(username)
        if name.isEmpty { return .empty }
        if let violation = UsernameRules.violation(for: name) { return .invalid(violation) }
        let key = name.lowercased()
        switch availability[key] {
        case true?: return .available
        case false?: return .taken
        case nil: return checkingUsername == key ? .checking : .unchecked
        }
    }

    /// Hinweis unter dem Benutzernamen, z. B. „Mindestens 3 Zeichen.“
    public var usernameMessage: String? {
        switch usernameStatus {
        case .empty, .unchecked: nil
        case .invalid(.tooShort): OnboardingTexts.atLeast(UsernameRules.minLength)
        case .invalid(.tooLong): OnboardingTexts.atMost(UsernameRules.maxLength)
        case .invalid(.invalidCharacters):
            PaceLocalization.text(
                de: "Nur Buchstaben ohne Umlaute, Ziffern und _ sind erlaubt.",
                en: "Only letters without umlauts, digits and _ are allowed.",
                ru: "Разрешены только латинские буквы без умлаутов, цифры и _."
            )
        case .invalid(.reserved):
            PaceLocalization.text(de: "Dieser Name ist reserviert.", en: "This name is reserved.", ru: "Это имя зарезервировано.")
        case .checking: PaceLocalization.text(de: "Wird geprüft …", en: "Checking …", ru: "Проверяем…")
        case .available: PaceLocalization.text(de: "Verfügbar", en: "Available", ru: "Свободно")
        case .taken:
            PaceLocalization.text(
                de: "Dieser Benutzername ist schon vergeben.",
                en: "This username is already taken.",
                ru: "Это имя пользователя уже занято."
            )
        }
    }

    /// Dauerhafter Hinweis zu den Regeln für Benutzernamen.
    public var usernameRulesHint: String {
        let range = "\(UsernameRules.minLength)–\(UsernameRules.maxLength)"
        return PaceLocalization.text(
            de: "\(range) Zeichen: Buchstaben ohne Umlaute, Ziffern und _. Groß- und Kleinschreibung zählen nicht als Unterschied.",
            en: "\(range) characters: letters without umlauts, digits and _. Upper and lower case count as the same.",
            ru: "\(range) символов: латинские буквы без умлаутов, цифры и _. Регистр букв не учитывается."
        )
    }

    /// Hinweis unter dem Anzeigenamen. Ein leeres Feld bekommt keinen Hinweis, nur einen deaktivierten Button.
    public var displayNameMessage: String? {
        switch DisplayNameRules.violation(for: displayName) {
        case .tooLong: OnboardingTexts.atMost(DisplayNameRules.maxLength)
        case .invalidCharacters:
            PaceLocalization.text(
                de: "Der Name enthält ungültige Zeichen.",
                en: "The name contains invalid characters.",
                ru: "Имя содержит недопустимые символы."
            )
        case .empty, nil: nil
        }
    }

    public var canSubmit: Bool {
        guard !isSubmitting, DisplayNameRules.violation(for: displayName) == nil else { return false }
        switch usernameStatus {
        case .available, .unchecked, .checking: return true
        case .empty, .invalid, .taken: return false
        }
    }

    /// Prüft nach kurzer Pause, ob der eingegebene Benutzername frei ist. Gedacht für `.task(id: username)`.
    /// Fehler bleiben still: Dann entscheidet der Server beim Anlegen.
    public func checkUsernameAvailability() async {
        let name = UsernameRules.normalized(username)
        guard UsernameRules.violation(for: name) == nil else { return }
        let key = name.lowercased()
        guard availability[key] == nil else { return }

        if availabilityDebounce > .zero {
            do {
                try await Task.sleep(for: availabilityDebounce)
            } catch {
                return
            }
        }

        checkingUsername = key
        defer {
            if checkingUsername == key { checkingUsername = nil }
        }
        if let available = try? await profiles.isUsernameAvailable(name) {
            availability[key] = available
        }
    }

    public func submit() async {
        guard canSubmit else { return }
        let newProfile = NewProfile(
            username: UsernameRules.normalized(username),
            displayName: DisplayNameRules.normalized(displayName)
        )
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let profile = try await profiles.createProfile(newProfile, for: userID)
            onCreated(profile)
        } catch ProfileError.usernameTaken {
            availability[newProfile.username.lowercased()] = false
        } catch {
            // Ging nur die Antwort verloren, existiert das Profil bereits. Dann geht es einfach weiter.
            if let existing = try? await profiles.fetchProfile(for: userID) {
                onCreated(existing)
                return
            }
            errorMessage = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        switch error as? ProfileError {
        case .invalidUsername:
            PaceLocalization.text(
                de: "Dieser Benutzername ist nicht erlaubt. Bitte wähle einen anderen.",
                en: "This username isn't allowed. Please choose another one.",
                ru: "Это имя пользователя недопустимо. Выбери другое."
            )
        case .invalidDisplayName:
            PaceLocalization.text(
                de: "Dieser Anzeigename ist nicht erlaubt. Bitte wähle einen anderen.",
                en: "This display name isn't allowed. Please choose another one.",
                ru: "Это имя недопустимо. Выбери другое."
            )
        case .network:
            OnboardingTexts.noConnection
        default:
            PaceLocalization.text(
                de: "Dein Profil konnte nicht angelegt werden. Bitte versuche es erneut.",
                en: "Your profile couldn't be created. Please try again.",
                ru: "Не удалось создать профиль. Попробуй ещё раз."
            )
        }
    }
}

/// Wiederkehrende Texte des Onboardings – in der Sprache der App.
enum OnboardingTexts {
    static var noConnection: String {
        PaceLocalization.text(
            de: "Keine Verbindung. Prüfe deine Internetverbindung und versuche es erneut.",
            en: "No connection. Check your internet connection and try again.",
            ru: "Нет соединения. Проверь подключение к интернету и попробуй ещё раз."
        )
    }

    static var next: String { PaceLocalization.text(de: "Weiter", en: "Continue", ru: "Далее") }

    /// „Mindestens 3 Zeichen.“
    static func atLeast(_ count: Int) -> String {
        PaceLocalization.plural(
            count,
            de: ("Mindestens \(count) Zeichen.", "Mindestens \(count) Zeichen."),
            en: ("At least \(count) character.", "At least \(count) characters."),
            ru: ("Не менее \(count) символа.", "Не менее \(count) символов.", "Не менее \(count) символов.")
        )
    }

    /// „Höchstens 20 Zeichen.“
    static func atMost(_ count: Int) -> String {
        PaceLocalization.plural(
            count,
            de: ("Höchstens \(count) Zeichen.", "Höchstens \(count) Zeichen."),
            en: ("At most \(count) character.", "At most \(count) characters."),
            ru: ("Не более \(count) символа.", "Не более \(count) символов.", "Не более \(count) символов.")
        )
    }
}
