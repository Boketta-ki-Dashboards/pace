import Foundation
import Observation
import PaceCore

/// „Freund hinzufügen“ (Referenzbild 1): Präfixsuche nach Benutzernamen mit Verzögerung beim Tippen.
///
/// Gesucht wird erst ab drei Zeichen und erst, wenn eine kurze Pause eintritt; es zählt nur die Antwort auf die zuletzt
/// gestellte Anfrage – eine langsame ältere Antwort überschreibt nie die neuere. Aktionen (Anfrage senden, annehmen,
/// blockieren) laufen über ``SocialViewModel``; danach wird die Suche mit dem Stand des Servers wiederholt.
@MainActor
@Observable
public final class FriendSearchViewModel {
    public enum State: Equatable {
        /// Noch keine (ausreichend lange) Eingabe.
        case idle
        case searching
        case results([ProfileSearchResult])
        /// Keine Treffer: Text für den Hinweis.
        case empty(String)
        case failed(String)
    }

    /// Eingabe im Suchfeld. Jede Änderung startet (verzögert) eine neue Suche.
    public var query = "" {
        didSet {
            if query != oldValue { scheduleSearch() }
        }
    }

    public private(set) var state: State = .idle

    @ObservationIgnored private let repository: any SocialRepository
    @ObservationIgnored private weak var social: SocialViewModel?
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// Zählt gestartete Suchen; nur die Antwort der neuesten wird angezeigt.
    @ObservationIgnored private var generation = 0

    public init(repository: any SocialRepository, social: SocialViewModel?, debounce: Duration = .milliseconds(350)) {
        self.repository = repository
        self.social = social
        self.debounce = debounce
    }

    /// Suchbegriff ohne Leerzeichen am Rand und ohne führendes „@“.
    public var normalizedQuery: String {
        SocialViewModel.normalizedQuery(query)
    }

    public var results: [ProfileSearchResult] {
        if case .results(let results) = state { return results }
        return []
    }

    /// Hinweis unter dem Suchfeld, solange noch nicht gesucht wird.
    public var hint: String? {
        guard state == .idle else { return nil }
        return SocialText.searchHint
    }

    public func clear() {
        query = ""
    }

    /// Sucht sofort (z. B. nach „Suchen“ auf der Tastatur oder „Erneut versuchen“).
    public func searchNow() async {
        searchTask?.cancel()
        searchTask = nil
        await search(normalizedQuery)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let term = normalizedQuery
        guard Self.isSearchable(term) else {
            generation += 1
            state = term.count < UsernameRules.minLength ? .idle : .empty(SocialText.nobodyStartsWith(term))
            return
        }
        let delay = debounce
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.search(term)
        }
    }

    /// Mindestens drei Zeichen, nur Zeichen, die in Benutzernamen vorkommen können.
    static func isSearchable(_ term: String) -> Bool {
        term.count >= UsernameRules.minLength
            && term.count <= UsernameRules.maxLength
            && term.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    private func search(_ term: String) async {
        generation += 1
        let current = generation
        guard Self.isSearchable(term) else {
            state = term.count < UsernameRules.minLength ? .idle : .empty(SocialText.nobodyStartsWith(term))
            return
        }
        // Vorhandene Treffer bleiben stehen, bis die neue Antwort da ist – die Liste springt so nicht.
        if results.isEmpty {
            state = .searching
        }
        do {
            let found = try await repository.searchProfiles(query: term)
            guard current == generation else { return }
            state = found.isEmpty ? .empty(SocialText.nobodyStartsWith(term)) : .results(found)
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            state = .failed(SocialText.message(for: error))
        }
    }

    // MARK: Aktionen

    public func isBusy(_ result: ProfileSearchResult) -> Bool {
        guard let social else { return false }
        return social.busyIDs.contains(result.profile.publicID) || requestID(for: result).map(social.busyIDs.contains) == true
    }

    /// Offene Anfrage zu einem Treffer – vom Server oder aus den geladenen Anfragen.
    public func requestID(for result: ProfileSearchResult) -> UUID? {
        if let id = result.requestID { return id }
        return social?.requests.first { $0.profile.publicID == result.profile.publicID }?.id
    }

    /// „Hinzufügen“: sendet eine Freundschaftsanfrage und zeigt danach den Stand des Servers.
    @discardableResult
    public func add(_ result: ProfileSearchResult) async -> Bool {
        guard let social, let outcome = await social.sendRequest(to: result.profile) else { return false }
        let relationship: SocialRelationship = switch outcome {
        case .requested, .alreadyRequested: .outgoingRequest
        case .accepted, .alreadyFriends: .friend
        }
        replace(result.profile.publicID, with: relationship)
        await refresh()
        return true
    }

    /// „Annehmen“ bei einer eingehenden Anfrage.
    @discardableResult
    public func accept(_ result: ProfileSearchResult) async -> Bool {
        guard let social, let requestID = requestID(for: result) else { return false }
        let accepted = await social.respondToRequest(requestID, from: result.profile, accept: true)
        if accepted { replace(result.profile.publicID, with: .friend) }
        await refresh()
        return accepted
    }

    /// „Nutzer blockieren“: Die Person verschwindet aus den Treffern.
    @discardableResult
    public func block(_ result: ProfileSearchResult) async -> Bool {
        guard let social else { return false }
        let blocked = await social.block(result.profile)
        if blocked, case .results(let results) = state {
            let remaining = results.filter { $0.id != result.id }
            state = remaining.isEmpty ? .empty(SocialText.nobodyStartsWith(normalizedQuery)) : .results(remaining)
        }
        return blocked
    }

    /// Nachricht schreiben – nur unter Freunden.
    public func chatTarget(for result: ProfileSearchResult) -> ChatTarget? {
        result.relationship == .friend ? .direct(result.profile) : nil
    }

    /// Wiederholt die Suche ohne Verzögerung, damit Beziehungen dem Server entsprechen.
    private func refresh() async {
        let term = normalizedQuery
        guard Self.isSearchable(term) else { return }
        await search(term)
    }

    /// Übernimmt die Antwort des Servers auf eine Aktion sofort in den Treffer.
    private func replace(_ publicID: UUID, with relationship: SocialRelationship) {
        guard case .results(let results) = state else { return }
        state = .results(results.map { result in
            result.profile.publicID == publicID
                ? ProfileSearchResult(profile: result.profile, relationship: relationship, requestID: relationship == .friend ? nil : result.requestID)
                : result
        })
    }
}
