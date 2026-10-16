import Foundation
import PaceCore

/// Quelle der aktuellen Bewegungsdaten für die Detailansicht (in der App: das Home-ViewModel).
///
/// So zeigt die Detailansicht immer denselben, live aktualisierten Stand wie Home, ohne selbst zu laden.
@MainActor
public protocol ActivityOverviewSource: AnyObject, Sendable {
    var overview: ActivityOverview? { get }
    func refresh() async
}
