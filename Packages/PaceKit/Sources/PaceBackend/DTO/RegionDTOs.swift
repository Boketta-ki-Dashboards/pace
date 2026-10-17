import Foundation
import PaceCore

/// „Hierarchy row“ aus `search_municipalities` und `get_region_hierarchy`: eine Gemeinde mit Kreis, Bundesland
/// und Land in einer Zeile.
struct HierarchyRow: Decodable, Equatable {
    let municipalityID: String
    let municipalityCode: String
    let municipalityName: String
    /// Als Text, damit unbekannte Arten nicht die ganze Antwort unlesbar machen.
    let municipalityKind: String?
    let districtID: String
    let districtCode: String
    let districtName: String
    let districtKind: String?
    let districtMunicipalityCount: Int
    let stateID: String
    let stateCode: String
    let stateName: String
    let stateMunicipalityCount: Int
    let countryID: String
    let countryCode: String
    let countryName: String
    let countryMunicipalityCount: Int

    enum CodingKeys: String, CodingKey {
        case municipalityID = "municipality_id"
        case municipalityCode = "municipality_code"
        case municipalityName = "municipality_name"
        case municipalityKind = "municipality_kind"
        case districtID = "district_id"
        case districtCode = "district_code"
        case districtName = "district_name"
        case districtKind = "district_kind"
        case districtMunicipalityCount = "district_municipality_count"
        case stateID = "state_id"
        case stateCode = "state_code"
        case stateName = "state_name"
        case stateMunicipalityCount = "state_municipality_count"
        case countryID = "country_id"
        case countryCode = "country_code"
        case countryName = "country_name"
        case countryMunicipalityCount = "country_municipality_count"
    }

    /// Unbekannte Arten werden zu `kind == nil`.
    var hierarchy: RegionHierarchy {
        let municipality = Region(
            id: RegionID(rawValue: municipalityID),
            code: municipalityCode,
            name: municipalityName,
            level: .municipality,
            kind: municipalityKind.flatMap(RegionKind.init(rawValue:)),
            parentID: RegionID(rawValue: districtID),
            municipalityCount: 1
        )
        let district = Region(
            id: RegionID(rawValue: districtID),
            code: districtCode,
            name: districtName,
            level: .district,
            kind: districtKind.flatMap(RegionKind.init(rawValue:)),
            parentID: RegionID(rawValue: stateID),
            municipalityCount: districtMunicipalityCount
        )
        let state = Region(
            id: RegionID(rawValue: stateID),
            code: stateCode,
            name: stateName,
            level: .state,
            kind: .state,
            parentID: RegionID(rawValue: countryID),
            municipalityCount: stateMunicipalityCount
        )
        let country = Region(
            id: RegionID(rawValue: countryID),
            code: countryCode,
            name: countryName,
            level: .country,
            kind: .country,
            parentID: nil,
            municipalityCount: countryMunicipalityCount
        )
        return RegionHierarchy(municipality: municipality, district: district, state: state, country: country)
    }
}

/// Parameter von `public.search_municipalities`.
struct SearchMunicipalitiesParams: Encodable {
    let query: String
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case query = "p_query"
        case limit = "p_limit"
    }
}

/// Parameter von `public.get_region_hierarchy`.
struct RegionHierarchyParams: Encodable {
    let municipalityID: String

    enum CodingKeys: String, CodingKey {
        case municipalityID = "p_municipality_id"
    }
}
