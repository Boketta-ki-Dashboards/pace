@testable import ActivityFeature
import DesignSystem
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import SwiftUI
import Testing

/// Home (Referenzbild 9), Anpassen-Modus (Bild 6), Widget-Galerie (Bild 7), alle Widgets in allen Größen und der
/// Zustand „Ranking ausgeschaltet“ – jeweils mit Kopfzeile.
@MainActor
@Suite(.snapshotsEnabled)
struct HomeSnapshotTests {
    private let languages: [AppLanguage] = [.german, .english, .russian]

    private func page(_ content: some View) -> some View {
        content
            .padding(.horizontal, PaceSpacing.m)
            .padding(.vertical, PaceSpacing.m)
    }

    @Test func home() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.loadStreakIfNeeded()
        try Snapshot.render(page(HomeDashboardContent(viewModel: dashboard)), name: "home", languages: languages)
    }

    /// Wie Bild 6: Anpassen-Modus mit offenem Größenmenü an „Deine Woche“.
    @Test func homeEdit() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.loadStreakIfNeeded()
        dashboard.beginEditing()
        if let week = dashboard.modules.first(where: { $0.kind == .week }) {
            dashboard.toggleSizeMenu(for: week.id)
        }
        try Snapshot.render(page(HomeDashboardContent(viewModel: dashboard)), name: "home-edit", languages: languages)

        dashboard.sizeMenuModuleID = nil
        dashboard.activeModuleID = nil
        try Snapshot.render(page(HomeDashboardContent(viewModel: dashboard)), name: "home-edit-plain")
    }

    /// Wie Bild 7: Freunde-Widget mit zwei ausgewählten Freunden, eigenem Namen und mittlerer Größe.
    @Test func widgetGallery() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        let gallery = dashboard.gallery(for: HomeWidgetGalleryRoute())
        gallery.select(.friends)
        gallery.toggleFriend(SnapshotFixtures.mia)
        gallery.toggleFriend(SnapshotFixtures.jonas)
        gallery.name = "Meine Laufrunde"
        gallery.size = .medium
        try Snapshot.render(page(HomeWidgetGalleryContent(gallery: gallery, dashboard: dashboard)), name: "widget-gallery", languages: languages)

        // Weitere Kategorien mit ihrer Auswahl.
        gallery.select(.regionRanks)
        gallery.size = .large
        try Snapshot.render(page(HomeWidgetGalleryContent(gallery: gallery, dashboard: dashboard)), name: "widget-gallery-regions")
        gallery.select(.groups)
        gallery.groupID = SnapshotFixtures.classID
        try Snapshot.render(page(HomeWidgetGalleryContent(gallery: gallery, dashboard: dashboard)), name: "widget-gallery-groups")

        let edit = dashboard.gallery(for: HomeWidgetGalleryRoute(editingID: dashboard.modules.first { $0.kind == .stepsToday }?.id))
        try Snapshot.render(page(HomeWidgetGalleryContent(gallery: edit, dashboard: dashboard)), name: "widget-gallery-edit-steps")

        try Snapshot.render(page(HomeFriendPickerContent(gallery: gallery)), name: "widget-gallery-friends")
    }

    /// Alle Widgets in jeder Größe mit echten Beispieldaten.
    @Test func widgetsInAllSizes() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.loadStreakIfNeeded()
        dashboard.standings.neighborhoodRadii = [.municipality: 6, .district: 1, .state: 1, .country: 1]
        await dashboard.standings.load()

        for size in HomeModuleSize.allCases {
            let modules = SnapshotFixtures.allWidgets(size: size)
            let content = VStack(alignment: .leading, spacing: PaceSpacing.s) {
                ForEach(modules) { module in
                    HomeModuleView(module: module, viewModel: dashboard, mode: .normal)
                }
            }
            try Snapshot.render(page(content), name: "home-widgets-\(size.rawValue)")
        }
    }

    /// Schrittkarte in allen vier Größen (Auftrag 5, A4): Klein, Mittel, Groß, Max mit 7-Tage-Diagramm.
    @Test func stepsWidgetInAllSizes() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.loadStreakIfNeeded()
        for size in HomeModuleSize.allCases {
            let module = HomeModule(id: "steps", kind: .stepsToday, size: size)
            try Snapshot.render(
                page(HomeModuleView(module: module, viewModel: dashboard, mode: .normal)),
                name: "steps-\(size.rawValue)",
                languages: size == .max ? languages : [.german]
            )
        }
    }

    /// Die fünf neuen Widgets (Auftrag 5, D) in jeder Größe mit Beispieldaten: Tagesvergleich, Flammen-Woche,
    /// Persönliche Rekorde, Aktivitätszeiten, Gruppenfortschritt.
    @Test func newWidgetsInAllSizes() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.loadStreakIfNeeded()
        for module in SnapshotFixtures.newWidgets(size: .medium) {
            _ = dashboard.settings.add(module)
        }
        await dashboard.loadSocialIfNeeded()
        await dashboard.loadHourlyIfNeeded()
        for size in HomeModuleSize.allCases {
            let content = VStack(alignment: .leading, spacing: PaceSpacing.s) {
                ForEach(SnapshotFixtures.newWidgets(size: size)) { module in
                    HomeModuleView(module: module, viewModel: dashboard, mode: .normal)
                }
            }
            try Snapshot.render(page(content), name: "home-new-widgets-\(size.rawValue)", languages: size == .medium ? languages : [.german])
        }
        // Einzeln je Widget in Mittel und Max (Vorschau-Ordner docs/previews/auftrag5).
        for size in [HomeModuleSize.medium, .max] {
            for module in SnapshotFixtures.newWidgets(size: size) {
                try Snapshot.render(
                    page(HomeModuleView(module: module, viewModel: dashboard, mode: .normal)),
                    name: "new-\(module.kind.rawValue)-\(size.rawValue)"
                )
            }
        }
    }

    /// Rekordauswahl der „Persönlichen Rekorde“ (Produkt-Review Auftrag 5): einspaltig, lange russische Titel ungekürzt.
    @Test func recordsGallery() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.loadStreakIfNeeded()
        let gallery = dashboard.gallery(for: HomeWidgetGalleryRoute())
        gallery.select(.records)
        gallery.record = .longestDistance
        try Snapshot.render(page(HomeWidgetGalleryContent(gallery: gallery, dashboard: dashboard)), name: "widget-gallery-records", languages: languages)
    }

    /// Ebenen-Editor der regionalen Karten (Auftrag 5, A3): „3 von 4 Ebenen sichtbar“ mit „Alle vier zeigen“.
    @Test func regionLevelEditor() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.standings.load()
        let id = try #require(dashboard.modules.first { $0.kind == .regionRanks }?.id)
        let gallery = dashboard.gallery(for: HomeWidgetGalleryRoute(editingID: id))
        gallery.toggleLevel(.country)
        try Snapshot.render(page(HomeWidgetGalleryContent(gallery: gallery, dashboard: dashboard)), name: "widget-gallery-regions-hidden-level")
    }

    /// „Ranking ausgeschaltet“: Ranking-Widgets bleiben an ihrem Platz, unscharf mit neutralen Platzhaltern.
    @Test func rankingOff() async throws {
        let (dashboard, store) = try await SnapshotFixtures.makeDashboard()
        try await store.setRegionalLeaderboardEnabled(false)
        await dashboard.standings.load()
        await dashboard.loadStreakIfNeeded()
        try Snapshot.render(page(HomeDashboardContent(viewModel: dashboard)), name: "home-ranking-off", languages: languages)

        dashboard.beginEditing()
        try Snapshot.render(page(HomeDashboardContent(viewModel: dashboard)), name: "home-ranking-off-edit")
    }

    /// Mitteilungen aus echten Anfragen und Einladungen.
    @Test func notifications() async throws {
        let (dashboard, store) = try await SnapshotFixtures.makeDashboard()
        try Snapshot.render(page(HomeNotificationsContent(viewModel: dashboard)), name: "home-notifications", languages: languages)

        let empty = SocialViewModel(repository: SocialRepositoryStub(), calendar: Fixtures.activityCalendar)
        await empty.load()
        let emptyDashboard = HomeDashboardViewModel(
            activity: dashboard.activity,
            standings: dashboard.standings,
            settings: dashboard.settings,
            streak: dashboard.streak,
            social: empty,
            activityData: HealthServiceStub(),
            store: store
        )
        try Snapshot.render(page(HomeNotificationsContent(viewModel: emptyDashboard)), name: "home-notifications-empty")
    }
}

extension SnapshotFixtures {
    static let mia = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
    static let jonas = UUID(uuidString: "40000000-0000-4000-8000-000000000002")!
    static let classID = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!

    /// Jede Widget-Art in einer Größe.
    static func allWidgets(size: HomeModuleSize) -> [HomeModule] {
        var modules: [HomeModule] = [
            HomeModule(id: "ranks", kind: .regionRanks, size: size),
            HomeModule(id: "steps", kind: .stepsToday, size: size),
            HomeModule(id: "week", kind: .week, size: size),
            HomeModule(id: "streak", kind: .streak, size: size),
            HomeModule(id: "near", kind: .neighborhood, size: size, regionLevel: .municipality),
            HomeModule(
                id: "run",
                kind: .friends,
                size: size,
                configuration: HomeWidgetConfiguration(friendIDs: [mia, jonas], customName: "Meine Laufrunde")
            ),
            HomeModule(id: "class", kind: .groups, size: size, configuration: HomeWidgetConfiguration(groupID: classID)),
            HomeModule(id: "groups", kind: .groups, size: size),
            HomeModule(id: "distance", kind: .activity, size: size, configuration: HomeWidgetConfiguration(metric: .distance)),
            HomeModule(id: "calendar", kind: .calendar, size: size),
        ]
        // Die neuen Widgets stehen in eigenen Bildern (`newWidgetsInAllSizes`) – ein einziges Bild aller Widgets in Max
        // würde zu hoch zum Speichern.
        modules.removeAll { !$0.kind.supportedSizes.contains(size) }
        return modules
    }

    /// Die fünf neuen Widgets (Auftrag 5) in einer Größe.
    static func newWidgets(size: HomeModuleSize) -> [HomeModule] {
        [
            HomeModule(id: "compare", kind: .dayComparison, size: size),
            HomeModule(id: "flameweek", kind: .streakWeek, size: size),
            HomeModule(id: "records", kind: .records, size: size, configuration: HomeWidgetConfiguration(record: .bestDay)),
            HomeModule(id: "times", kind: .activityTimes, size: size),
            HomeModule(id: "groupprogress", kind: .groupProgress, size: size, configuration: HomeWidgetConfiguration(groupID: classID)),
        ]
    }
}
