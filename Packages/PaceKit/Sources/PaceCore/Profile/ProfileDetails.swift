import Foundation

/// Freiwillige Angaben eines Pace-Profils (Social-Profil 2.0, Auftrag 6): Bio, Interessen, Banner und – nur wenn die
/// Person das ausdrücklich freigibt – Auszeichnungen. Alles optional; ältere Profile haben keine dieser Angaben.
///
/// Gespeichert wird in `public.profiles` (Migration 20261030100000). Ohne diese Migration auf dem Server meldet das
/// Repository ``ProfileDetailsError/unavailable`` – die App zeigt die neuen Felder dann nicht an.
public struct ProfileDetails: Equatable, Sendable {
    public var bio: String?
    /// Interessen aus dem Katalog (stabile IDs).
    public var interests: [ProfileInterest]
    /// Selbst eingegebene Interessen (normalisierter Text, so angezeigt wie eingegeben). Seit Migration 20261102100000.
    public var customInterests: [String]
    /// Freiwillig angegebene gesprochene Sprachen (ISO-639-Codes, z. B. `de`, `sr`). Nie aus der App-Sprache abgeleitet.
    public var spokenLanguages: [String]
    /// Freiwilliger Länder- bzw. Kulturbezug (ISO-3166-Code, z. B. `IT`) – Selbstbeschreibung, keine geprüfte Angabe.
    /// Ohne Einfluss auf die regionalen Ranglisten.
    public var countryCode: String?
    /// Banner im Bucket `avatars` (Ordner der eigenen öffentlichen ID); `nil` = neutraler Pace-Hintergrund.
    public var bannerPath: String?
    /// Auszeichnungen auf dem Profil zeigen (Standard: aus). Nur beim eigenen Profil bekannt.
    public var showsAchievements: Bool
    /// Beim eigenen Profil die gespeicherten, bei anderen nur die freigegebenen Auszeichnungen.
    public var achievements: [ProfileAchievement]
    /// Der Server kennt eigene Interessen, Sprachen und Land (Migration 20261102100000). Sonst gelten die bisherigen
    /// Grenzen: höchstens fünf Interessen aus dem ursprünglichen Katalog.
    public var supportsExtendedProfile: Bool
    /// Katalog-IDs, die diese App-Version noch nicht kennt (aus einer neueren Version gespeichert). Nicht angezeigt,
    /// aber beim Speichern unverändert mitgeschickt und auf die Höchstzahl angerechnet – sonst gingen sie verloren.
    public var preservedInterestIDs: [String]

    public init(
        bio: String? = nil,
        interests: [ProfileInterest] = [],
        customInterests: [String] = [],
        spokenLanguages: [String] = [],
        countryCode: String? = nil,
        bannerPath: String? = nil,
        showsAchievements: Bool = false,
        achievements: [ProfileAchievement] = [],
        supportsExtendedProfile: Bool = false,
        preservedInterestIDs: [String] = []
    ) {
        self.bio = bio
        self.interests = interests
        self.customInterests = customInterests
        self.spokenLanguages = spokenLanguages
        self.countryCode = countryCode
        self.bannerPath = bannerPath
        self.showsAchievements = showsAchievements
        self.achievements = achievements
        self.supportsExtendedProfile = supportsExtendedProfile
        self.preservedInterestIDs = preservedInterestIDs
    }

    public static let empty = ProfileDetails()

    /// Höchstzahl der Interessen (Katalog und eigene zusammen) – 20, auf älteren Servern 5.
    public var interestLimit: Int {
        supportsExtendedProfile ? ProfileInterestRules.maximumTotal : ProfileInterestRules.legacyMaximum
    }

    /// Alle Interessen zur Anzeige: Katalog (übersetzt) und eigene (wie eingegeben).
    public var allInterests: [ProfileInterestItem] {
        interests.map(ProfileInterestItem.catalog) + customInterests.map(ProfileInterestItem.custom)
    }

    /// Ob es Interessen, Sprachen oder ein Land zu zeigen gibt.
    public var hasInterestsOrBackground: Bool {
        !interests.isEmpty || !customInterests.isEmpty || !spokenLanguages.isEmpty || countryCode != nil
    }

    public var banner: MediaReference? { .avatar(bannerPath) }

    /// Auszeichnungen, die andere sehen.
    public var visibleAchievements: [ProfileAchievement] {
        showsAchievements ? achievements : []
    }
}

/// Fehler beim Laden oder Speichern der Profilangaben.
public enum ProfileDetailsError: Error, Equatable, Sendable {
    /// Der Server kennt die Profilangaben noch nicht (Migration 20261030100000 nicht eingespielt).
    case unavailable
    /// Vom Server abgelehnt (Länge, Zeichen, Katalog, Banner-Datei).
    case invalid
    case notFound
    case rateLimited
    case network
    case unexpected(String)
}

/// Profilangaben lesen und die eigenen speichern.
public protocol ProfileDetailsRepository: Sendable {
    /// Angaben einer Person (gleiche Sichtbarkeit wie ihr Profil). Für die eigene öffentliche ID samt
    /// ``ProfileDetails/showsAchievements``.
    func details(of publicID: UUID) async throws -> ProfileDetails
    /// Eigene Angaben (aus der eigenen Zeile).
    func ownDetails() async throws -> ProfileDetails
    /// Speichert die eigenen Angaben (Bio wird vorher normalisiert, Listen ohne Doppelte).
    func saveOwnDetails(_ details: ProfileDetails) async throws -> ProfileDetails
}

// MARK: - Bio

/// Regeln für die Bio – gleich wie auf dem Server (Constraint `profiles_bio_valid`).
public enum ProfileBioRules {
    /// Höchstens 160 Zeichen (Unicode-Zeichen wie `char_length` auf dem Server).
    public static let maximumLength = 160
    /// Höchstens vier Zeilen.
    public static let maximumLines = 4

    public enum Problem: Equatable, Sendable {
        case tooLong
        case tooManyLines
        case invalidCharacters
    }

    /// Länge wie auf dem Server (Unicode-Zeichen, Emojis aus mehreren Zeichen zählen entsprechend).
    public static func length(_ text: String) -> Int {
        text.unicodeScalars.count
    }

    /// Leerzeichen und Leerzeilen am Rand weg, Leerzeichen am Zeilenende weg; leer → `nil` (keine Bio).
    public static func normalized(_ text: String) -> String? {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                String(line.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed())
            }
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: CharacterSet(charactersIn: " \n\t"))
        return joined.isEmpty ? nil : joined
    }

    /// Prüft eine (normalisierte) Bio; `nil` = in Ordnung.
    public static func problem(_ text: String) -> Problem? {
        if text.unicodeScalars.contains(where: isForbidden) { return .invalidCharacters }
        if length(text) > maximumLength { return .tooLong }
        if text.components(separatedBy: "\n").count > maximumLines { return .tooManyLines }
        return nil
    }

    /// Steuerzeichen (außer Zeilenumbruch) und unsichtbare Formatzeichen wie beim Anzeigenamen – außer dem
    /// Zero-Width-Joiner, den Emoji-Folgen brauchen.
    static func isForbidden(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if value == 0x0A { return false }
        if value < 0x20 || value == 0x7F { return true }
        if value == 0x200D { return false }
        let ranges: [ClosedRange<UInt32>] = [
            0x0080...0x009F, 0x00AD...0x00AD, 0x0600...0x0605, 0x061C...0x061C, 0x06DD...0x06DD, 0x070F...0x070F,
            0x180E...0x180E, 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2064, 0x2066...0x206F, 0xFEFF...0xFEFF,
            0xFFF9...0xFFFB, 0xE0001...0xE0001, 0xE0020...0xE007F,
        ]
        return ranges.contains { $0.contains(value) }
    }

    /// Fehlermeldung für die Bearbeitung.
    public static func message(for problem: Problem) -> String {
        switch problem {
        case .tooLong:
            PaceLocalization.text(
                de: "Höchstens \(maximumLength) Zeichen.",
                en: "At most \(maximumLength) characters.",
                ru: "Не больше \(maximumLength) символов."
            )
        case .tooManyLines:
            PaceLocalization.text(
                de: "Höchstens \(maximumLines) Zeilen.",
                en: "At most \(maximumLines) lines.",
                ru: "Не больше \(maximumLines) строк."
            )
        case .invalidCharacters:
            PaceLocalization.text(
                de: "Enthält unsichtbare oder nicht erlaubte Zeichen.",
                en: "Contains invisible or unsupported characters.",
                ru: "Содержит невидимые или недопустимые символы."
            )
        }
    }
}

// MARK: - Auszeichnungen

/// Freiwillig sichtbare Auszeichnung – ohne genaue Werte (keine Schrittzahlen, nur Stufen).
public enum ProfileAchievement: String, CaseIterable, Codable, Sendable, Identifiable {
    case streak7 = "streak_7"
    case streak30 = "streak_30"
    case streak100 = "streak_100"
    case streak365 = "streak_365"
    case bestDay10k = "best_day_10k"
    case bestDay20k = "best_day_20k"
    case bestDay30k = "best_day_30k"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .streak7: PaceLocalization.text(de: "7 Tage in Folge", en: "7 days in a row", ru: "7 дней подряд")
        case .streak30: PaceLocalization.text(de: "30 Tage in Folge", en: "30 days in a row", ru: "30 дней подряд")
        case .streak100: PaceLocalization.text(de: "100 Tage in Folge", en: "100 days in a row", ru: "100 дней подряд")
        case .streak365: PaceLocalization.text(de: "365 Tage in Folge", en: "365 days in a row", ru: "365 дней подряд")
        case .bestDay10k: PaceLocalization.text(de: "Tag mit 10.000+ Schritten", en: "10,000+ steps in a day", ru: "10 000+ шагов за день")
        case .bestDay20k: PaceLocalization.text(de: "Tag mit 20.000+ Schritten", en: "20,000+ steps in a day", ru: "20 000+ шагов за день")
        case .bestDay30k: PaceLocalization.text(de: "Tag mit 30.000+ Schritten", en: "30,000+ steps in a day", ru: "30 000+ шагов за день")
        }
    }

    public var systemImage: String {
        switch self {
        case .streak7, .streak30, .streak100, .streak365: "flame.fill"
        case .bestDay10k, .bestDay20k, .bestDay30k: "trophy.fill"
        }
    }

    /// Erreichte Auszeichnungen aus den vorhandenen Werten der App: längste persönliche Serie (Tage) und bester Tag
    /// (Wettbewerbsschritte, ohne manuell eingetragene). Nur die jeweils höchste Stufe je Art wird gezeigt.
    public static func earned(longestStreak: Int, bestDaySteps: Int) -> [ProfileAchievement] {
        let streak: ProfileAchievement? = switch longestStreak {
        case 365...: .streak365
        case 100...: .streak100
        case 30...: .streak30
        case 7...: .streak7
        default: nil
        }
        let bestDay: ProfileAchievement? = switch bestDaySteps {
        case 30_000...: .bestDay30k
        case 20_000...: .bestDay20k
        case 10_000...: .bestDay10k
        default: nil
        }
        return [streak, bestDay].compactMap { $0 }
    }

    /// Je Art (Serie, bester Tag) die höhere Stufe aus beiden Listen – zum Nachtragen veröffentlichter Auszeichnungen.
    /// Entfernt nie eine Stufe: Serie und Bestwert wachsen nur, und ein Bestwert außerhalb des geladenen Verlaufs
    /// (älter als etwa ein Jahr) bleibt so erhalten.
    public static func upgraded(_ published: [ProfileAchievement], with earned: [ProfileAchievement]) -> [ProfileAchievement] {
        let all = published + earned
        let order = allCases
        func highest(_ kind: [ProfileAchievement]) -> ProfileAchievement? {
            all.filter(kind.contains).max { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
        }
        return [highest([.streak7, .streak30, .streak100, .streak365]), highest([.bestDay10k, .bestDay20k, .bestDay30k])].compactMap { $0 }
    }

    /// Unbekannte IDs fallen weg, Doppelte auch.
    public static func parse(_ ids: [String]) -> [ProfileAchievement] {
        var seen = Set<ProfileAchievement>()
        return ids.compactMap(ProfileAchievement.init(rawValue:)).filter { seen.insert($0).inserted }
    }
}
