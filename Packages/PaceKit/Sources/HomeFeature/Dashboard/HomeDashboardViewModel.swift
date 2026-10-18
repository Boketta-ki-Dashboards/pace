import ActivityFeature
import Foundation
import Observation
import PaceCore

/// Das Home-Dashboard: Bewegungsdaten, Tagesziel, Serie, regionale Platzierungen und die vom Nutzer gewählten Module.
///
/// Die Module sind eigenständig (`HomeModule`) und lassen sich über „Anpassen“ hinzufügen, entfernen, verschieben
/// und in der Größe ändern. Neue Module (z. B. Challenges) kommen als weitere Art hinzu.
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
    /// Tagesziel mit Verlauf.
    public let goals: StepGoalSettings
    /// Persönliche Streak und Bewegungsverlauf (geteilt mit Statistik und Profil).
    public let streak: StepStreakTracker

    @ObservationIgnored private let activityData: any ActivityDataProviding
    @ObservationIgnored private let store: ProfileStore
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let formatter: ActivityFormatter
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let onOpenRankings: @MainActor (Region?) -> Void
    @ObservationIgnored private let onOpenSocial: @MainActor () -> Void

    /// - Parameters:
    ///   - onOpenRankings: Wechselt zum Rankings-Tab, optional mit einer bestimmten Ebene.
    ///   - onOpenSocial: Wechselt zum Social-Tab.
    public init(
        activity: HomeViewModel,
        standings: RegionalStandingsViewModel,
        settings: HomeSettings,
        streak: StepStreakTracker,
        activityData: any ActivityDataProviding,
        store: ProfileStore,
        calendar: ActivityCalendar = ActivityCalendar(),
        formatter: ActivityFormatter = ActivityFormatter(),
        now: @escaping @Sendable () -> Date = { Date() },
        onOpenRankings: @escaping @MainActor (Region?) -> Void = { _ in },
        onOpenSocial: @escaping @MainActor () -> Void = {}
    ) {
        self.activity = activity
        self.standings = standings
        self.settings = settings
        self.streak = streak
        goals = streak.goals
        self.activityData = activityData
        self.store = store
        self.calendar = calendar
        self.formatter = formatter
        self.now = now
        self.onOpenRankings = onOpenRankings
        self.onOpenSocial = onOpenSocial
    }

    /// z. B. `Hi Niklas` (erster Teil des Anzeigenamens).
    public var greeting: String {
        let first = store.profile.displayName.split(separator: " ").first.map(String.init) ?? store.profile.displayName
        return "Hi \(first)"
    }

    public var stepsToday: StepsTodaySummary? {
        activity.overview.map { StepsTodaySummary(today: $0.today, goal: goals.goal(on: $0.today.date), formatter: formatter) }
    }

    public var week: WeekOverview? {
        activity.overview.map {
            WeekOverview(overview: $0, goals: goals.history, calendar: calendar, formatter: formatter)
        }
    }

    public var modules: [HomeModule] {
        settings.modules
    }

    /// Serie für das Serien-Modul; `nil`, solange der Verlauf nicht geladen ist.
    public var streakSummary: StreakSummary? {
        guard let current = streak.streak else { return nil }
        return StreakSummary(
            streak: current,
            record: streak.record,
            recentDays: streak.recentDays(28),
            formatter: formatter
        )
    }

    /// Ändert sich, wenn die Platzierungen neu geladen werden müssen (auch wenn Umfeld-Module mehr Zeilen brauchen).
    public var standingsReloadKey: StandingsTrigger {
        StandingsTrigger(key: standings.reloadKey, radii: settings.neighborhoodRadii, isShown: showsStandings)
    }

    public struct StandingsTrigger: Hashable, Sendable {
        let key: RegionalStandingsViewModel.ReloadKey
        let radii: [RegionLevel: Int]
        let isShown: Bool
    }

    /// Platzierungen werden nur geladen, wenn ein Modul sie anzeigt.
    public var showsStandings: Bool {
        settings.showsStandings
    }

    /// Ob ein Modul den Verlauf braucht (Serie).
    public var showsStreak: Bool {
        modules.contains { $0.kind == .streak }
    }

    /// Erstes Laden beim Erscheinen und nach Änderungen am Layout.
    public func loadIfNeeded() async {
        guard showsStandings else { return }
        standings.neighborhoodRadii = settings.neighborhoodRadii
        await standings.loadIfNeeded()
    }

    /// Verlauf für das Serien-Modul laden (selten, siehe `ActivityHistoryStore`).
    public func loadStreakIfNeeded() async {
        guard showsStreak else { return }
        await streak.loadIfNeeded()
    }

    /// Pull-to-Refresh: Schritte neu aus Apple Health lesen, an den Sync übergeben, Platzierungen neu laden.
    public func refresh() async {
        await activity.refreshForRanking()
        if showsStreak {
            await streak.history.reload()
            streak.saveRecordIfNeeded()
        }
        guard showsStandings else { return }
        standings.neighborhoodRadii = settings.neighborhoodRadii
        await standings.load()
    }

    /// Zurück in der App: zuerst die Schritte lesen und übergeben, dann – falls älter als eine Minute – die
    /// Platzierungen, damit sie die neuen Schritte schon enthalten.
    public func returnedToForeground() async {
        await activity.refresh(trigger: .foreground)
        await loadStreakIfNeeded()
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

    /// ViewModel für die Statistik (Navigation aus Schrittkarte, Distanz, Kalorien und Wochenbalken).
    public func statistics(for route: StatisticsRoute) -> StatisticsViewModel {
        StatisticsViewModel(
            route: route,
            streak: streak,
            activityData: activityData,
            live: activity,
            calendar: calendar,
            formatter: formatter,
            now: now
        )
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
