import Foundation

/// Feste ID einer Region, z. B. `DE:06432018` (Pfungstadt) oder `DE` (Deutschland).
///
/// Format: Länderkennung, optional gefolgt von `:` und dem amtlichen Schlüssel (Landes-, Kreis- bzw.
/// Gemeindeschlüssel/AGS). Regionen werden nie über Namen identifiziert.
public struct RegionID: Hashable, Sendable, Codable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// Ebene in der regionalen Hierarchie.
public enum RegionLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case municipality
    case district
    case state
    case country

    private var order: Int {
        switch self {
        case .municipality: 0
        case .district: 1
        case .state: 2
        case .country: 3
        }
    }

    public static func < (lhs: RegionLevel, rhs: RegionLevel) -> Bool {
        lhs.order < rhs.order
    }
}

/// Art der Gebietseinheit laut Gemeindeverzeichnis (Textkennzeichen).
public enum RegionKind: String, Codable, Sendable {
    case country
    case state
    // Kreise
    case kreisfreieStadt = "kreisfreie_stadt"
    case stadtkreis
    case kreis
    case landkreis
    case regionalverband
    // Gemeinden
    case markt
    case stadt
    case gemeinde
    case grosseKreisstadt = "grosse_kreisstadt"
    case gemeindefreiesGebiet = "gemeindefreies_gebiet"
}

public struct Region: Hashable, Sendable, Identifiable {
    public let id: RegionID
    /// Amtlicher Schlüssel, z. B. `06432018`. Für Länder der ISO-Code, z. B. `DE`.
    public let code: String
    /// Anzeigename ohne amtlichen Zusatz, z. B. `Pfungstadt` statt `Pfungstadt, Stadt`.
    public let name: String
    public let level: RegionLevel
    public let kind: RegionKind?
    public let parentID: RegionID?
    /// Anzahl der Gemeinden in dieser Region (Gemeinde selbst: 1).
    public let municipalityCount: Int

    public init(
        id: RegionID,
        code: String,
        name: String,
        level: RegionLevel,
        kind: RegionKind?,
        parentID: RegionID?,
        municipalityCount: Int
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.level = level
        self.kind = kind
        self.parentID = parentID
        self.municipalityCount = municipalityCount
    }

    /// Anzeigename in der App-Sprache: Amtliche Namen von Gemeinden, Kreisen und Ländern bleiben unverändert, nur
    /// Deutschland heißt auf Englisch „Germany“ und auf Russisch „Германия“.
    public var localizedName: String {
        guard level == .country, code == "DE" else { return name }
        return PaceLocalization.text(de: name, en: "Germany", ru: "Германия")
    }

    /// Name mit Art der Gebietseinheit, z. B. `Landkreis Darmstadt-Dieburg`. Namen, die die Art schon enthalten
    /// (`Main-Kinzig-Kreis`, `Landkreis Rostock`, `Region Hannover`, `Regionalverband Saarbrücken`), bleiben unverändert.
    public var displayName: String {
        guard level != .country else { return localizedName }
        guard !nameIncludesKind else { return name }
        switch kind {
        case .landkreis: return "Landkreis \(name)"
        case .kreis: return "Kreis \(name)"
        case .stadtkreis: return "Stadtkreis \(name)"
        default: return name
        }
    }

    /// Ortsangabe für Sätze wie „Du bist der Erste …“ in der Sprache der App.
    ///
    /// Deutsch mit passender Präposition: `in Pfungstadt`, `im Landkreis Darmstadt-Dieburg`, `im Oberbergischen
    /// Kreis`, `in der Region Hannover`, `im Saarland`. Englisch `in Pfungstadt`. Russisch bleibt der amtliche
    /// (deutsche) Name unverändert und wird nicht gebeugt: `в рейтинге «Pfungstadt»`.
    public var locative: String {
        PaceLocalization.text(de: germanLocative, en: "in \(displayName)", ru: "в рейтинге «\(displayName)»")
    }

    private var germanLocative: String {
        if name.hasPrefix("Region ") || name.hasPrefix("Städteregion ") {
            return "in der \(name)"
        }
        switch kind {
        case .landkreis, .kreis, .stadtkreis, .regionalverband:
            // Adjektivische Namen werden gebeugt: „Oberbergischer Kreis“ → „im Oberbergischen Kreis“.
            let dative = displayName.replacingOccurrences(of: "er Kreis", with: "en Kreis")
            return "im \(dative)"
        default:
            return name == "Saarland" ? "im Saarland" : "in \(name)"
        }
    }

    private var nameIncludesKind: Bool {
        name.localizedCaseInsensitiveContains("kreis")
            || ["Region ", "Städteregion ", "Regionalverband "].contains { name.hasPrefix($0) }
    }
}
