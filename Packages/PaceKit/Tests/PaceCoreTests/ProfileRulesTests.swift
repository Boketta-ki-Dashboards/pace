import Foundation
import PaceCore
import Testing

struct UsernameRulesTests {
    @Test(arguments: ["abc", "Niklas_76", "a_b_c", "ABCDEFGHIJKLMNOPQRST", "user123", "  niklas  "])
    func acceptsValidUsernames(_ username: String) {
        #expect(UsernameRules.violation(for: username) == nil)
    }

    @Test(arguments: ["ab", "a", ""])
    func rejectsTooShort(_ username: String) {
        #expect(UsernameRules.violation(for: username) == .tooShort)
    }

    @Test func rejectsTooLong() {
        #expect(UsernameRules.violation(for: String(repeating: "a", count: 21)) == .tooLong)
    }

    @Test(arguments: ["niklas zockt", "niklas-76", "nik.las", "jürgen", "emoji😀", "a@b", "tab\tname"])
    func rejectsInvalidCharactersIncludingSpaces(_ username: String) {
        #expect(UsernameRules.violation(for: username) == .invalidCharacters)
    }

    @Test(arguments: ["admin", "ADMIN", "Pace", "support", "Root"])
    func rejectsReservedNamesCaseInsensitively(_ username: String) {
        #expect(UsernameRules.violation(for: username) == .reserved)
    }

    @Test func normalizesSurroundingWhitespace() {
        #expect(UsernameRules.normalized("  niklas\n") == "niklas")
    }
}

struct DisplayNameRulesTests {
    @Test(arguments: ["Niklas", "Niklas Zockt", "Jürgen 🏃", "N", "Dr. Müller-Lüdenscheidt"])
    func acceptsValidDisplayNames(_ name: String) {
        #expect(DisplayNameRules.violation(for: name) == nil)
    }

    @Test(arguments: ["", "   ", "\n"])
    func rejectsEmpty(_ name: String) {
        #expect(DisplayNameRules.violation(for: name) == .empty)
    }

    @Test func rejectsTooLong() {
        #expect(DisplayNameRules.violation(for: String(repeating: "x", count: 31)) == .tooLong)
    }

    @Test func rejectsControlCharacters() {
        #expect(DisplayNameRules.violation(for: "Nik\u{0007}las") == .invalidCharacters)
    }

    /// Unsichtbare Formatzeichen lehnt auch der Server ab (Constraint `profiles_display_name_valid`).
    @Test(arguments: ["\u{200B}", "Nik\u{200B}las", "Nik\u{202E}las", "\u{FEFF}Niklas"])
    func rejectsInvisibleFormatCharacters(_ name: String) {
        #expect(DisplayNameRules.violation(for: name) == .invalidCharacters)
    }

    /// Wie `char_length` auf dem Server: 29 Buchstaben plus ein Emoji aus zwei Codepoints sind zu lang.
    @Test func lengthCountsCodePointsLikeTheServer() {
        let name = String(repeating: "x", count: 29) + "\u{2764}\u{FE0F}"
        #expect(name.count == 30)
        #expect(DisplayNameRules.violation(for: name) == .tooLong)
        #expect(DisplayNameRules.violation(for: String(repeating: "x", count: 28) + "\u{2764}\u{FE0F}") == nil)
    }

    @Test func collapsesWhitespace() {
        #expect(DisplayNameRules.normalized("  Niklas    Zockt \n") == "Niklas Zockt")
    }
}
