import Foundation

/// Welches geladene Bild eine Ansicht zeigen darf (Profil-, Gruppen- und Chatbilder).
///
/// SwiftUI verwendet Ansichten wieder: Dieselbe Avatar-Ansicht zeigt nach einem Wechsel (andere Person in einer Liste,
/// anderes Gruppenbild, neues Profilbild) einen neuen Verweis. Dabei darf
/// - nie das Bild des vorherigen Verweises stehen bleiben, solange das neue lädt,
/// - ein verspätet fertiger Download eines früheren Verweises das aktuelle Bild nicht überschreiben,
/// - ein Fehlschlag nur für den Verweis gelten, bei dem er auftrat (danach Platzhalter, kein endloses Laden).
///
/// Dateinamen in Storage sind je Upload eindeutig: Ein geändertes Bild hat immer einen neuen Verweis – der Speicher
/// liefert deshalb nie ein veraltetes Bild unter dem neuen Verweis.
public struct MediaSlot<Value> {
    public enum Phase {
        /// Kein Bild vorgesehen (z. B. Profil ohne Foto) – Initialen bzw. Symbol.
        case empty
        /// Lädt (oder wartet auf den Speicher) – Platzhalter, nie ein fremdes Bild.
        case loading
        case loaded(Value)
        /// Laden fehlgeschlagen – Platzhalter, Wiederholen möglich.
        case failed
    }

    /// Verweis, den die Ansicht gerade zeigen soll.
    public private(set) var reference: MediaReference?
    private var result: (reference: MediaReference, value: Value?)?

    public init(reference: MediaReference? = nil) {
        self.reference = reference
    }

    /// Die Ansicht soll jetzt diesen Verweis zeigen. Ein geladenes Bild eines anderen Verweises wird verworfen.
    public mutating func show(_ reference: MediaReference?) {
        self.reference = reference
        if result?.reference != reference { result = nil }
    }

    /// Ergebnis eines Ladevorgangs (`nil` = fehlgeschlagen). Übernommen wird es nur, wenn es zum aktuellen Verweis
    /// gehört – ein verspäteter Download eines früheren Verweises ändert nichts.
    /// - Returns: `true`, wenn das Ergebnis übernommen wurde.
    @discardableResult
    public mutating func deliver(_ value: Value?, for reference: MediaReference) -> Bool {
        guard reference == self.reference else { return false }
        result = (reference, value)
        return true
    }

    /// Vor einem neuen Versuch (z. B. „Erneut versuchen“): Fehlschlag vergessen, wieder laden.
    public mutating func retry() {
        if case .failed = phase { result = nil }
    }

    public var phase: Phase {
        guard let reference else { return .empty }
        guard let result, result.reference == reference else { return .loading }
        if let value = result.value { return .loaded(value) }
        return .failed
    }

    /// Das geladene Bild des aktuellen Verweises.
    public var value: Value? {
        if case .loaded(let value) = phase { return value }
        return nil
    }

    public var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }
}
