import Foundation
import Observation
import PaceCore

/// Ein entferntes Widget mit seiner bisherigen Position – für „Rückgängig“.
public struct RemovedHomeModule: Equatable, Sendable {
    public let module: HomeModule
    public let index: Int

    public init(module: HomeModule, index: Int) {
        self.module = module
        self.index = index
    }
}

/// Aufbau des Dashboards, live für alle Ansichten. Jede Änderung wird sofort gespeichert.
@MainActor
@Observable
public final class HomeSettings {
    public private(set) var preferences: HomePreferences

    @ObservationIgnored private let store: any HomePreferencesStoring

    public init(store: any HomePreferencesStoring) {
        self.store = store
        preferences = (store.load() ?? HomePreferences()).normalized()
    }

    /// Alle Widgets in Nutzer-Reihenfolge.
    public var modules: [HomeModule] { preferences.modules }

    public func module(id: HomeModule.ID) -> HomeModule? {
        preferences.modules.first { $0.id == id }
    }

    /// Arten, die sich (noch) hinzufügen lassen: Mehrfach-Widgets immer, alle anderen nur, solange sie fehlen.
    public var addableKinds: [HomeModuleKind] {
        HomeModuleKind.allCases.filter { kind in
            kind.allowsMultiple || !preferences.modules.contains { $0.kind == kind }
        }
    }

    /// Ein anderes vorhandenes Widget, das genau dasselbe zeigt (z. B. dieselbe Gruppe) – dann wäre dieses doppelt.
    public func duplicate(of module: HomeModule) -> HomeModule? {
        guard let key = module.uniquenessKey else { return nil }
        return preferences.modules.first { $0.id != module.id && $0.uniquenessKey == key }
    }

    /// Ob das Widget so hinzugefügt werden kann (passende Größe, keine Dopplung).
    public func canAdd(_ module: HomeModule) -> Bool {
        module.kind.supportedSizes.contains(module.size) && duplicate(of: module) == nil
    }

    /// Fügt ein Widget der Art mit Standardgröße und -konfiguration am Ende hinzu.
    @discardableResult
    public func add(_ kind: HomeModuleKind) -> HomeModule? {
        guard addableKinds.contains(kind) else { return nil }
        return add(HomeModule(kind: kind))
    }

    /// Fügt ein fertig konfiguriertes Widget (aus der Widget-Galerie) am Ende hinzu; `nil`, wenn es doppelt wäre.
    @discardableResult
    public func add(_ module: HomeModule) -> HomeModule? {
        guard canAdd(module), !preferences.modules.contains(where: { $0.id == module.id }) else { return nil }
        update { $0.modules.append(module) }
        return preferences.modules.first { $0.id == module.id }
    }

    /// Ersetzt Größe und Konfiguration eines vorhandenen Widgets (Bearbeiten in der Galerie); Position und ID bleiben.
    @discardableResult
    public func replace(_ module: HomeModule) -> Bool {
        guard let index = preferences.modules.firstIndex(where: { $0.id == module.id }),
              preferences.modules[index].kind == module.kind,
              module.kind.supportedSizes.contains(module.size),
              duplicate(of: module) == nil
        else { return false }
        update { $0.modules[index] = module }
        return true
    }

    /// Entfernt ein Widget (nicht die Schrittkarte). Gibt es mit Position zurück, damit es sich wiederherstellen lässt.
    @discardableResult
    public func remove(_ id: HomeModule.ID) -> RemovedHomeModule? {
        guard let index = preferences.modules.firstIndex(where: { $0.id == id }),
              preferences.modules[index].kind.isRemovable
        else { return nil }
        let removed = RemovedHomeModule(module: preferences.modules[index], index: index)
        update { $0.modules.remove(at: index) }
        return removed
    }

    /// „Rückgängig“: setzt ein entferntes Widget an seine alte Position zurück.
    public func restore(_ removed: RemovedHomeModule) {
        guard !preferences.modules.contains(where: { $0.id == removed.module.id }),
              duplicate(of: removed.module) == nil
        else { return }
        update { preferences in
            preferences.modules.insert(removed.module, at: min(max(removed.index, 0), preferences.modules.count))
        }
    }

    public func setSize(_ size: HomeModuleSize, for id: HomeModule.ID) {
        update { preferences in
            guard let index = preferences.modules.firstIndex(where: { $0.id == id }),
                  preferences.modules[index].kind.supportedSizes.contains(size)
            else { return }
            preferences.modules[index].size = size
        }
    }

    public func setRegionLevel(_ level: RegionLevel, for id: HomeModule.ID) {
        update { preferences in
            guard let index = preferences.modules.firstIndex(where: { $0.id == id }),
                  preferences.modules[index].kind.usesRegionScope
            else { return }
            preferences.modules[index].regionLevel = level
        }
    }

    /// Neue Konfiguration für ein Widget; doppelte Widgets entstehen dabei nicht.
    @discardableResult
    public func setConfiguration(_ configuration: HomeWidgetConfiguration, for id: HomeModule.ID) -> Bool {
        guard let current = module(id: id) else { return false }
        let changed = HomeModule(
            id: current.id,
            kind: current.kind,
            size: current.size,
            regionLevel: current.regionLevel,
            configuration: configuration
        )
        return replace(changed)
    }

    /// Verschiebt Widgets wie `List.onMove`.
    public func moveModules(fromOffsets source: IndexSet, toOffset destination: Int) {
        update { preferences in
            let moving = source.sorted().filter { $0 < preferences.modules.count }.map { preferences.modules[$0] }
            var remaining = preferences.modules.enumerated().filter { !source.contains($0.offset) }.map(\.element)
            let insertion = destination - source.filter { $0 < destination }.count
            remaining.insert(contentsOf: moving, at: min(max(insertion, 0), remaining.count))
            preferences.modules = remaining
        }
    }

    /// Drag & Drop: legt das Widget an die Stelle des Ziel-Widgets. Von oben kommend landet es danach, von unten
    /// kommend davor – wie auf dem iPhone-Homescreen.
    public func move(_ id: HomeModule.ID, to targetID: HomeModule.ID) {
        guard id != targetID,
              let source = preferences.modules.firstIndex(where: { $0.id == id }),
              let target = preferences.modules.firstIndex(where: { $0.id == targetID })
        else { return }
        moveModules(fromOffsets: [source], toOffset: target > source ? target + 1 : target)
    }

    /// Ziehgriff: legt das Widget an die Position `index` der Reihenfolge (0 = ganz oben). Gespeichert wird sofort.
    public func move(_ id: HomeModule.ID, toIndex index: Int) {
        guard let source = preferences.modules.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index, 0), preferences.modules.count - 1)
        guard target != source else { return }
        moveModules(fromOffsets: [source], toOffset: target > source ? target + 1 : target)
    }

    public func canMoveUp(_ id: HomeModule.ID) -> Bool {
        (preferences.modules.firstIndex { $0.id == id } ?? 0) > 0
    }

    public func canMoveDown(_ id: HomeModule.ID) -> Bool {
        guard let index = preferences.modules.firstIndex(where: { $0.id == id }) else { return false }
        return index < preferences.modules.count - 1
    }

    /// Eine Position nach oben (VoiceOver-Aktion als Alternative zum Ziehen).
    public func moveUp(_ id: HomeModule.ID) {
        guard let index = preferences.modules.firstIndex(where: { $0.id == id }), index > 0 else { return }
        moveModules(fromOffsets: [index], toOffset: index - 1)
    }

    /// Eine Position nach unten (VoiceOver-Aktion als Alternative zum Ziehen).
    public func moveDown(_ id: HomeModule.ID) {
        guard let index = preferences.modules.firstIndex(where: { $0.id == id }),
              index < preferences.modules.count - 1
        else { return }
        moveModules(fromOffsets: [index], toOffset: index + 2)
    }

    public func resetLayout() {
        update { $0.modules = HomePreferences.defaultModules() }
    }

    /// Plätze über und unter dem eigenen, die je Ebene geladen werden müssen: für Umfeld-Widgets ihre Zeilen, für
    /// große Platzierungs-Widgets der Platz darüber (Abstand zum nächsten Platz).
    public var neighborhoodRadii: [RegionLevel: Int] {
        preferences.modules.reduce(into: [:]) { radii, module in
            switch module.kind {
            case .neighborhood:
                guard let level = module.regionLevel else { return }
                radii[level] = max(radii[level] ?? 0, module.neighborhoodRadius)
            case .regionRanks where module.size >= .large:
                for level in module.regionLevels {
                    radii[level] = max(radii[level] ?? 0, 1)
                }
            default:
                return
            }
        }
    }

    /// Ob ein Widget Platzierungen anzeigt (sonst werden keine geladen).
    public var showsStandings: Bool {
        preferences.modules.contains { $0.kind.showsRegionalRankings }
    }

    private func update(_ change: (inout HomePreferences) -> Void) {
        var updated = preferences
        change(&updated)
        updated = updated.normalized()
        guard updated != preferences else { return }
        preferences = updated
        store.save(updated)
    }
}
