import Foundation
import Observation
import PaceCore

/// Anzeigename und Benutzername ändern – mit denselben Regeln wie beim Anlegen des Profils.
///
/// Die Regeln werden schon beim Tippen geprüft, die Verfügbarkeit des Benutzernamens nach einer kurzen Pause.
/// Verbindlich entscheidet der Server (u. a. über die Eindeutigkeit ohne Beachtung der Groß-/Kleinschreibung).
@MainActor
@Observable
public final class NameEditViewModel {
    public enum UsernameStatus: Equatable, Sendable {
        case empty
        case invalid(UsernameRules.Violation)
        /// Wie bisher (auch bei anderer Groß-/Kleinschreibung) – keine Prüfung nötig.
        case unchanged
        case checking
        case available
        case taken
        /// Gültig, Verfügbarkeit (noch) unbekannt. Der Server prüft beim Sichern.
        case unchecked
    }

    public var username: String
    public var displayName: String

    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    /// Nach erfolgreichem Sichern `true` – die Ansicht schließt sich dann.
    public private(set) var didSave = false

    /// Ergebnisse der Verfügbarkeitsprüfung, Schlüssel in Kleinbuchstaben.
    private var availability: [String: Bool] = [:]
    private var checkingUsername: String?

    @ObservationIgnored private let store: ProfileStore
    @ObservationIgnored private let profiles: (any ProfileRepository)?
    @ObservationIgnored private let availabilityDebounce: Duration

    /// - Parameter profiles: Für die Verfügbarkeitsprüfung; ohne Angabe prüft erst der Server beim Sichern.
    public init(store: ProfileStore, profiles: (any ProfileRepository)?, availabilityDebounce: Duration = .milliseconds(400)) {
        self.store = store
        self.profiles = profiles
        self.availabilityDebounce = availabilityDebounce
        username = store.profile.username
        displayName = store.profile.displayName
    }

    private var normalizedUsername: String { UsernameRules.normalized(username) }
    private var normalizedDisplayName: String { DisplayNameRules.normalized(displayName) }

    var usernameChanged: Bool {
        normalizedUsername != store.profile.username
    }

    var displayNameChanged: Bool {
        normalizedDisplayName != store.profile.displayName
    }

    public var usernameStatus: UsernameStatus {
        let name = normalizedUsername
        if name.isEmpty { return .empty }
        if let violation = UsernameRules.violation(for: name) { return .invalid(violation) }
        let key = name.lowercased()
        if key == store.profile.username.lowercased() { return .unchanged }
        switch availability[key] {
        case true?: return .available
        case false?: return .taken
        case nil: return checkingUsername == key ? .checking : .unchecked
        }
    }

    /// Hinweis unter dem Benutzernamen, z. B. „Mindestens 3 Zeichen.“
    public var usernameMessage: String? {
        switch usernameStatus {
        case .empty, .unchecked, .unchanged:
            nil
        case .invalid(.tooShort):
            PaceLocalization.text(
                de: "Mindestens \(ProfileTexts.characters(UsernameRules.minLength)).",
                en: "At least \(ProfileTexts.characters(UsernameRules.minLength)).",
                ru: "Минимум \(ProfileTexts.characters(UsernameRules.minLength))."
            )
        case .invalid(.tooLong):
            PaceLocalization.text(
                de: "Höchstens \(ProfileTexts.characters(UsernameRules.maxLength)).",
                en: "At most \(ProfileTexts.characters(UsernameRules.maxLength)).",
                ru: "Максимум \(ProfileTexts.characters(UsernameRules.maxLength))."
            )
        case .invalid(.invalidCharacters):
            PaceLocalization.text(
                de: "Nur Buchstaben ohne Umlaute, Ziffern und _ sind erlaubt.",
                en: "Only letters without accents, digits and _ are allowed.",
                ru: "Допустимы только латинские буквы без диакритики, цифры и _."
            )
        case .invalid(.reserved):
            PaceLocalization.text(de: "Dieser Name ist reserviert.", en: "This name is reserved.", ru: "Это имя зарезервировано.")
        case .checking:
            PaceLocalization.text(de: "Wird geprüft …", en: "Checking …", ru: "Проверяем …")
        case .available:
            PaceLocalization.text(de: "Verfügbar", en: "Available", ru: "Доступно")
        case .taken:
            ProfileError.usernameTaken.message
        }
    }

    /// Dauerhafter Hinweis zu den Regeln für Benutzernamen.
    public var usernameRulesHint: String {
        PaceLocalization.text(
            de: "\(UsernameRules.minLength)–\(UsernameRules.maxLength) Zeichen: Buchstaben ohne Umlaute, Ziffern und _. Groß- und Kleinschreibung zählen nicht als Unterschied. Links zu deinem Profil mit dem alten Namen funktionieren danach nicht mehr.",
            en: "\(UsernameRules.minLength)–\(UsernameRules.maxLength) characters: letters without accents, digits and _. Upper and lower case count as the same. Links to your profile with the old name will stop working.",
            ru: "\(UsernameRules.minLength)–\(UsernameRules.maxLength) символов: латинские буквы без диакритики, цифры и _. Регистр букв не учитывается. Ссылки на профиль со старым именем перестанут работать."
        )
    }

    /// Hinweis unter dem Anzeigenamen. Ein leeres Feld bekommt keinen Hinweis, nur einen deaktivierten Button.
    public var displayNameMessage: String? {
        switch DisplayNameRules.violation(for: displayName) {
        case .tooLong:
            PaceLocalization.text(
                de: "Höchstens \(ProfileTexts.characters(DisplayNameRules.maxLength)).",
                en: "At most \(ProfileTexts.characters(DisplayNameRules.maxLength)).",
                ru: "Максимум \(ProfileTexts.characters(DisplayNameRules.maxLength))."
            )
        case .invalidCharacters:
            PaceLocalization.text(
                de: "Der Name enthält ungültige Zeichen.",
                en: "The name contains invalid characters.",
                ru: "Имя содержит недопустимые символы."
            )
        case .empty, nil:
            nil
        }
    }

    public var canSave: Bool {
        guard !isSaving, usernameChanged || displayNameChanged else { return false }
        guard DisplayNameRules.violation(for: displayName) == nil else { return false }
        switch usernameStatus {
        case .available, .unchecked, .checking, .unchanged: return true
        case .empty, .invalid, .taken: return false
        }
    }

    /// Prüft nach kurzer Pause, ob der eingegebene Benutzername frei ist. Gedacht für `.task(id: username)`.
    /// Fehler bleiben still: Dann entscheidet der Server beim Sichern.
    public func checkUsernameAvailability() async {
        guard let profiles else { return }
        let name = normalizedUsername
        guard UsernameRules.violation(for: name) == nil else { return }
        let key = name.lowercased()
        guard key != store.profile.username.lowercased(), availability[key] == nil else { return }

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

    /// Speichert nur, was sich geändert hat.
    public func save() async {
        guard canSave else { return }
        let newUsername = usernameChanged ? normalizedUsername : nil
        let newDisplayName = displayNameChanged ? normalizedDisplayName : nil
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await store.updateNames(username: newUsername, displayName: newDisplayName)
            username = store.profile.username
            displayName = store.profile.displayName
            didSave = true
        } catch ProfileError.usernameTaken {
            if let newUsername {
                availability[newUsername.lowercased()] = false
            }
            errorMessage = ProfileError.usernameTaken.message
        } catch let error as ProfileError {
            errorMessage = error.message
        } catch {
            errorMessage = ProfileError.unexpected(String(describing: error)).message
        }
    }
}
