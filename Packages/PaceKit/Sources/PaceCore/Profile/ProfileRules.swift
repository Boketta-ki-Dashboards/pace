import Foundation

/// Regeln für Benutzernamen. Spiegelt exakt die serverseitige Prüfung (`supabase/migrations`), damit Fehler
/// schon beim Tippen sichtbar sind. Der Server bleibt die verbindliche Instanz.
public enum UsernameRules {
    public static let minLength = 3
    public static let maxLength = 20

    /// Reservierte Namen (ohne Beachtung der Groß-/Kleinschreibung).
    public static let reserved: Set<String> = [
        "admin", "administrator", "pace", "paceapp", "support", "help", "hilfe", "moderator", "mod",
        "system", "root", "official", "offiziell", "team", "staff", "null", "undefined", "me", "du",
    ]

    public enum Violation: Equatable, Sendable {
        case tooShort
        case tooLong
        case invalidCharacters
        case reserved
    }

    /// Entfernt führende und nachfolgende Leerzeichen.
    public static func normalized(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `nil`, wenn der (normalisierte) Name gültig ist. Erlaubt: a–z, A–Z, 0–9 und `_`.
    public static func violation(for username: String) -> Violation? {
        let name = normalized(username)
        guard name.allSatisfy(isAllowed) else { return .invalidCharacters }
        if name.count < minLength { return .tooShort }
        if name.count > maxLength { return .tooLong }
        if reserved.contains(name.lowercased()) { return .reserved }
        return nil
    }

    private static func isAllowed(_ character: Character) -> Bool {
        guard character.isASCII, let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F: return true // 0-9, A-Z, a-z, _
        default: return false
        }
    }
}

/// Regeln für Anzeigenamen: bewusst weniger streng als Benutzernamen.
public enum DisplayNameRules {
    public static let minLength = 1
    public static let maxLength = 30

    public enum Violation: Equatable, Sendable {
        case empty
        case tooLong
        case invalidCharacters
    }

    /// Entfernt Leerzeichen am Rand und fasst mehrfache Leerzeichen zusammen.
    public static func normalized(_ displayName: String) -> String {
        displayName
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Die Länge zählt Unicode-Codepoints wie der Server (`char_length`), nicht sichtbare Zeichen: Ein Emoji aus
    /// mehreren Codepoints zählt mehrfach.
    public static func violation(for displayName: String) -> Violation? {
        let name = normalized(displayName)
        if name.isEmpty { return .empty }
        if name.unicodeScalars.count > maxLength { return .tooLong }
        let hasControlCharacters = name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        return hasControlCharacters ? .invalidCharacters : nil
    }
}
