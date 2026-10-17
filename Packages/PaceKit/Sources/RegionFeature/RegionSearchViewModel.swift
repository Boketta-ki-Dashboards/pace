import Foundation
import Observation
import PaceCore

/// Gemeindesuche mit Auswahl. Wird im Onboarding und beim Ändern der Region verwendet.
///
/// Gespeichert wird von den Aufrufern ausschließlich die ID der gewählten Gemeinde; Kreis, Bundesland und Land
/// ergeben sich aus der Hierarchie.
@MainActor
@Observable
public final class RegionSearchViewModel {
    public enum State: Equatable {
        case idle
        case searching
        case results([RegionHierarchy])
        case noResults(query: String)
        case failed(message: String)
    }

    public private(set) var state: State = .idle
    public private(set) var selection: RegionHierarchy?

    @ObservationIgnored private let regions: any RegionRepository
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let resultLimit: Int
    @ObservationIgnored private var lastQuery: String?
    @ObservationIgnored private var generation = 0

    public init(regions: any RegionRepository, debounce: Duration = .milliseconds(300), resultLimit: Int = 20) {
        self.regions = regions
        self.debounce = debounce
        self.resultLimit = resultLimit
    }

    /// Sucht nach kurzer Pause. Wird die Suche währenddessen abgebrochen (z. B. durch `.task(id:)` bei neuer
    /// Eingabe) oder durch eine neuere Suche überholt, bleibt ihr Ergebnis unbeachtet.
    public func search(_ rawQuery: String) async {
        generation += 1
        let current = generation

        guard let query = RegionSearchQuery.normalized(rawQuery) else {
            lastQuery = nil
            state = .idle
            return
        }
        lastQuery = query

        if debounce > .zero {
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
        }
        guard current == generation else { return }

        state = .searching
        do {
            let results = try await regions.searchMunicipalities(matching: query, limit: resultLimit)
            guard current == generation, !Task.isCancelled else { return }
            state = results.isEmpty ? .noResults(query: query) : .results(results)
        } catch {
            guard current == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            state = .failed(message: Self.message(for: error))
        }
    }

    /// Wiederholt die letzte Suche, z. B. nach einem Verbindungsfehler.
    public func retry() async {
        guard let lastQuery else { return }
        await search(lastQuery)
    }

    public func select(_ hierarchy: RegionHierarchy) {
        selection = hierarchy
    }

    public func clearSelection() {
        selection = nil
    }

    static func message(for error: Error) -> String {
        if error as? RegionError == .network {
            return "Keine Verbindung. Prüfe deine Internetverbindung und versuche es erneut."
        }
        return "Die Suche ist gerade nicht möglich. Bitte versuche es erneut."
    }
}
