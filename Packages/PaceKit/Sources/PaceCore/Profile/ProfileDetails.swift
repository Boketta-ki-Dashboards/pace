import Foundation

/// Freiwillige Angaben eines Pace-Profils (Social-Profil 2.0, Auftrag 6): Bio, Interessen, Banner und – nur wenn die
/// Person das ausdrücklich freigibt – Auszeichnungen. Alles optional; ältere Profile haben keine dieser Angaben.
///
/// Gespeichert wird in `public.profiles` (Migration 20261030100000). Ohne diese Migration auf dem Server meldet das
/// Repository ``ProfileDetailsError/unavailable`` – die App zeigt die neuen Felder dann nicht an.
public struct ProfileDetails: Equatable, Sendable {
    public var bio: String?
    public var interests: [ProfileInterest]
    /// Banner im Bucket `avatars` (Ordner der eigenen öffentlichen ID); `nil` = neutraler Pace-Hintergrund.
    public var bannerPath: String?
    /// Auszeichnungen auf dem Profil zeigen (Standard: aus). Nur beim eigenen Profil bekannt.
    public var showsAchievements: Bool
    /// Beim eigenen Profil die gespeicherten, bei anderen nur die freigegebenen Auszeichnungen.
    public var achievements: [ProfileAchievement]

    public init(
        bio: String? = nil,
        interests: [ProfileInterest] = [],
        bannerPath: String? = nil,
        showsAchievements: Bool = false,
        achievements: [ProfileAchievement] = []
    ) {
        self.bio = bio
        self.interests = interests
        self.bannerPath = bannerPath
        self.showsAchievements = showsAchievements
        self.achievements = achievements
    }

    public static let empty = ProfileDetails()

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

// MARK: - Interessen

/// Interesse aus dem festen Katalog (gespeichert wird die stabile ID, angezeigt die Übersetzung).
public enum ProfileInterest: String, CaseIterable, Codable, Sendable, Identifiable {
    case walking
    case running
    case hiking
    case fitness
    case cycling
    case football
    case outdoor
    case everydayMovement = "everyday_movement"
    case challenges
    case wellbeing

    /// Bis zu fünf Interessen je Profil.
    public static let maximumCount = 5

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .walking: PaceLocalization.text(de: "Spazieren", en: "Walking", ru: "Прогулки")
        case .running: PaceLocalization.text(de: "Laufen", en: "Running", ru: "Бег")
        case .hiking: PaceLocalization.text(de: "Wandern", en: "Hiking", ru: "Походы")
        case .fitness: PaceLocalization.text(de: "Fitness", en: "Fitness", ru: "Фитнес")
        case .cycling: PaceLocalization.text(de: "Radfahren", en: "Cycling", ru: "Велоспорт")
        case .football: PaceLocalization.text(de: "Fußball", en: "Football", ru: "Футбол")
        case .outdoor: PaceLocalization.text(de: "Outdoor", en: "Outdoors", ru: "На природе")
        case .everydayMovement: PaceLocalization.text(de: "Bewegung im Alltag", en: "Everyday movement", ru: "Движение каждый день")
        case .challenges: PaceLocalization.text(de: "Challenges", en: "Challenges", ru: "Челленджи")
        case .wellbeing: PaceLocalization.text(de: "Gesundheit & Wohlbefinden", en: "Health & wellbeing", ru: "Здоровье и самочувствие")
        }
    }

    public var systemImage: String {
        switch self {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .hiking: "figure.hiking"
        case .fitness: "dumbbell"
        case .cycling: "bicycle"
        case .football: "soccerball"
        case .outdoor: "tree"
        case .everydayMovement: "figure.walk.motion"
        case .challenges: "flag.checkered"
        case .wellbeing: "heart"
        }
    }

    /// Unbekannte IDs (neuere App-Version) fallen weg, Doppelte auch; höchstens ``maximumCount``.
    public static func parse(_ ids: [String]) -> [ProfileInterest] {
        var seen = Set<ProfileInterest>()
        return ids.compactMap(ProfileInterest.init(rawValue:)).filter { seen.insert($0).inserted }.prefix(maximumCount).map { $0 }
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
        case .bestDay10k: PaceLocalization.text(de: "Tag mit über 10.000 Schritten", en: "A day over 10,000 steps", ru: "День больше 10 000 шагов")
        case .bestDay20k: PaceLocalization.text(de: "Tag mit über 20.000 Schritten", en: "A day over 20,000 steps", ru: "День больше 20 000 шагов")
        case .bestDay30k: PaceLocalization.text(de: "Tag mit über 30.000 Schritten", en: "A day over 30,000 steps", ru: "День больше 30 000 шагов")
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

    /// Unbekannte IDs fallen weg, Doppelte auch.
    public static func parse(_ ids: [String]) -> [ProfileAchievement] {
        var seen = Set<ProfileAchievement>()
        return ids.compactMap(ProfileAchievement.init(rawValue:)).filter { seen.insert($0).inserted }
    }
}
