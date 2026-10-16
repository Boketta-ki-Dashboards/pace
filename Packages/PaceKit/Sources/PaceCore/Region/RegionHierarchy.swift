import Foundation

/// Die vollständige Zuordnung einer Gemeinde: Gemeinde → Kreis bzw. kreisfreie Stadt → Bundesland → Land.
public struct RegionHierarchy: Hashable, Sendable, Identifiable {
    public let municipality: Region
    public let district: Region
    public let state: Region
    public let country: Region

    public init(municipality: Region, district: Region, state: Region, country: Region) {
        self.municipality = municipality
        self.district = district
        self.state = state
        self.country = country
    }

    public var id: RegionID { municipality.id }

    /// Alle vier Ebenen, von klein nach groß.
    public var allLevels: [Region] {
        [municipality, district, state, country]
    }

    /// Ebenen für Rankings, von klein nach groß. Ebenen mit denselben Gemeinden wie die vorige entfallen –
    /// z. B. „Frankfurt am Main“ als kreisfreie Stadt neben der Gemeinde Frankfurt, oder Berlin als Bundesland.
    public var leaderboardScopes: [Region] {
        var scopes: [Region] = []
        for region in allLevels {
            if let previous = scopes.last, region.municipalityCount <= previous.municipalityCount {
                continue
            }
            scopes.append(region)
        }
        return scopes
    }

    /// Zweite Zeile in Suchergebnissen, z. B. `Hessen · Landkreis Darmstadt-Dieburg`.
    public var subtitle: String {
        if state.municipalityCount <= 1 {
            return "Stadtstaat"
        }
        if district.municipalityCount <= 1 {
            return "\(state.name) · kreisfreie Stadt"
        }
        return "\(state.name) · \(district.displayName)"
    }
}

/// Lädt Regionen. Die Daten stammen aus dem amtlichen Gemeindeverzeichnis (siehe docs/BACKEND.md).
public protocol RegionRepository: Sendable {
    /// Gemeinden, deren Name zur Suche passt – sortiert nach Relevanz.
    func searchMunicipalities(matching query: String, limit: Int) async throws -> [RegionHierarchy]

    /// Die Hierarchie zu einer Gemeinde.
    func hierarchy(forMunicipality id: RegionID) async throws -> RegionHierarchy
}

public enum RegionError: Error, Equatable, Sendable {
    case notFound
    case network
    case unexpected(String)
}

/// Bereitet Sucheingaben auf.
public enum RegionSearchQuery {
    public static let minimumLength = 2

    /// Getrimmte Eingabe mit zusammengefassten Leerzeichen, oder `nil`, wenn sie zu kurz für eine Suche ist.
    public static func normalized(_ raw: String) -> String? {
        let query = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return query.count >= minimumLength ? query : nil
    }
}
