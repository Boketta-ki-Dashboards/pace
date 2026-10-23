import Foundation

/// Scrollverhalten im Chat ohne SwiftUI (testbar): Bleibt der Verlauf am unteren Ende „angeheftet“, wandern neue
/// Nachrichten mit; liest man ältere Nachrichten, erscheint stattdessen ein Hinweis „Neue Nachrichten“.
///
/// Ob man unten ist, wird nur aus echten Scroll-Bewegungen abgeleitet (Inhalt und sichtbarer Bereich unverändert).
/// Wächst der Inhalt (neue Nachricht, nachgeladenes Bild) oder schrumpft der sichtbare Bereich (Tastatur), bleibt der
/// bisherige Zustand – sonst sähe eine gerade eingetroffene Nachricht so aus, als hätte man nach oben gescrollt.
public struct ChatScrollTracker: Equatable, Sendable {
    /// Abstand zur Unterkante, bis zu dem man noch als „unten“ gilt.
    public static let pinThreshold: CGFloat = 56

    public private(set) var isPinnedToBottom = true
    public private(set) var hasUnseenMessages = false
    private var contentHeight: CGFloat?
    private var viewportHeight: CGFloat?

    public init() {}

    /// Neue Geometrie des Verlaufs.
    /// - Parameters:
    ///   - contentBottom: Unterkante des Inhalts, gemessen ab der Oberkante des sichtbaren Bereichs.
    ///   - contentHeight: Höhe des Inhalts.
    ///   - viewportHeight: Höhe des sichtbaren Bereichs.
    /// - Returns: `true`, wenn der Verlauf ans Ende scrollen soll, weil sich Inhalt oder sichtbarer Bereich geändert
    ///   haben, während er unten angeheftet war.
    @discardableResult
    public mutating func update(contentBottom: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        let layoutChanged = !Self.same(contentHeight, self.contentHeight) || !Self.same(viewportHeight, self.viewportHeight)
        self.contentHeight = contentHeight
        self.viewportHeight = viewportHeight
        if layoutChanged {
            return isPinnedToBottom
        }
        isPinnedToBottom = contentBottom - viewportHeight <= Self.pinThreshold
        if isPinnedToBottom {
            hasUnseenMessages = false
        }
        return false
    }

    /// Eine neue unterste Nachricht ist da.
    /// - Returns: `true`, wenn ans Ende gescrollt werden soll (erstes Laden, eigene Nachricht oder schon unten).
    public mutating func newLastEntry(isOwn: Bool, isFirstEntry: Bool) -> Bool {
        if isFirstEntry || isOwn || isPinnedToBottom {
            isPinnedToBottom = true
            hasUnseenMessages = false
            return true
        }
        hasUnseenMessages = true
        return false
    }

    /// Der Nutzer springt über den Hinweis ans Ende.
    public mutating func scrolledToBottom() {
        isPinnedToBottom = true
        hasUnseenMessages = false
    }

    private static func same(_ value: CGFloat, _ previous: CGFloat?) -> Bool {
        guard let previous else { return false }
        return abs(value - previous) < 0.5
    }
}
