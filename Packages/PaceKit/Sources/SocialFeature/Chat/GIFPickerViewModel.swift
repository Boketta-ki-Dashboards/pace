import Foundation
import Observation
import PaceCore

/// GIF-Auswahl im Chat: Suchfeld, echte Treffer des Anbieters (ohne Suchbegriff beliebte GIFs), Vorschau des
/// gewählten GIFs und Senden. Ohne eingerichtete Suche oder ohne Verbindung steht dort ein ehrlicher Hinweis – nie
/// Platzhalter-Bilder.
///
/// Arbeitsspeicher: Das Raster zeigt kleine Standbilder; animiert wird nur das eine gewählte GIF. Nachgeladen wird in
/// Seiten bis höchstens ``GIFRules/maximumResults``.
@MainActor
@Observable
public final class GIFPickerViewModel {
    public enum Phase: Equatable, Sendable {
        case loading
        case loaded
        /// Keine Treffer für den Suchbegriff.
        case empty
        case failed(GIFSearchError)
    }

    /// Das gewählte GIF und – sobald geladen – die Datei zum Senden.
    public struct Selection: Equatable, Sendable {
        public let result: GIFSearchResult
        public var data: Data?
        public var error: GIFSearchError?
    }

    /// Eingabe im Suchfeld.
    public var query = ""
    public private(set) var results: [GIFSearchResult] = []
    public private(set) var phase: Phase
    public private(set) var isLoadingMore = false
    public private(set) var selection: Selection?

    @ObservationIgnored private let search: (any GIFSearching)?
    /// Suchbegriff der angezeigten Treffer (`nil` = beliebte GIFs).
    @ObservationIgnored private var loadedQuery: String??
    @ObservationIgnored private var reachedEnd = false

    public init(search: (any GIFSearching)?) {
        self.search = search
        phase = search == nil ? .failed(.notConfigured) : .loading
    }

    public var isAvailable: Bool {
        search != nil
    }

    public var attribution: String? {
        search?.attribution
    }

    public var privacyNote: String? {
        search?.privacyNote
    }

    // MARK: Suche

    /// Lädt die erste Seite für den aktuellen Suchbegriff (die Ansicht ruft das verzögert nach der letzten Eingabe auf).
    public func load() async {
        guard let search else { return }
        let cleaned = GIFRules.query(query)
        if loadedQuery == .some(cleaned), phase == .loaded || phase == .empty { return }
        phase = .loading
        do throws(GIFSearchError) {
            let page: [GIFSearchResult]
            if let cleaned {
                page = try await search.search(cleaned, limit: GIFRules.pageSize, offset: 0)
            } else {
                page = try await search.trending(limit: GIFRules.pageSize, offset: 0)
            }
            // Inzwischen anders gesucht: Ergebnis verwerfen.
            guard GIFRules.query(query) == cleaned else { return }
            results = Self.unique(page)
            loadedQuery = .some(cleaned)
            reachedEnd = page.count < GIFRules.pageSize
            phase = results.isEmpty ? .empty : .loaded
        } catch {
            guard GIFRules.query(query) == cleaned, !Task.isCancelled else { return }
            phase = .failed(error)
        }
    }

    /// Nächste Seite, sobald das Raster beim Scrollen das Ende erreicht.
    public func loadMoreIfNeeded(after result: GIFSearchResult) async {
        guard let search, phase == .loaded, !isLoadingMore, !reachedEnd,
              results.count < GIFRules.maximumResults,
              results.suffix(6).contains(result),
              case .some(let shown) = loadedQuery
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let offset = results.count
        do throws(GIFSearchError) {
            let page: [GIFSearchResult]
            if let shown {
                page = try await search.search(shown, limit: GIFRules.pageSize, offset: offset)
            } else {
                page = try await search.trending(limit: GIFRules.pageSize, offset: offset)
            }
            guard loadedQuery == .some(shown) else { return }
            let known = Set(results.map(\.id))
            results += page.filter { !known.contains($0.id) }
            if results.count > GIFRules.maximumResults {
                results = Array(results.prefix(GIFRules.maximumResults))
            }
            reachedEnd = page.count < GIFRules.pageSize || results.count >= GIFRules.maximumResults
        } catch {
            // Nachladen ist optional: Die vorhandenen Treffer bleiben stehen.
            reachedEnd = true
        }
    }

    // MARK: Auswahl

    /// Wählt ein GIF und lädt die Datei zum Senden (geprüft: GIF, Größengrenze des Chats).
    public func select(_ result: GIFSearchResult) async {
        guard let search else { return }
        selection = Selection(result: result, data: nil, error: nil)
        do throws(GIFSearchError) {
            let data = try await search.download(result, maximumBytes: MediaRules.maximumChatBytes)
            guard selection?.result == result else { return }
            selection?.data = data
        } catch {
            guard selection?.result == result else { return }
            selection?.error = error
        }
    }

    public func clearSelection() {
        selection = nil
    }

    /// Daten des gewählten GIFs zum Senden; `nil`, solange sie nicht (fehlerfrei) geladen sind.
    public var dataToSend: Data? {
        guard let selection, selection.error == nil else { return nil }
        return selection.data
    }

    // MARK: Texte

    public static func message(for error: GIFSearchError) -> String {
        switch error {
        case .notConfigured:
            PaceLocalization.text(
                de: "Die GIF-Suche ist in dieser App-Version nicht eingerichtet. Fotos und GIFs aus deiner Mediathek kannst du weiterhin senden.",
                en: "GIF search isn't set up in this version of the app. You can still send photos and GIFs from your library.",
                ru: "Поиск GIF не настроен в этой версии приложения. Фото и GIF из медиатеки по-прежнему можно отправлять."
            )
        case .offline:
            PaceLocalization.text(
                de: "Keine Internetverbindung. Prüfe deine Verbindung und versuche es erneut.",
                en: "No internet connection. Check your connection and try again.",
                ru: "Нет подключения к интернету. Проверь соединение и попробуй ещё раз."
            )
        case .rateLimited:
            PaceLocalization.text(
                de: "Gerade zu viele Suchanfragen. Versuche es in ein paar Minuten erneut.",
                en: "Too many searches right now. Try again in a few minutes.",
                ru: "Сейчас слишком много запросов. Попробуй через несколько минут."
            )
        case .unsuitableFile:
            PaceLocalization.text(
                de: "Dieses GIF lässt sich nicht senden (zu groß oder beschädigt). Wähle ein anderes.",
                en: "This GIF can't be sent (too large or damaged). Choose another one.",
                ru: "Этот GIF нельзя отправить (слишком большой или повреждён). Выбери другой."
            )
        case .failed:
            PaceLocalization.text(
                de: "GIFs konnten nicht geladen werden. Versuche es erneut.",
                en: "GIFs couldn't be loaded. Please try again.",
                ru: "Не удалось загрузить GIF. Попробуй ещё раз."
            )
        }
    }

    private static func unique(_ results: [GIFSearchResult]) -> [GIFSearchResult] {
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
    }
}
