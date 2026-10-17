import Foundation
import PaceCore

/// Was die Detailansicht zeigt.
public enum ActivityDetailsState: Equatable, Sendable {
    case loading
    /// Werte, optional mit Hinweis – z. B. wenn die letzte Aktualisierung fehlschlug und ältere Werte zu sehen sind.
    case loaded(ActivityOverview, notice: String?)
    /// Keine Werte verfügbar (Fehler ohne frühere Werte oder kein Lesezugriff).
    case unavailable(message: String)
}

/// Quelle der aktuellen Bewegungsdaten für die Detailansicht (in der App: das Home-ViewModel).
///
/// So zeigt die Detailansicht immer denselben, live aktualisierten Stand wie Home, ohne selbst zu laden.
@MainActor
public protocol ActivityOverviewSource: AnyObject, Sendable {
    var detailsState: ActivityDetailsState { get }
    func refresh() async
}
