import ActivityFeature
import Foundation
import Observation
import PaceCore

/// Das Home-Dashboard: Bewegungsdaten, Tagesziel, regionale Platzierungen und die vom Nutzer gewählten Bereiche.
///
/// Die einzelnen Bereiche sind eigenständig (`HomeSection`) und lassen sich über „Anpassen“ ein- und ausblenden oder
/// umsortieren. Neue Bereiche (z. B. Challenges) kommen als weiterer Fall hinzu.
@MainActor
@Observable
public final class HomeDashboardViewModel {
    /// Offene Sheets.
    public enum Sheet: String, Identifiable, Sendable {
        case customize
        case stepGoal
        case notifications

        public var id: String { rawValue }
    }

    public var presentedSheet: Sheet?

    public let activity: HomeViewModel
    public let standings: RegionalStandingsViewModel
    public let settings: HomeSettings

    @ObservationIgnored private let store: ProfileStore
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let formatter: ActivityFormatter
    @ObservationIgnored private let onOpenRankings: @MainActor (Region?) -> Void
    @ObservationIgnored private let onOpenSocial: @MainActor () -> Void

    /// - Parameters:
    ///   - onOpenRankings: Wechselt zum Rankings-Tab, optional mit einer bestimmten Ebene.
    ///   - onOpenSocial: Wechselt zum Social-Tab.
    public init(
        activity: HomeViewModel,
        standings: RegionalStandingsViewModel,
        settings: HomeSettings,
        store: ProfileStore,
        calendar: ActivityCalendar = ActivityCalendar(),
        formatter: ActivityFormatter = ActivityFormatter(),
        onOpenRankings: @escaping @MainActor (Region?) -> Void = { _ in },
        onOpenSocial: @escaping @MainActor () -> Void = {}
    ) {
        self.activity = activity
        self.standings = standings
        self.settings = settings
        self.store = store
        self.calendar = calendar
        self.formatter = formatter
        self.onOpenRankings = onOpenRankings
        self.onOpenSocial = onOpenSocial
    }

    /// z. B. `Hi Niklas` (erster Teil des Anzeigenamens).
    public var greeting: String {
        let first = store.profile.displayName.split(separator: " ").first.map(String.init) ?? store.profile.displayName
        return "Hi \(first)"
    }

    public var stepsToday: StepsTodaySummary? {
        activity.overview.map { StepsTodaySummary(today: $0.today, goal: settings.stepGoal, formatter: formatter) }
    }

    public var week: WeekOverview? {
        activity.overview.map { WeekOverview(overview: $0, goal: settings.stepGoal, calendar: calendar, formatter: formatter) }
    }

    public var visibleSections: [HomeSection] {
        settings.visibleSections
    }

    /// Ändert sich, wenn die Platzierungen neu geladen werden müssen.
    public var standingsReloadKey: RegionalStandingsViewModel.ReloadKey {
        standings.reloadKey
    }

    /// Platzierungen werden nur geladen, wenn ein Bereich sie anzeigt.
    public var showsStandings: Bool {
        visibleSections.contains(.regionRanks) || visibleSections.contains(.neighborhood)
    }

    /// Erstes Laden beim Erscheinen.
    public func loadIfNeeded() async {
        guard showsStandings else { return }
        await standings.loadIfNeeded()
    }

    /// Pull-to-Refresh: Schritte neu aus Apple Health lesen, an den Sync übergeben, Platzierungen neu laden.
    public func refresh() async {
        await activity.refreshForRanking()
        guard showsStandings else { return }
        await standings.load()
    }

    /// Zurück in der App: zuerst die Schritte lesen und übergeben, dann – falls älter als eine Minute – die
    /// Platzierungen, damit sie die neuen Schritte schon enthalten.
    public func returnedToForeground() async {
        await activity.refresh(trigger: .foreground)
        await activity.waitForPendingSync()
        guard showsStandings else { return }
        await standings.refreshIfStale()
    }

    /// Neue Schritte sind da: Platzierungen höchstens einmal pro Minute nachladen.
    public func stepsDidChange() async {
        guard showsStandings else { return }
        await activity.waitForPendingSync()
        await standings.refreshIfStale()
    }

    public func openRankings(_ scope: Region? = nil) {
        onOpenRankings(scope)
    }

    public func openSocial() {
        onOpenSocial()
    }

    public func present(_ sheet: Sheet) {
        presentedSheet = sheet
    }
}
