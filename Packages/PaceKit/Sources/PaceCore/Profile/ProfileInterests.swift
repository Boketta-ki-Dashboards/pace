import Foundation

// MARK: - Grenzen

/// Grenzen für Interessen (gleich wie auf dem Server, Migration 20261102100000).
public enum ProfileInterestRules {
    /// Bis zu 20 Interessen je Profil – Katalog und eigene zusammen.
    public static let maximumTotal = 20
    /// Grenze auf Servern ohne Migration 20261102100000 (nur der ursprüngliche Katalog).
    public static let legacyMaximum = 5
    /// Auf fremden Profilen zunächst sichtbare Interessen; der Rest über „Alle Interessen ansehen“.
    public static let compactCount = 6
    /// Bis zu zehn gesprochene Sprachen.
    public static let maximumLanguages = 10
}

// MARK: - Kategorien

/// Gruppen des Interessenkatalogs.
public enum ProfileInterestCategory: String, CaseIterable, Sendable, Identifiable {
    case sport
    case creative
    case tech
    case leisure
    case culture

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sport: PaceLocalization.text(de: "Sport & Bewegung", en: "Sports & movement", ru: "Спорт и движение")
        case .creative: PaceLocalization.text(de: "Musik & Kreativität", en: "Music & creativity", ru: "Музыка и творчество")
        case .tech: PaceLocalization.text(de: "Technik & Gaming", en: "Tech & gaming", ru: "Техника и игры")
        case .leisure: PaceLocalization.text(de: "Alltag & Freizeit", en: "Everyday & leisure", ru: "Повседневность и досуг")
        case .culture: PaceLocalization.text(de: "Sprachen & Kultur", en: "Languages & culture", ru: "Языки и культура")
        }
    }

    public var systemImage: String {
        switch self {
        case .sport: "figure.run"
        case .creative: "music.note"
        case .tech: "gamecontroller"
        case .leisure: "cup.and.saucer"
        case .culture: "globe.europe.africa"
        }
    }

    /// Einträge der Kategorie in Anzeigereihenfolge.
    public var interests: [ProfileInterest] {
        ProfileInterest.allCases.filter { $0.categories.contains(self) }
    }
}

// MARK: - Katalog

/// Interesse aus dem gemeinsamen Katalog: gespeichert wird die stabile ID, angezeigt die Übersetzung.
///
/// Neue Einträge brauchen nur eine Zeile hier und eine im Server-Katalog (`private.profile_interest_catalog`) – keine
/// neue Spalte und kein neuer Constraint. Unbekannte IDs (neuere App-Version) blendet ``parse(_:)`` aus.
public enum ProfileInterest: String, CaseIterable, Codable, Sendable, Identifiable {
    // Sport & Bewegung
    case football
    case basketball
    case volleyball
    case fitness
    case running
    case walking
    case hiking
    case cycling
    case swimming
    case martialArts = "martial_arts"
    case dancing
    case skateboarding
    case tennis
    case yoga
    case outdoor
    case everydayMovement = "everyday_movement"
    case challenges
    case wellbeing
    // Musik & Kreativität
    case rap
    case hipHop = "hip_hop"
    case makingMusic = "making_music"
    case singing
    case freestyle
    case musicProduction = "music_production"
    case djing
    case drawing
    case photography
    case design
    // Technik & Gaming
    case programming
    case webDevelopment = "web_development"
    case appDevelopment = "app_development"
    case ai
    case gaming
    case gameDevelopment = "game_development"
    case technology
    case contentCreation = "content_creation"
    // Alltag & Freizeit
    case travel
    case cars
    case fashion
    case cooking
    case movies
    case series
    case books
    case nature
    case animals
    // Sprachen & Kultur
    case languageLearning = "language_learning"
    case multilingualism
    case culture
    case history
    case internationalFriendships = "international_friendships"

    /// Die ursprünglichen zehn Interessen (Auftrag 6). Server ohne Migration 20261102100000 kennen nur diese.
    public static let legacyCases: [ProfileInterest] = [
        .walking, .running, .hiking, .fitness, .cycling, .football, .outdoor, .everydayMovement, .challenges, .wellbeing,
    ]

    public var id: String { rawValue }

    public var isLegacy: Bool {
        Self.legacyCases.contains(self)
    }

    public var category: ProfileInterestCategory {
        switch self {
        case .football, .basketball, .volleyball, .fitness, .running, .walking, .hiking, .cycling, .swimming, .martialArts,
             .dancing, .skateboarding, .tennis, .yoga, .outdoor, .everydayMovement, .challenges, .wellbeing:
            .sport
        case .rap, .hipHop, .makingMusic, .singing, .freestyle, .musicProduction, .djing, .drawing, .photography, .design:
            .creative
        case .programming, .webDevelopment, .appDevelopment, .ai, .gaming, .gameDevelopment, .technology, .contentCreation:
            .tech
        case .travel, .cars, .fashion, .cooking, .movies, .series, .books, .nature, .animals:
            .leisure
        case .languageLearning, .multilingualism, .culture, .history, .internationalFriendships:
            .culture
        }
    }

    /// Kategorien, in denen der Eintrag erscheint – „Reisen“ auch unter „Sprachen & Kultur“ (eine ID, eine Auswahl).
    public var categories: [ProfileInterestCategory] {
        self == .travel ? [.leisure, .culture] : [category]
    }

    public var title: String {
        let titles = titles
        return PaceLocalization.text(de: titles.de, en: titles.en, ru: titles.ru)
    }

    /// Titel in allen App-Sprachen – für den Abgleich eigener Eingaben mit dem Katalog.
    public var allTitles: [String] {
        let titles = titles
        return [titles.de, titles.en, titles.ru]
    }

    private var titles: (de: String, en: String, ru: String) {
        switch self {
        case .football: ("Fußball", "Football", "Футбол")
        case .basketball: ("Basketball", "Basketball", "Баскетбол")
        case .volleyball: ("Volleyball", "Volleyball", "Волейбол")
        case .fitness: ("Fitness", "Fitness", "Фитнес")
        case .running: ("Laufen", "Running", "Бег")
        case .walking: ("Spazieren", "Walking", "Прогулки")
        case .hiking: ("Wandern", "Hiking", "Походы")
        case .cycling: ("Radfahren", "Cycling", "Велоспорт")
        case .swimming: ("Schwimmen", "Swimming", "Плавание")
        case .martialArts: ("Kampfsport", "Martial arts", "Единоборства")
        case .dancing: ("Tanzen", "Dancing", "Танцы")
        case .skateboarding: ("Skateboarding", "Skateboarding", "Скейтбординг")
        case .tennis: ("Tennis", "Tennis", "Теннис")
        case .yoga: ("Yoga", "Yoga", "Йога")
        case .outdoor: ("Outdoor", "Outdoors", "На природе")
        case .everydayMovement: ("Bewegung im Alltag", "Everyday movement", "Движение каждый день")
        case .challenges: ("Challenges", "Challenges", "Челленджи")
        case .wellbeing: ("Gesundheit & Wohlbefinden", "Health & wellbeing", "Здоровье и самочувствие")
        case .rap: ("Rap", "Rap", "Рэп")
        case .hipHop: ("Hip-Hop", "Hip-hop", "Хип-хоп")
        case .makingMusic: ("Musik machen", "Making music", "Музицирование")
        case .singing: ("Singen", "Singing", "Пение")
        case .freestyle: ("Freestyle", "Freestyle", "Фристайл")
        case .musicProduction: ("Musikproduktion", "Music production", "Создание музыки")
        case .djing: ("DJing", "DJing", "Диджеинг")
        case .drawing: ("Zeichnen", "Drawing", "Рисование")
        case .photography: ("Fotografie", "Photography", "Фотография")
        case .design: ("Design", "Design", "Дизайн")
        case .programming: ("Programmieren", "Programming", "Программирование")
        case .webDevelopment: ("Webcoding", "Web development", "Веб-разработка")
        case .appDevelopment: ("App-Entwicklung", "App development", "Разработка приложений")
        case .ai: ("KI", "AI", "ИИ")
        case .gaming: ("Gaming", "Gaming", "Гейминг")
        case .gameDevelopment: ("Game Development", "Game development", "Разработка игр")
        case .technology: ("Technik", "Technology", "Техника")
        case .contentCreation: ("Content Creation", "Content creation", "Создание контента")
        case .travel: ("Reisen", "Travel", "Путешествия")
        case .cars: ("Autos", "Cars", "Автомобили")
        case .fashion: ("Mode", "Fashion", "Мода")
        case .cooking: ("Kochen", "Cooking", "Кулинария")
        case .movies: ("Filme", "Movies", "Фильмы")
        case .series: ("Serien", "TV series", "Сериалы")
        case .books: ("Bücher", "Books", "Книги")
        case .nature: ("Natur", "Nature", "Природа")
        case .animals: ("Tiere", "Animals", "Животные")
        case .languageLearning: ("Sprachen lernen", "Learning languages", "Изучение языков")
        case .multilingualism: ("Mehrsprachigkeit", "Multilingualism", "Многоязычие")
        case .culture: ("Kultur", "Culture", "Культура")
        case .history: ("Geschichte", "History", "История")
        case .internationalFriendships: ("Internationale Freundschaften", "International friendships", "Международная дружба")
        }
    }

    public var systemImage: String {
        switch self {
        case .football: "soccerball"
        case .basketball: "basketball"
        case .volleyball: "volleyball"
        case .fitness: "dumbbell"
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .cycling: "bicycle"
        case .swimming: "figure.pool.swim"
        case .martialArts: "figure.martial.arts"
        case .dancing: "figure.dance"
        case .skateboarding: "figure.skateboarding"
        case .tennis: "tennis.racket"
        case .yoga: "figure.yoga"
        case .outdoor: "tree"
        case .everydayMovement: "figure.walk.motion"
        case .challenges: "flag.checkered"
        case .wellbeing: "heart"
        case .rap: "quote.bubble"
        case .hipHop: "headphones"
        case .makingMusic: "music.note"
        case .singing: "music.mic"
        case .freestyle: "waveform"
        case .musicProduction: "slider.vertical.3"
        case .djing: "hifispeaker"
        case .drawing: "paintbrush.pointed"
        case .photography: "camera"
        case .design: "paintpalette"
        case .programming: "chevron.left.forwardslash.chevron.right"
        case .webDevelopment: "globe"
        case .appDevelopment: "apps.iphone"
        case .ai: "sparkles"
        case .gaming: "gamecontroller"
        case .gameDevelopment: "cube"
        case .technology: "cpu"
        case .contentCreation: "video"
        case .travel: "airplane"
        case .cars: "car"
        case .fashion: "tshirt"
        case .cooking: "fork.knife"
        case .movies: "film"
        case .series: "tv"
        case .books: "book"
        case .nature: "leaf"
        case .animals: "pawprint"
        case .languageLearning: "character.book.closed"
        case .multilingualism: "character.bubble"
        case .culture: "theatermasks"
        case .history: "building.columns"
        case .internationalFriendships: "person.2"
        }
    }

    /// Unbekannte IDs (neuere App-Version) fallen weg, Doppelte auch; höchstens ``ProfileInterestRules/maximumTotal``.
    public static func parse(_ ids: [String]) -> [ProfileInterest] {
        var seen = Set<ProfileInterest>()
        return ids.compactMap(ProfileInterest.init(rawValue:)).filter { seen.insert($0).inserted }
            .prefix(ProfileInterestRules.maximumTotal).map { $0 }
    }

    /// IDs im gültigen Format, die diese App-Version nicht kennt (aus einer neueren Version) – ohne Doppelte. Sie
    /// bleiben beim Speichern erhalten (``ProfileDetails/preservedInterestIDs``).
    public static func unknownIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { id in
            ProfileInterest(rawValue: id) == nil
                && id.range(of: "^[a-z][a-z_]{1,39}$", options: .regularExpression) != nil
                && seen.insert(id).inserted
        }
    }
}

/// Ein angezeigtes Interesse: aus dem Katalog (übersetzt) oder selbst eingegeben (wie eingegeben).
public enum ProfileInterestItem: Hashable, Sendable, Identifiable {
    case catalog(ProfileInterest)
    case custom(String)

    public var id: String {
        switch self {
        case .catalog(let interest): "catalog:\(interest.rawValue)"
        case .custom(let text): "custom:\(text.lowercased())"
        }
    }

    public var title: String {
        switch self {
        case .catalog(let interest): interest.title
        case .custom(let text): text
        }
    }

    /// Symbol nur für Katalogeinträge – eigene Begriffe haben keins (Pace rät nicht, was gemeint ist).
    public var systemImage: String? {
        switch self {
        case .catalog(let interest): interest.systemImage
        case .custom: nil
        }
    }
}

// MARK: - Eigene Interessen

/// Regeln für selbst eingegebene Interessen – gleich wie auf dem Server (Trigger `validate_profile_details`).
public enum CustomInterestRules {
    public static let minimumLength = 2
    /// Höchstens 30 Zeichen – passt auch als einzelnes langes Wort auf einen Chip auf dem iPhone SE.
    public static let maximumLength = 30

    public enum Problem: Error, Equatable, Sendable {
        case empty
        case tooShort
        case tooLong
        case invalidCharacters
        /// Links, E-Mail-Adressen oder @-Erwähnungen gehören nicht in Interessen.
        case link
        /// Bereits ausgewählt (Groß-/Kleinschreibung egal).
        case duplicate
        /// Gibt es im Katalog – stattdessen den Katalogeintrag wählen.
        case inCatalog(ProfileInterest)
        case limitReached
    }

    /// Leerzeichen am Rand weg, Leerraum innen (auch Zeilenumbrüche, Tabs) zu einem Leerzeichen, Unicode-NFC.
    public static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    /// Länge wie auf dem Server (`char_length`, Unicode-Zeichen).
    public static func length(_ text: String) -> Int {
        text.unicodeScalars.count
    }

    /// Schlüssel für den Vergleich ohne Groß-/Kleinschreibung (wie `lower()` auf dem Server).
    public static func key(_ text: String) -> String {
        normalized(text).lowercased()
    }

    /// Katalogeintrag mit diesem Titel in einer der App-Sprachen (z. B. „rap“, „Basketball“, „Баскетбол“).
    public static func catalogMatch(for text: String) -> ProfileInterest? {
        let key = key(text)
        guard !key.isEmpty else { return nil }
        return ProfileInterest.allCases.first { interest in
            interest.allTitles.contains { $0.lowercased() == key } || interest.rawValue == key
        }
    }

    /// Prüft einen (normalisierten) Begriff ohne Rücksicht auf die bestehende Auswahl; `nil` = in Ordnung.
    public static func problem(_ text: String) -> Problem? {
        if text.isEmpty { return .empty }
        if text.unicodeScalars.contains(where: isForbidden) { return .invalidCharacters }
        let length = length(text)
        if length < minimumLength { return .tooShort }
        if length > maximumLength { return .tooLong }
        let lowered = text.lowercased()
        if lowered.contains("://") || lowered.contains("www.") || lowered.contains("@")
            || lowered.range(of: linkPattern, options: .regularExpression) != nil {
            return .link
        }
        return nil
    }

    /// Wie auf dem Server: „domain.tld/…“ oder eine bekannte Endung am Wortende („t.me/x“, „onlyfans.com“), nicht
    /// „Node.js“.
    static let linkPattern = #"\.[a-z]{2,}/|\.(com|net|org|de|ru|me|io|ly|gg|tv|app|xyz|info|link)($| )"#

    /// Prüft eine Eingabe gegen die aktuelle Auswahl: normalisiert, gültig, nicht doppelt, nicht im Katalog, Platz frei.
    /// - Returns: den zu speichernden Text oder das Problem.
    public static func validate(
        _ input: String,
        existing: [String],
        selected: [ProfileInterest],
        limit: Int
    ) -> Result<String, Problem> {
        let text = normalized(input)
        if let problem = problem(text) { return .failure(problem) }
        if existing.contains(where: { key($0) == key(text) }) { return .failure(.duplicate) }
        if let match = catalogMatch(for: text) {
            return .failure(selected.contains(match) ? .duplicate : .inCatalog(match))
        }
        if existing.count + selected.count >= limit { return .failure(.limitReached) }
        return .success(text)
    }

    /// Eigene Einträge aus dem Server: normalisiert, gültig, ohne Doppelte (Groß-/Kleinschreibung egal).
    public static func parse(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map(normalized).filter { problem($0) == nil && seen.insert(key($0)).inserted }
    }

    /// Steuerzeichen (auch Zeilenumbruch) und unsichtbare Formatzeichen wie bei der Bio – außer dem Zero-Width-Joiner,
    /// den Emoji-Folgen brauchen –, dazu leer dargestellte Füllzeichen (Hangul-Füller, Braille-Leerzeichen, Combining
    /// Grapheme Joiner), sonst entstünden leere Chips.
    static func isForbidden(_ scalar: Unicode.Scalar) -> Bool {
        let blank: Set<UInt32> = [0x034F, 0x115F, 0x1160, 0x2800, 0x3164, 0xFFA0]
        return scalar.value == 0x0A || blank.contains(scalar.value) || ProfileBioRules.isForbidden(scalar)
    }

    public static func message(for problem: Problem) -> String {
        switch problem {
        case .empty:
            PaceLocalization.text(de: "Bitte gib einen Begriff ein.", en: "Please enter a term.", ru: "Введи слово или фразу.")
        case .tooShort:
            PaceLocalization.text(
                de: "Mindestens \(minimumLength) Zeichen.",
                en: "At least \(minimumLength) characters.",
                ru: "Не меньше \(minimumLength) символов."
            )
        case .tooLong:
            PaceLocalization.text(
                de: "Höchstens \(maximumLength) Zeichen.",
                en: "At most \(maximumLength) characters.",
                ru: "Не больше \(maximumLength) символов."
            )
        case .invalidCharacters:
            ProfileBioRules.message(for: .invalidCharacters)
        case .link:
            PaceLocalization.text(
                de: "Bitte ohne Links, E-Mail-Adressen oder @.",
                en: "Please leave out links, email addresses and @.",
                ru: "Без ссылок, адресов почты и @."
            )
        case .duplicate:
            PaceLocalization.text(de: "Schon ausgewählt.", en: "Already selected.", ru: "Уже выбрано.")
        case .inCatalog(let interest):
            PaceLocalization.text(
                de: "„\(interest.title)“ gibt es schon im Katalog.",
                en: "“\(interest.title)” is already in the catalog.",
                ru: "«\(interest.title)» уже есть в каталоге."
            )
        case .limitReached:
            PaceLocalization.text(
                de: "Höchstens \(ProfileInterestRules.maximumTotal) Interessen.",
                en: "At most \(ProfileInterestRules.maximumTotal) interests.",
                ru: "Не больше \(ProfileInterestRules.maximumTotal) интересов."
            )
        }
    }
}

// MARK: - Gesprochene Sprachen

/// Auswahlliste für gesprochene Sprachen (ISO-639-Codes). Namen kommen aus dem System in der App-Sprache; gesucht wird
/// auch nach dem Namen in der Sprache selbst („Српски“) und nach dem englischen Namen.
public enum SpokenLanguageCatalog {
    /// Häufige Sprachen – zuerst die der App, dann alphabetisch nach Code. Gespeichert wird nur der Code; der Server
    /// prüft das Format, nicht die Liste (spätere Erweiterung ohne Migration).
    public static let codes: [String] = [
        "de", "en", "ru",
        "af", "am", "ar", "az", "be", "bg", "bn", "bs", "ca", "cs", "cy", "da", "el", "eo", "es", "et", "eu", "fa", "fi",
        "fil", "fr", "ga", "gl", "gsw", "he", "hi", "hr", "hu", "hy", "id", "is", "it", "ja", "ka", "kk", "km", "ko", "ku",
        "ky", "lb", "lo", "lt", "lv", "mk", "mn", "ms", "mt", "my", "nb", "ne", "nl", "pa", "pl", "ps", "pt", "ro", "rom",
        "si", "sk", "sl", "so", "sq", "sr", "sv", "sw", "ta", "te", "tg", "th", "ti", "tk", "tr", "uk", "ur", "uz", "vi",
        "yi", "zh",
    ]

    /// Name in der aktuellen App-Sprache, z. B. „Serbisch“ / „Serbian“ / „сербский“ (am Anfang groß).
    public static func name(for code: String) -> String {
        let locale = Locale(identifier: PaceLocalization.shared.effectiveLanguage.rawValue)
        return capitalized(locale.localizedString(forLanguageCode: code), locale: locale) ?? code.uppercased()
    }

    /// Name in der Sprache selbst, z. B. „Српски“.
    public static func nativeName(for code: String) -> String? {
        let locale = Locale(identifier: code)
        return capitalized(locale.localizedString(forLanguageCode: code), locale: locale)
    }

    /// Codes, deren Name (App-Sprache, Englisch oder die Sprache selbst) oder Code die Suche enthält.
    public static func search(_ query: String) -> [String] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return codes }
        let english = Locale(identifier: "en")
        return codes.filter { code in
            let names = [name(for: code), nativeName(for: code), english.localizedString(forLanguageCode: code), code]
            return names.contains { name in
                name.map { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil } ?? false
            }
        }
    }

    /// Gültiger Code wie auf dem Server: zwei bis drei Kleinbuchstaben.
    public static func isValid(_ code: String) -> Bool {
        (2...3).contains(code.count) && code.allSatisfy { ("a"..."z").contains($0) }
    }

    /// Codes aus dem Server: gültig, ohne Doppelte, höchstens ``ProfileInterestRules/maximumLanguages``.
    public static func parse(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { isValid($0) && seen.insert($0).inserted }.prefix(ProfileInterestRules.maximumLanguages).map { $0 }
    }

    static func capitalized(_ name: String?, locale: Locale) -> String? {
        guard let name, let first = name.first else { return nil }
        return String(first).uppercased(with: locale) + name.dropFirst()
    }
}

// MARK: - Land / Kulturbezug

/// Freiwilliger Länder- bzw. Kulturbezug: ISO-3166-Codes mit Namen in der App-Sprache und Flagge.
public enum ProfileCountryCatalog {
    /// Alle ISO-3166-1-Ländercodes (ohne unbewohnte Gebiete).
    public static let codes: [String] = """
    AD AE AF AG AI AL AM AO AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BW BY BZ CA CC CD CF CG \
    CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH \
    GI GL GM GN GP GQ GR GT GU GW GY HK HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY \
    KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG \
    NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM \
    SN SO SR SS ST SV SX SY SZ TC TD TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS XK \
    YE YT ZA ZM ZW
    """.split(separator: " ").map(String.init)

    /// Name in der aktuellen App-Sprache, z. B. „Italien“ / „Italy“ / „Италия“.
    public static func name(for code: String) -> String {
        let locale = Locale(identifier: PaceLocalization.shared.effectiveLanguage.rawValue)
        if code == "XK" {
            return PaceLocalization.text(de: "Kosovo", en: "Kosovo", ru: "Косово")
        }
        return locale.localizedString(forRegionCode: code) ?? code
    }

    /// Flagge aus den regionalen Indikatorzeichen (🇮🇹).
    public static func flag(for code: String) -> String {
        let scalars = code.uppercased().unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            guard ("A"..."Z").contains(Character(scalar)) else { return nil }
            return Unicode.Scalar(0x1F1E6 + scalar.value - 0x41)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Codes, deren Name (App-Sprache oder Englisch) oder Code die Suche enthält – alphabetisch nach Namen.
    public static func search(_ query: String) -> [String] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let english = Locale(identifier: "en")
        // Namen einmal bestimmen (nicht bei jedem Vergleich im Sortieren).
        let names = Dictionary(uniqueKeysWithValues: codes.map { ($0, name(for: $0)) })
        let matches = query.isEmpty ? codes : codes.filter { code in
            [names[code], english.localizedString(forRegionCode: code), code].contains { name in
                name.map { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil } ?? false
            }
        }
        let locale = PaceLocalization.shared.locale
        return matches.sorted { (names[$0] ?? $0).compare(names[$1] ?? $1, locale: locale) == .orderedAscending }
    }

    /// Code aus der Liste (der Server prüft nur das Format; unbekannte Codes wie „ZZ“ zeigt die App nicht an).
    public static func isKnown(_ code: String) -> Bool {
        codes.contains(code)
    }

    /// Gültiger Code wie auf dem Server: zwei Großbuchstaben.
    public static func isValid(_ code: String) -> Bool {
        code.count == 2 && code.allSatisfy { ("A"..."Z").contains($0) }
    }
}
