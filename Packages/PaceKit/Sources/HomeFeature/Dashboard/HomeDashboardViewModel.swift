import ActivityFeature
import Foundation
import Observation
import PaceCore
import SocialFeature

/// Navigation zur Widget-Galerie: neues Widget hinzufügen (`editingID == nil`) oder ein vorhandenes bearbeiten.
public struct HomeWidgetGalleryRoute: Hashable, Sendable {
    public let editingID: HomeModule.ID?

    public init(editingID: HomeModule.ID? = nil) {
        self.editingID = editingID
    }
}

/// Navigation zu „Mitteilungen“.
public struct HomeNotificationsRoute: Hashable, Sendable {
    public init() {}
}

/// Das Home-Dashboard: Bewegungsdaten, Tagesziel, Serie, regionale Platzierungen und die vom Nutzer gewählten Widgets.
///
/// Die Widgets (`HomeModule`) lassen sich im Anpassen-Modus direkt auf Home entfernen, verschieben und in der Größe
/// ändern; neue Widgets kommen über die Widget-Galerie hinzu. Jede Änderung wird sofort gespeichert.
@MainActor
@Observable
public final class HomeDashboardViewModel {
    /// Offene Sheets.
    public enum Sheet: String, Identifiable, Sendable {
        case stepGoal

        public var id: String { rawValue }
    }

    public var presentedSheet: Sheet?

    // MARK: Anpassen-Modus

    /// Home im Anpassen-Modus (Widgets wackeln, X, Größe, Ziehgriff).
    public private(set) var isEditing = false
    /// Widget, dessen Menü „Größe auswählen“ offen ist.
    public var sizeMenuModuleID: HomeModule.ID?
    /// Zuletzt bewegtes bzw. in der Größe geändertes Widget – hervorgehoben mit mint Rahmen.
    public var activeModuleID: HomeModule.ID?
    /// Widget, das gerade gezogen wird.
    public var draggingModuleID: HomeModule.ID?
    /// Zuletzt entferntes Widget, solange „Rückgängig“ angeboten wird.
    public private(set) var lastRemoved: RemovedHomeModule?
    /// Bestätigung „Ranking-Sichtbarkeit aktivieren“ ist offen.
    public var isConfirmingRankingVisibility = false

    public let activity: HomeViewModel
    public let standings: RegionalStandingsViewModel
    public let settings: HomeSettings
    /// Tagesziel mit Verlauf.
    public let goals: StepGoalSettings
    /// Persönliche Streak und Bewegungsverlauf (geteilt mit Statistik und Profil).
    public let streak: StepStreakTracker
    /// Freunde, Gruppen und Chats (geteilt mit dem Social-Tab).
    public let social: SocialViewModel

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
        social: SocialViewModel,
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
        self.social = social
        goals = streak.goals
        self.activityData = activityData
        self.store = store
        self.calendar = calendar
        self.formatter = formatter
        self.now = now
        self.onOpenRankings = onOpenRankings
        self.onOpenSocial = onOpenSocial
    }

    // MARK: Inhalte

    /// z. B. `Hi Niklas` (erster Teil des Anzeigenamens).
    public var greeting: String {
        let name = store.profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return HomeTexts.greeting(first)
    }

    /// Heutige Wettbewerbsschritte laut HealthKit (ohne Live-Sensorwerte) – Auslöser für Platzierungen, damit nicht
    /// jeder einzelne Sensorschritt eine Abfrage startet.
    public var healthKitStepsToday: Int? {
        activity.overview?.today.competitionSteps
    }

    /// Körperdaten für geschätzte aktive Kalorien (nur auf dem Gerät; Standard: keine Schätzung).
    var bodyMetrics: BodyMetrics {
        streak.history.bodyMetrics?.metrics ?? BodyMetrics()
    }

    /// „Deine Schritte heute“ – mit Live-Schritten vom Bewegungssensor, solange Pace offen ist.
    public var stepsToday: StepsTodaySummary? {
        activity.overview.map {
            StepsTodaySummary(
                overview: $0,
                goal: goals.goal(on: $0.today.date),
                formatter: formatter,
                liveCompetitionSteps: activity.liveCompetitionStepsToday,
                bodyMetrics: bodyMetrics
            )
        }
    }

    public var week: WeekOverview? {
        activity.overview.map {
            WeekOverview(overview: $0, goals: goals.history, calendar: calendar, formatter: formatter)
        }
    }

    /// Hinweis für Widgets mit Bewegungsdaten, wenn es keine Werte gibt; `nil` während des Ladens.
    public var weekUnavailableText: String? {
        switch activity.state {
        case .noReadAccess:
            PaceLocalization.text(
                de: "Ohne Zugriff auf deine Schritte gibt es keine Wochenwerte.",
                en: "Without access to your steps there are no weekly values.",
                ru: "Без доступа к шагам нет данных за неделю."
            )
        case .failed:
            PaceLocalization.text(
                de: "Wochenwerte gerade nicht verfügbar.",
                en: "Weekly values are unavailable right now.",
                ru: "Данные за неделю сейчас недоступны."
            )
        case .loading, .loaded:
            nil
        }
    }

    public var modules: [HomeModule] {
        settings.modules
    }

    /// Persönliche Streak für das Streak-Widget; `nil`, solange der Verlauf nicht geladen ist.
    public var streakWidget: HomeStreakWidget? {
        guard let current = streak.streak else { return nil }
        return HomeStreakWidget(streak: current, record: streak.record, recentDays: streak.recentDays(35), formatter: formatter)
    }

    /// Kalender-Widget in einer Größe. Bewertet jeden Tag mit dem damals geltenden Ziel.
    public func calendarWidget(size: HomeModuleSize) -> HomeCalendarWidget {
        let overview = activity.overview
        let history = streak.history.history
        let today = calendar.day(containing: now())
        return HomeCalendarWidget(size: size, today: today, goals: goals.history, formatter: formatter) { day in
            if let summary = overview?.summary(for: day) { return summary.competitionSteps }
            return history?.summary(for: day)?.competitionSteps
        }
    }

    /// Ob der Verlauf für Kalender und Streak noch geladen wird.
    public var isHistoryLoading: Bool {
        switch streak.history.state {
        case .idle, .loading: streak.history.history == nil
        default: false
        }
    }

    /// Freunde-Widget: du und die ausgewählten Freunde.
    public func friendsWidget(for module: HomeModule) -> HomeFriendsWidget {
        let friendIDs: Set<UUID>? = social.state == .loaded ? Set(social.friends.map(\.profile.publicID)) : nil
        return HomeFriendsWidget(ranking: social.ranking, friendIDs: friendIDs, selection: module.configuration.friendIDs)
    }

    /// Gruppen-Widget: alle Gruppen, die gewählte oder ein Hinweis, wenn es sie nicht mehr gibt.
    public func groupSelection(for module: HomeModule) -> HomeGroupSelection {
        HomeGroupSelection(groupID: module.configuration.groupID, groups: social.groups, isLoaded: social.state == .loaded)
    }

    /// Aktivitäts-Widget; `nil`, solange keine Bewegungsdaten geladen sind.
    public func activityWidget(for module: HomeModule) -> HomeActivityWidget? {
        activity.overview.map {
            HomeActivityWidget(metric: module.metric, overview: $0.estimatingActiveEnergy(with: bodyMetrics), formatter: formatter)
        }
    }

    /// Regionale Karten eines Widgets (immer alle gewählten Ebenen in einer Reihe).
    public func regionCards(for module: HomeModule) -> [HomeRegionCard] {
        standings.regionCards(levels: module.regionLevels)
    }

    /// Ob der Nutzer in regionalen Rankings sichtbar ist. Sonst zeigen Ranking-Widgets einen gesperrten Zustand mit
    /// neutralen Platzhaltern – es werden keine Rankingdaten geladen.
    public var isRankingVisible: Bool {
        standings.isParticipating
    }

    // MARK: Mitteilungen

    /// Echte Mitteilungen: eingehende Freundschaftsanfragen, Gruppeneinladungen, ungelesene Chats.
    public var notifications: [HomeNotificationItem] {
        HomeNotifications.items(
            incomingRequests: social.incomingRequests,
            invitations: social.invitations,
            conversations: social.chats.conversations
        )
    }

    /// Zahl am Glocken-Symbol (0 = kein Badge).
    public var notificationCount: Int {
        notifications.count
    }

    /// Ob Mitteilungen geladen werden können (Social-Backend vorhanden).
    public var areNotificationsAvailable: Bool {
        social.isAvailable
    }

    /// Mitteilungen (Social und Chats) laden – höchstens einmal pro Minute.
    public func loadNotificationsIfNeeded() async {
        guard social.isAvailable else { return }
        await social.loadIfNeeded()
        await social.chats.loadIfNeeded()
    }

    /// Tippen auf eine Mitteilung: in den Social-Tab, wo Anfragen, Einladungen und Chats stehen.
    public func open(_ notification: HomeNotificationItem) {
        onOpenSocial()
    }

    // MARK: Laden

    /// Ändert sich, wenn die Platzierungen neu geladen werden müssen (auch wenn Widgets mehr Zeilen brauchen).
    public var standingsReloadKey: StandingsTrigger {
        StandingsTrigger(key: standings.reloadKey, radii: settings.neighborhoodRadii, isShown: showsStandings)
    }

    public struct StandingsTrigger: Hashable, Sendable {
        let key: RegionalStandingsViewModel.ReloadKey
        let radii: [RegionLevel: Int]
        let isShown: Bool
    }

    /// Platzierungen werden nur geladen, wenn ein Widget sie anzeigt.
    public var showsStandings: Bool {
        settings.showsStandings
    }

    /// Ob ein Widget den Verlauf braucht (Streak, Kalender).
    public var showsStreak: Bool {
        modules.contains { $0.kind == .streak || $0.kind == .calendar }
    }

    /// Ob ein Widget Freunde oder Gruppen zeigt.
    public var showsSocial: Bool {
        modules.contains { $0.kind == .friends || $0.kind == .groups }
    }

    /// Freunde und Gruppen laden, wenn ein Widget sie zeigt (höchstens einmal pro Minute).
    public func loadSocialIfNeeded() async {
        guard showsSocial else { return }
        await social.loadIfNeeded()
    }

    /// Erstes Laden beim Erscheinen und nach Änderungen am Layout.
    public func loadIfNeeded() async {
        guard showsStandings else { return }
        standings.neighborhoodRadii = settings.neighborhoodRadii
        await standings.loadIfNeeded()
    }

    /// Verlauf für Streak- und Kalender-Widget laden (selten, siehe `ActivityHistoryStore`).
    public func loadStreakIfNeeded() async {
        guard showsStreak else { return }
        // Erst die laufende Abfrage der letzten 7 Tage abwarten, damit HealthKit nicht zwei große Abfragen parallel
        // ausführt (z. B. beim App-Start).
        await activity.waitForPendingLoad()
        await streak.loadIfNeeded()
    }

    /// Pull-to-Refresh: Schritte neu aus Apple Health lesen, an den Sync übergeben, Platzierungen neu laden.
    public func refresh() async {
        await activity.refreshForRanking()
        if showsStreak {
            await streak.history.reload()
            streak.saveRecordIfNeeded()
        }
        if social.isAvailable {
            await social.load()
            await social.chats.load()
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

    // MARK: Anpassen

    public func beginEditing() {
        isEditing = true
        presentedSheet = nil
    }

    /// „Fertig“: beendet den Anpassen-Modus. Alles ist bereits gespeichert.
    public func endEditing() {
        isEditing = false
        sizeMenuModuleID = nil
        activeModuleID = nil
        draggingModuleID = nil
        settings.endDeferringSave()
        lastRemoved = nil
    }

    /// Öffnet bzw. schließt das Größenmenü eines Widgets.
    public func toggleSizeMenu(for id: HomeModule.ID) {
        sizeMenuModuleID = sizeMenuModuleID == id ? nil : id
        activeModuleID = id
    }

    public func setSize(_ size: HomeModuleSize, for id: HomeModule.ID) {
        settings.setSize(size, for: id)
        sizeMenuModuleID = nil
        activeModuleID = id
    }

    /// Entfernt ein Widget (nicht die zugrunde liegenden Daten) und bietet „Rückgängig“ an.
    public func remove(_ id: HomeModule.ID) {
        guard let removed = settings.remove(id) else { return }
        lastRemoved = removed
        if sizeMenuModuleID == id { sizeMenuModuleID = nil }
        if activeModuleID == id { activeModuleID = nil }
    }

    public func undoRemove() {
        guard let lastRemoved else { return }
        settings.restore(lastRemoved)
        activeModuleID = lastRemoved.module.id
        self.lastRemoved = nil
    }

    /// Blendet „Rückgängig“ aus (nach einigen Sekunden).
    public func dismissUndo(for removed: RemovedHomeModule) {
        guard lastRemoved == removed else { return }
        lastRemoved = nil
    }

    /// Wartet und blendet „Rückgängig“ dann aus – solange inzwischen nichts anderes entfernt wurde.
    public func expireUndo(for removed: RemovedHomeModule, after delay: Duration) async {
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        dismissUndo(for: removed)
    }

    /// Titel eines Widgets, wie er auf Home steht (beim Umfeld mit dem Gebiet, z. B. „Pfungstadt · Dein Umfeld“).
    public func title(for module: HomeModule) -> String {
        switch module.kind {
        case .neighborhood:
            let level = standings.effectiveLevel(for: module.regionLevel ?? .municipality)
            guard let region = standings.scopes.first(where: { $0.level == level }) else { return module.title }
            return "\(region.localizedName) · \(module.title)"
        case .groups where module.configuration.groupID != nil:
            return PaceLocalization.text(de: "Gruppen-Streak", en: "Group streak", ru: "Серия группы")
        default:
            return module.title
        }
    }

    /// Drag & Drop: Das gezogene Widget nimmt den Platz des Ziel-Widgets ein.
    public func moveDragged(to targetID: HomeModule.ID) {
        guard let draggingModuleID, draggingModuleID != targetID else { return }
        settings.move(draggingModuleID, to: targetID)
        activeModuleID = draggingModuleID
    }

    /// Ziehen am Griff beginnt: Größenmenü schließen, Widget als aktiv markieren.
    public func beginDragging(_ id: HomeModule.ID) {
        sizeMenuModuleID = nil
        draggingModuleID = id
        activeModuleID = id
        settings.beginDeferringSave()
    }

    /// Ziehgriff: Das gezogene Widget wandert an die Position `index`.
    public func moveDragged(toIndex index: Int) {
        guard let draggingModuleID else { return }
        settings.move(draggingModuleID, toIndex: index)
    }

    /// Ziehen beendet (abgelegt oder abgebrochen): Das Widget ist wieder normal sichtbar, die neue Reihenfolge wird
    /// einmal gespeichert.
    public func endDragging() {
        draggingModuleID = nil
        settings.endDeferringSave()
    }

    public func moveUp(_ id: HomeModule.ID) {
        settings.moveUp(id)
        activeModuleID = id
    }

    public func moveDown(_ id: HomeModule.ID) {
        settings.moveDown(id)
        activeModuleID = id
    }

    // MARK: Navigation

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

    /// ViewModel für den Kalender (Kalender-Symbol im Kopf und Kalender-Widget).
    public func calendar(for route: CalendarRoute) -> CalendarViewModel {
        CalendarViewModel(
            route: route,
            streak: streak,
            activityData: activityData,
            live: activity,
            calendar: calendar,
            formatter: formatter,
            now: now
        )
    }

    /// ViewModel für die Widget-Galerie.
    public func gallery(for route: HomeWidgetGalleryRoute) -> HomeWidgetGalleryViewModel {
        HomeWidgetGalleryViewModel(
            mode: route.editingID.map { .edit($0) } ?? .add,
            settings: settings,
            social: social,
            standings: standings
        )
    }

    public func openRankings(_ scope: Region? = nil) {
        onOpenRankings(scope)
    }

    public func openSocial() {
        onOpenSocial()
    }

    /// Öffnet eine Gruppe im Social-Tab (Gruppen-Widget).
    public func openGroup(_ id: UUID) {
        social.showGroup(id)
        onOpenSocial()
    }

    public func present(_ sheet: Sheet) {
        presentedSheet = sheet
    }

    // MARK: Ranking-Sichtbarkeit

    /// Tippen auf ein gesperrtes Ranking-Widget: fragt, ob die Sichtbarkeit aktiviert werden soll.
    public func requestRankingVisibility() {
        guard !isRankingVisible else { return }
        isConfirmingRankingVisibility = true
    }

    /// Speichert die Sichtbarkeit im Profil (und auf dem Server) und lädt danach die Platzierungen.
    public func enableRankingVisibility() async {
        isConfirmingRankingVisibility = false
        standings.neighborhoodRadii = settings.neighborhoodRadii
        await standings.enableParticipation()
    }
}
