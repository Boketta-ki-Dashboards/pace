import Foundation

/// Regeln für Navigationspfade (ohne SwiftUI): Dieselbe Seite liegt nie zweimal auf dem Stapel.
///
/// Öffnet man eine Seite, die im Pfad schon liegt, geht es dorthin zurück, statt sie erneut aufzulegen. So entstehen
/// keine Kreisläufe wie Gruppe → Chat → Gruppe → Chat …, der Pfad bleibt begrenzt und der Rückweg ist der, auf dem man
/// gekommen ist. Doppeltes Tippen auf denselben Link ändert nichts.
public enum PaceNavigationRules {
    /// Pfad nach dem Öffnen von `item`.
    ///
    /// - Liegt dieselbe Seite schon oben: unverändert (z. B. doppeltes Tippen).
    /// - Liegt sie weiter unten: zurück bis zu ihr (die Seiten darüber werden geschlossen).
    /// - Sonst: oben aufgelegt.
    public static func opening<Item>(_ item: Item, in path: [Item], isSamePage: (Item, Item) -> Bool) -> [Item] {
        if let index = path.firstIndex(where: { isSamePage($0, item) }) {
            return Array(path.prefix(through: index))
        }
        return path + [item]
    }

    /// Ersetzt die oberste Seite durch `item` (z. B. „Gruppe erstellen“ → die neue Gruppe). Liegt das Ziel schon
    /// darunter, geht es stattdessen dorthin zurück.
    public static func replacingTop<Item>(with item: Item, in path: [Item], isSamePage: (Item, Item) -> Bool) -> [Item] {
        opening(item, in: Array(path.dropLast()), isSamePage: isSamePage)
    }

    public static func opening<Item: Equatable>(_ item: Item, in path: [Item]) -> [Item] {
        opening(item, in: path, isSamePage: ==)
    }
}
