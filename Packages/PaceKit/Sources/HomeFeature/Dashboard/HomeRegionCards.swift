import Foundation
import PaceCore

/// Eine der vier regionalen Karten auf Home: Stadt/Gemeinde, Landkreis, Bundesland, Land.
///
/// Es gibt immer alle vier Ebenen – auch bei kreisfreien Städten und Stadtstaaten. Hat eine Ebene dieselben Gemeinden
/// wie die kleinere (Frankfurt als Stadt und kreisfreie Stadt, Berlin als Stadt, Kreis und Land), gilt dort dasselbe
/// Ranking und damit derselbe Platz; nur die Bezeichnung passt sich an.
public struct HomeRegionCard: Equatable, Sendable, Identifiable {
    public let level: RegionLevel
    /// Gebiet dieser Ebene; `nil`, solange die Region nicht geladen ist.
    public let region: Region?
    /// Das Ranking, das für diese Ebene gilt (bei gleichen Gemeinden das der kleineren Ebene).
    public let rankingRegion: Region?
    /// Eigener Platz; `nil`, wenn (noch) nicht platziert.
    public let rank: Int?
    /// Schritte bis zum nächsten Platz; nur bekannt, wenn die Ebene mit Nachbarn geladen wurde.
    public let stepsToNextPlace: Int?

    public var id: RegionLevel { level }

    public init(level: RegionLevel, region: Region?, rankingRegion: Region?, rank: Int?, stepsToNextPlace: Int?) {
        self.level = level
        self.region = region
        self.rankingRegion = rankingRegion
        self.rank = rank
        self.stepsToNextPlace = stepsToNextPlace
    }

    /// Ob die Ebene das Ranking einer kleineren Ebene teilt (kreisfreie Stadt, Stadtstaat).
    public var sharesSmallerRanking: Bool {
        guard let region, let rankingRegion else { return false }
        return region.id != rankingRegion.id
    }

    /// z. B. `Stadt`, `Landkreis`, `Kreisfreie Stadt`, `Bundesland`, `Stadtstaat`, `Land`.
    public var title: String {
        Self.title(for: level, region: region)
    }

    /// Name des Gebiets, z. B. `Darmstadt-Dieburg`.
    public var name: String {
        region?.name ?? ""
    }

    /// z. B. `#12`; ohne Platz `–`.
    public var rankText: String {
        rank.map { "#\($0.paceFormatted)" } ?? "–"
    }

    /// Kurzer Abstand zum nächsten Platz, z. B. `+280 bis #11`; auf Platz 1 `Spitze`.
    public var nextPlaceShortText: String? {
        if rank == 1 {
            return PaceLocalization.text(de: "Spitze", en: "Top spot", ru: "Лидер")
        }
        guard let steps = stepsToNextPlace, let rank else { return nil }
        let target = "#\((rank - 1).paceFormatted)"
        return PaceLocalization.text(
            de: "+\(steps.paceFormatted) bis \(target)",
            en: "+\(steps.paceFormatted) to \(target)",
            ru: "+\(steps.paceFormatted) до \(target)"
        )
    }

    /// Ausführlicher Hinweis für das Max-Widget, z. B. `Noch 280 Schritte bis Platz #11`.
    public var nextPlaceText: String? {
        if rank == 1 {
            return PaceLocalization.text(de: "Du führst hier.", en: "You're in the lead here.", ru: "Здесь ты лидируешь.")
        }
        guard let steps = stepsToNextPlace, let rank else { return nil }
        return HomeRankingTexts.stepsToPlace(steps, place: rank - 1)
    }

    public var accessibilityLabel: String {
        let place = rank.map {
            PaceLocalization.text(de: "Platz \($0.paceFormatted)", en: "rank \($0.paceFormatted)", ru: "место \($0.paceFormatted)")
        } ?? PaceLocalization.text(de: "noch nicht platziert", en: "not ranked yet", ru: "пока без места")
        let area = name.isEmpty ? title : "\(title) \(name)"
        return "\(area), \(place)"
    }

    static func title(for level: RegionLevel, region: Region?) -> String {
        switch level {
        case .municipality:
            switch region?.kind {
            case .markt:
                return PaceLocalization.text(de: "Markt", en: "Market town", ru: "Ярмарочная община")
            case .gemeinde, .gemeindefreiesGebiet:
                return PaceLocalization.text(de: "Gemeinde", en: "Municipality", ru: "Община")
            default:
                return PaceLocalization.text(de: "Stadt", en: "City", ru: "Город")
            }
        case .district:
            switch region?.kind {
            case .kreisfreieStadt:
                return PaceLocalization.text(de: "Kreisfreie Stadt", en: "Independent city", ru: "Город-район")
            case .stadtkreis:
                return PaceLocalization.text(de: "Stadtkreis", en: "Urban district", ru: "Городской округ")
            case .kreis:
                return PaceLocalization.text(de: "Kreis", en: "District", ru: "Район")
            case .regionalverband:
                return PaceLocalization.text(de: "Regionalverband", en: "Regional association", ru: "Региональный союз")
            default:
                return PaceLocalization.text(de: "Landkreis", en: "District", ru: "Район")
            }
        case .state:
            if let region, region.municipalityCount <= 1 {
                return PaceLocalization.text(de: "Stadtstaat", en: "City state", ru: "Город-земля")
            }
            return PaceLocalization.text(de: "Bundesland", en: "State", ru: "Земля")
        case .country:
            return PaceLocalization.text(de: "Land", en: "Country", ru: "Страна")
        }
    }
}

public enum HomeRegionCards {
    /// Karten für die gewünschten Ebenen (Standard: alle vier), von klein nach groß.
    ///
    /// - Parameters:
    ///   - hierarchy: Region des Nutzers; ohne sie entstehen Karten ohne Namen und Platz.
    ///   - standings: Geladene Platzierungen; `nil` vor dem Laden oder ohne Teilnahme.
    public static func cards(
        hierarchy: RegionHierarchy?,
        standings: RegionalStandings?,
        levels: [RegionLevel] = RegionLevel.allCases
    ) -> [HomeRegionCard] {
        let shown = RegionLevel.allCases.filter { levels.contains($0) }
        guard let hierarchy else {
            return shown.map { HomeRegionCard(level: $0, region: nil, rankingRegion: nil, rank: nil, stepsToNextPlace: nil) }
        }
        let scopes = hierarchy.leaderboardScopes
        return shown.map { level in
            let region = hierarchy.allLevels.first { $0.level == level }
            // Das Ranking dieser Ebene oder – wenn sie dieselben Gemeinden hat – das der nächst kleineren.
            let ranking = scopes.last { $0.level <= level }
            let scope = ranking.flatMap { ranking in standings?.scopes.first { $0.region.id == ranking.id } }
            let neighborhood = ranking.flatMap { standings?.neighborhood(for: $0.level, rows: 1) }
            return HomeRegionCard(
                level: level,
                region: region,
                rankingRegion: ranking,
                rank: scope?.rank,
                stepsToNextPlace: neighborhood?.stepsToNextPlace
            )
        }
    }
}

/// Texte rund um Ranking-Plätze, gemeinsam für Karten, Umfeld und Freunde-Widgets.
public enum HomeRankingTexts {
    /// z. B. `Noch 280 Schritte bis Platz #11`.
    public static func stepsToPlace(_ steps: Int, place: Int) -> String {
        let count = steps.paceFormatted
        let noun = PaceLocalization.plural(steps, de: ("Schritt", "Schritte"), en: ("step", "steps"), ru: ("шаг", "шага", "шагов"))
        let target = "#\(place.paceFormatted)"
        return PaceLocalization.text(
            de: "Noch \(count) \(noun) bis Platz \(target)",
            en: "\(count) \(noun) to rank \(target)",
            ru: "Ещё \(count) \(noun) до места \(target)"
        )
    }

    /// Hinweis unter dem Umfeld: Aufstieg, Führung oder „allein im Ranking“; `nil`, wenn der Platz darüber fehlt.
    public static func neighborhoodFooter(_ neighborhood: RegionalStandings.Neighborhood) -> String? {
        let region = neighborhood.region
        if neighborhood.isAlone {
            return PaceLocalization.text(
                de: "Du bist der Erste \(region.locative).",
                en: "You're the first one in \(region.name).",
                ru: "Ты первый в рейтинге: \(region.name)."
            )
        }
        if neighborhood.currentUser.rank == 1 {
            return PaceLocalization.text(
                de: "Du führst \(region.locative).",
                en: "You're in the lead in \(region.name).",
                ru: "Ты лидируешь в рейтинге: \(region.name)."
            )
        }
        guard let steps = neighborhood.stepsToNextPlace else { return nil }
        return stepsToPlace(steps, place: neighborhood.currentUser.rank - 1)
    }
}
