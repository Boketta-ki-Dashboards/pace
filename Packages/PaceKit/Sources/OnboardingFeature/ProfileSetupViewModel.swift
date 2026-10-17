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
        case .invalid(.tooShort): "Mindestens \(UsernameRules.minLength) Zeichen."
        case .invalid(.tooLong): "Höchstens \(UsernameRules.maxLength) Zeichen."
        case .invalid(.invalidCharacters): "Nur Buchstaben ohne Umlaute, Ziffern und _ sind erlaubt."
        case .invalid(.reserved): "Dieser Name ist reserviert."
        case .checking: "Wird geprüft …"
        case .available: "Verfügbar"
        case .taken: "Dieser Benutzername ist schon vergeben."
        }
    }

    /// Dauerhafter Hinweis zu den Regeln für Benutzernamen.
    public var usernameRulesHint: String {
        "\(UsernameRules.minLength)–\(UsernameRules.maxLength) Zeichen: Buchstaben ohne Umlaute, Ziffern und _. "
            + "Groß- und Kleinschreibung zählen nicht als Unterschied."
    }

    /// Hinweis unter dem Anzeigenamen. Ein leeres Feld bekommt keinen Hinweis, nur einen deaktivierten Button.
    public var displayNameMessage: String? {
        switch DisplayNameRules.violation(for: displayName) {
        case .tooLong: "Höchstens \(DisplayNameRules.maxLength) Zeichen."
        case .invalidCharacters: "Der Name enthält ungültige Zeichen."
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
            "Dieser Benutzername ist nicht erlaubt. Bitte wähle einen anderen."
        case .invalidDisplayName:
            "Dieser Anzeigename ist nicht erlaubt. Bitte wähle einen anderen."
        case .network:
            "Keine Verbindung. Prüfe deine Internetverbindung und versuche es erneut."
        default:
            "Dein Profil konnte nicht angelegt werden. Bitte versuche es erneut."
        }
    }
}
