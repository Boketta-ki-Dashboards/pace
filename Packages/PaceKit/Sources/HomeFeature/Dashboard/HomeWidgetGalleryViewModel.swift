import Foundation
import Observation
import PaceCore
import SocialFeature

/// Widget-Galerie: Kategorie wählen, konkrete Daten auswählen (Freunde, Gruppe, Ebene, Kennzahl), Größe festlegen
/// und das Widget hinzufügen – oder ein vorhandenes Widget bearbeiten.
///
/// Die Vorschau zeigt ``draft`` mit echten Daten; jede Änderung an Kategorie, Auswahl oder Größe ändert sie sofort.
@MainActor
@Observable
public final class HomeWidgetGalleryViewModel {
    public enum Mode: Equatable, Sendable {
        case add
        case edit(HomeModule.ID)
    }

    public let mode: Mode
    public private(set) var kind: HomeModuleKind
    public var size: HomeModuleSize
    /// Ausgewählte Freunde in Auswahlreihenfolge (leer = alle Freunde).
    public private(set) var friendIDs: [UUID]
    /// Eigener Name (nur Freunde-Widgets); leer = Standardtitel.
    public var name: String
    /// Gewählte Gruppe; `nil` = alle eigenen Gruppen.
    public var groupID: UUID?
    /// Ebenen des Widgets „Regionale Rankings“ (mindestens eine).
    public private(set) var regionLevels: [RegionLevel]
    /// Ebene des Ranking-Umfelds.
    public var neighborhoodLevel: RegionLevel
    public var metric: HomeActivityMetric

    /// Freunde und Gruppen für die Auswahl (geteilt mit dem Social-Tab).
    public let social: SocialViewModel

    @ObservationIgnored private let settings: HomeSettings
    @ObservationIgnored private let standings: RegionalStandingsViewModel
    @ObservationIgnored private let draftID: HomeModule.ID

    public init(mode: Mode, settings: HomeSettings, social: SocialViewModel, standings: RegionalStandingsViewModel) {
        self.mode = mode
        self.settings = settings
        self.social = social
        self.standings = standings

        let existing: HomeModule? = switch mode {
        case .add: nil
        case .edit(let id): settings.module(id: id)
        }
        if let existing {
            draftID = existing.id
            kind = existing.kind
            size = existing.size
            friendIDs = existing.configuration.friendIDs ?? []
            name = existing.configuration.customName ?? ""
            groupID = existing.configuration.groupID
            regionLevels = existing.regionLevels
            neighborhoodLevel = existing.regionLevel ?? .municipality
            metric = existing.metric
        } else {
            draftID = UUID().uuidString
            let addable = settings.addableKinds
            kind = HomeModuleKind.galleryKinds.first { addable.contains($0) } ?? .activity
            size = .medium
            friendIDs = []
            name = ""
            groupID = nil
            regionLevels = RegionLevel.allCases
            neighborhoodLevel = .municipality
            metric = .steps
        }
        neighborhoodLevel = RegionalStandingsViewModel.effectiveLevel(for: neighborhoodLevel, available: standings.scopes.map(\.level))
    }

    public var isEditing: Bool {
        mode != .add
    }

    /// Überschrift der Seite.
    public var title: String {
        isEditing ? HomeTexts.editWidget : HomeTexts.addWidget
    }

    /// Text des Hauptknopfs.
    public var saveTitle: String {
        isEditing
            ? PaceLocalization.text(de: "Änderungen sichern", en: "Save changes", ru: "Сохранить изменения")
            : HomeTexts.addWidget
    }

    // MARK: Kategorie

    public var categories: [HomeModuleKind] {
        HomeModuleKind.galleryKinds
    }

    /// Die markierte Kategorie (beim Bearbeiten der Schrittkarte „Schritte und Aktivität“).
    public var selectedCategory: HomeModuleKind {
        kind.galleryCategory
    }

    /// Beim Bearbeiten bleibt die Art fest; beim Hinzufügen lässt sich jede Kategorie wählen.
    public func isSelectable(_ category: HomeModuleKind) -> Bool {
        !isEditing || category == selectedCategory
    }

    /// Einzel-Widgets, die schon auf Home sind (z. B. die Woche).
    public func isAlreadyOnHome(_ category: HomeModuleKind) -> Bool {
        !isEditing && !category.allowsMultiple && settings.modules.contains { $0.kind == category }
    }

    public func select(_ category: HomeModuleKind) {
        guard isSelectable(category), !isEditing else { return }
        kind = category
        if !category.supportedSizes.contains(size) {
            size = category.defaultSize
        }
    }

    public var supportedSizes: [HomeModuleSize] {
        kind.supportedSizes
    }

    // MARK: Freunde

    /// Alle Freunde in der Reihenfolge des heutigen Freundesrankings, danach alphabetisch.
    public var friendChoices: [SocialProfile] {
        let profiles = social.friends.map(\.profile)
        let order = Dictionary(social.ranking.map { ($0.publicUserID, $0.rank) }, uniquingKeysWith: { first, _ in first })
        return profiles.sorted { lhs, rhs in
            switch (order[lhs.publicID], order[rhs.publicID]) {
            case let (left?, right?): left < right
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    /// Bis zu drei Freunde als Auswahl-Chips: ausgewählte zuerst, dann die übrigen.
    public var chipFriends: [SocialProfile] {
        let choices = friendChoices
        let byID = Dictionary(choices.map { ($0.publicID, $0) }, uniquingKeysWith: { first, _ in first })
        let selected = friendIDs.compactMap { byID[$0] }
        let others = choices.filter { !friendIDs.contains($0.publicID) }
        return Array((selected + others).prefix(3))
    }

    /// Ausgewählte Freunde, die nicht als Chip zu sehen sind (für „Weitere…“).
    public var additionalSelectedCount: Int {
        let shown = Set(chipFriends.map(\.publicID))
        return friendIDs.filter { !shown.contains($0) }.count
    }

    public func isSelected(friend id: UUID) -> Bool {
        friendIDs.contains(id)
    }

    public func toggleFriend(_ id: UUID) {
        if let index = friendIDs.firstIndex(of: id) {
            friendIDs.remove(at: index)
        } else {
            friendIDs.append(id)
        }
    }

    /// Hinweis unter dem Namensfeld.
    public var friendsHint: String {
        PaceLocalization.text(
            de: "Mehrere Freunde-Widgets mit eigener Auswahl möglich – ohne Gruppe.",
            en: "You can add several friends widgets, each with its own selection – no group needed.",
            ru: "Можно добавить несколько виджетов друзей со своим выбором – без группы."
        )
    }

    /// Hinweis, wenn niemand ausgewählt ist.
    public var allFriendsHint: String {
        PaceLocalization.text(
            de: "Ohne Auswahl vergleicht das Widget dich mit allen Freunden.",
            en: "Without a selection, the widget compares you with all friends.",
            ru: "Без выбора виджет сравнивает тебя со всеми друзьями."
        )
    }

    /// Platzhalter des Namensfelds.
    public var namePlaceholder: String {
        HomeModuleKind.friends.title
    }

    // MARK: Gruppen

    public var groups: [GroupSummary] {
        social.groups
    }

    // MARK: Ebenen

    /// Wählbare Ebenen: alle vier bei „Regionale Rankings“, beim Umfeld die, die es für die Region gibt.
    public var levelChoices: [RegionLevel] {
        kind == .neighborhood ? standings.availableLevels : RegionLevel.allCases
    }

    /// Name einer Ebene in der Auswahl, z. B. `Pfungstadt` oder – ohne geladene Region – `Stadt`.
    public func levelTitle(_ level: RegionLevel) -> String {
        if kind == .regionRanks {
            return level.widgetTitle
        }
        return standings.hierarchy?.allLevels.first { $0.level == level }?.localizedName ?? level.widgetTitle
    }

    public func isSelected(level: RegionLevel) -> Bool {
        kind == .neighborhood ? neighborhoodLevel == level : regionLevels.contains(level)
    }

    /// Umfeld: wählt die Ebene. Regionale Rankings: schaltet eine Ebene um (mindestens eine bleibt).
    public func toggleLevel(_ level: RegionLevel) {
        if kind == .neighborhood {
            neighborhoodLevel = level
            return
        }
        if let index = regionLevels.firstIndex(of: level) {
            guard regionLevels.count > 1 else { return }
            regionLevels.remove(at: index)
        } else {
            regionLevels = RegionLevel.allCases.filter { regionLevels.contains($0) || $0 == level }
        }
    }

    // MARK: Ergebnis

    /// Das Widget, wie es mit der aktuellen Auswahl auf Home erscheint (auch die Vorschau).
    public var draft: HomeModule {
        HomeModule(
            id: draftID,
            kind: kind,
            size: supportedSizes.contains(size) ? size : kind.defaultSize,
            regionLevel: neighborhoodLevel,
            configuration: HomeWidgetConfiguration(
                friendIDs: friendIDs,
                customName: name,
                groupID: groupID,
                regionLevels: regionLevels,
                metric: metric
            )
        )
    }

    /// Das Widget in einer anderen Größe – für die Mini-Vorschauen unter „Größe auswählen“.
    public func previewModule(size: HomeModuleSize) -> HomeModule {
        let module = draft
        return HomeModule(
            id: module.id,
            kind: module.kind,
            size: size,
            regionLevel: module.regionLevel,
            configuration: module.configuration
        )
    }

    /// Ein vorhandenes Widget, das genau dasselbe zeigt.
    public var duplicate: HomeModule? {
        settings.duplicate(of: draft)
    }

    /// Warum sich das Widget nicht hinzufügen lässt; `nil`, wenn alles passt.
    public var validationMessage: String? {
        if let duplicate {
            return PaceLocalization.text(
                de: "„\(duplicate.title)“ zeigt das schon auf deiner Übersicht.",
                en: "“\(duplicate.title)” already shows this on your overview.",
                ru: "«\(duplicate.title)» уже показывает это в твоём обзоре."
            )
        }
        if case .edit(let id) = mode, settings.module(id: id) == nil {
            return PaceLocalization.text(
                de: "Dieses Widget gibt es nicht mehr.",
                en: "This widget no longer exists.",
                ru: "Этого виджета больше нет."
            )
        }
        return nil
    }

    public var canSave: Bool {
        validationMessage == nil
    }

    /// Fügt das Widget hinzu bzw. speichert die Änderungen. `false`, wenn es nicht ging (z. B. doppelt).
    @discardableResult
    public func save() -> Bool {
        guard canSave else { return false }
        switch mode {
        case .add:
            return settings.add(draft) != nil
        case .edit:
            return settings.replace(draft)
        }
    }

    /// Lädt Freunde und Gruppen für die Auswahl (höchstens einmal pro Minute).
    public func loadIfNeeded() async {
        await social.loadIfNeeded()
    }
}
