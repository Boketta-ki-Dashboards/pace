@testable import ActivityFeature
import DesignSystem
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
@testable import ProfileFeature
@testable import SocialFeature
import SwiftUI
import Testing
import UIKit

/// Vorschaubilder für Auftrag 7 (docs/previews/auftrag7): Home-Anpassen-Kopf, Pace-Bot in der Chatliste, ruhige
/// Statistik beim Wischen, Profilbild und Banner direkt bearbeiten, Interessen 2.0, Profil-Tab nach der Rückkehr.
/// Simulator-Bilder mit Beispieldaten und Beispielbildern – keine Aufnahmen vom iPhone.
@MainActor
@Suite(.snapshotsEnabled)
struct Auftrag7SnapshotTests {
    private let languages: [AppLanguage] = [.german, .english, .russian]

    private func page(_ content: some View, loader: PaceImageLoader? = nil) -> some View {
        content
            .padding(.horizontal, PaceSpacing.m)
            .padding(.vertical, PaceSpacing.m)
            .environment(\.paceImageLoader, loader)
    }

    // MARK: 1–2 Home-Anpassen-Kopf

    @Test func homeEditHeader() async throws {
        let (dashboard, loader) = try await A6Fixtures.dashboard()
        dashboard.beginEditing()
        try await Snapshot.renderInWindow(
            MainScreenHarness(selected: 0, content: AnyView(HomeView(viewModel: dashboard))).environment(\.paceImageLoader, loader),
            name: "a7-home-edit"
        )
        // Nur der Kopf auf schmalen, normalen und großen iPhones (Seitenrand wie Home: 16 pt).
        for (width, device) in [(CGFloat(320), "320"), (375, "375"), (393, "393"), (430, "430")] {
            try Snapshot.render(
                HomeHeaderView(viewModel: dashboard, onAddWidget: {}).padding(.horizontal, PaceSpacing.m).padding(.vertical, PaceSpacing.s),
                name: "a7-header-\(device)",
                width: width,
                languages: languages
            )
        }
        try Snapshot.render(
            HomeHeaderView(viewModel: dashboard, onAddWidget: {})
                .padding(.horizontal, PaceSpacing.m).padding(.vertical, PaceSpacing.s)
                .environment(\.dynamicTypeSize, .xxxLarge),
            name: "a7-header-375-large-text",
            width: 375,
            languages: languages
        )
        dashboard.endEditing()
    }

    // MARK: 3–5 Pace-Bot in der Chatliste

    private func session(askedAt date: Date?) -> PaceHelpBotSession {
        var messages = [PaceHelpMessage(role: .bot, content: .greeting, date: Fixtures.date(2026, 10, 10, 9, 0))]
        if let date {
            messages.append(PaceHelpMessage(role: .user, content: .question(.groupFlame), date: date))
            messages.append(PaceHelpMessage(role: .bot, content: .answer(.groupFlame), date: date))
        }
        return PaceHelpBotSession(store: InMemoryPaceHelpHistoryStore(messages))
    }

    private func chats(groupUpdatedAt: Date, groupLast: ChatMessagePreview? = nil, unread: Int = 0) async -> ChatListViewModel {
        let list = ChatListViewModel(repository: ChatRepositoryStub { state in
            state.conversations = [
                ChatFixtures.direct(
                    id: UUID(), peer: A6Fixtures.mia,
                    last: ChatMessagePreview(kind: .text, text: "Bis morgen beim Laufen!", senderName: "Mia", isOwn: false, sentAt: Fixtures.date(2026, 10, 16, 18, 5)),
                    updatedAt: Fixtures.date(2026, 10, 16, 18, 5)
                ),
                ChatFixtures.group(
                    id: UUID(), groupID: A6Fixtures.groupID, title: "Smoking red", memberCount: 12, last: groupLast, unread: unread,
                    updatedAt: groupUpdatedAt
                ),
                ChatFixtures.direct(
                    id: UUID(), peer: A6Fixtures.jonas,
                    last: ChatMessagePreview(kind: .text, text: "Starke Serie 🔥", senderName: "Jonas", isOwn: false, sentAt: Fixtures.date(2026, 10, 15, 20, 12)),
                    updatedAt: Fixtures.date(2026, 10, 15, 20, 12)
                ),
            ]
        }, media: nil, calendar: Fixtures.activityCalendar, now: { Fixtures.date(2026, 10, 16, 18, 30) })
        await list.load()
        return list
    }

    @Test func paceBotSortedLikeAChat() async throws {
        let loader = await A6Fixtures.loader()
        // Nie benutzt: ganz unten.
        let inactive = await chats(groupUpdatedAt: Fixtures.date(2026, 10, 16, 17, 40))
        try Snapshot.render(
            page(ChatListContent(viewModel: inactive, helpBot: session(askedAt: nil), onOpenHelpBot: {}), loader: loader),
            name: "a7-chatlist-bot-inactive",
            languages: languages
        )
        // Eigene Frage um 18:20: der Bot steht oben.
        try Snapshot.render(
            page(ChatListContent(viewModel: inactive, helpBot: session(askedAt: Fixtures.date(2026, 10, 16, 18, 20)), onOpenHelpBot: {}), loader: loader),
            name: "a7-chatlist-after-bot-question",
            languages: languages
        )
        // Danach neue Gruppennachricht um 18:25: die Gruppe steht wieder über dem Bot.
        let newer = await chats(
            groupUpdatedAt: Fixtures.date(2026, 10, 16, 18, 25),
            groupLast: ChatMessagePreview(kind: .text, text: "Wer kommt heute mit?", senderName: "Lea", isOwn: false, sentAt: Fixtures.date(2026, 10, 16, 18, 25)),
            unread: 1
        )
        try Snapshot.render(
            page(ChatListContent(viewModel: newer, helpBot: session(askedAt: Fixtures.date(2026, 10, 16, 18, 20)), onOpenHelpBot: {}), loader: loader),
            name: "a7-chatlist-after-group-message",
            languages: languages
        )
    }

    // MARK: 6–7 Statistik beim Wischen

    @Test func statisticsSwipe() async throws {
        let environment = await ActivitySnapshotEnvironment.make(october: ActivitySnapshotEnvironment.dayDetailsOctober)
        for (period, metric, name) in [
            (StatisticsPeriod.day, StatisticsMetric.steps, "day"), (.week, .distance, "week"), (.month, .activeEnergy, "month"),
        ] {
            let statistics = StatisticsViewModel(
                route: StatisticsRoute(period: period, metric: metric),
                streak: environment.streak,
                activityData: environment.health,
                live: environment.live,
                calendar: environment.calendar,
                formatter: ActivityFormatter(calendar: environment.calendar),
                now: environment.now
            )
            await statistics.loadIfNeeded()
            await statistics.loadHourly()
            // Mitten in der Geste (Finger 110 pt nach rechts): Karte und Diagramm bewegen sich als Ganzes.
            try Snapshot.render(
                page(StatisticsSnapshotHost(viewModel: statistics).environment(\.pacePeriodSwipePreviewOffset, 110)),
                name: "a7-statistics-\(name)-swipe"
            )
            // Nach dem Einrasten (vorheriger Zeitraum geladen, kein Versatz).
            statistics.showPrevious()
            await statistics.loadIfNeeded()
            await statistics.loadHourly()
            try Snapshot.render(page(StatisticsSnapshotHost(viewModel: statistics)), name: "a7-statistics-\(name)-settled", languages: period == .day ? languages : [.german])
        }
    }

    // MARK: 8–10 Profilbild und Banner

    @Test func editProfilePictures() async throws {
        let (profile, loader) = try await A6Fixtures.profile(details: A7Fixtures.manyInterests)
        try await Snapshot.renderInWindow(
            NavigationStack { ProfileEditPage(viewModel: profile, backTitle: ProfileTexts.profileTitle) }.environment(\.paceImageLoader, loader),
            name: "a7-profile-edit"
        )
        let photo = try #require(UIImage(data: A6Fixtures.image([.systemIndigo, .systemTeal], symbol: "figure.hiking", size: CGSize(width: 900, height: 1_200))))
        try await Snapshot.renderInWindow(AvatarCropSheet(image: photo, onUse: { _ in }, onCancel: {}), name: "a7-avatar-editor")
        let landscape = try #require(UIImage(data: A6Fixtures.image([UIColor(red: 0.05, green: 0.35, blue: 0.25, alpha: 1), .systemMint], symbol: "mountain.2", size: CGSize(width: 1_600, height: 1_000))))
        try await Snapshot.renderInWindow(BannerCropSheet(image: landscape, onUse: { _ in }, onCancel: {}), name: "a7-banner-editor")
    }

    // MARK: 11–15 Interessen, Sprachen, Land

    private func interestsViewModel(_ details: ProfileDetails, input: String = "") async -> ProfileDetailsViewModel {
        let viewModel = ProfileDetailsViewModel(repository: ProfileDetailsRepositoryStub { $0.own = details }, media: MediaRepositoryStub())
        await viewModel.load()
        viewModel.beginEditing()
        viewModel.customInterestInput = input
        return viewModel
    }

    private func scrollPage(_ content: some View) -> some View {
        ScrollView {
            content.padding(PaceSpacing.m)
        }
        .paceScreenBackground()
    }

    @Test func interestsEditor() async throws {
        let catalog = await interestsViewModel(A7Fixtures.someInterests)
        try await Snapshot.renderInWindow(
            scrollPage(ProfileInterestsCard(details: catalog, initiallyExpanded: Set(ProfileInterestCategory.allCases))),
            name: "a7-interests-catalog"
        )
        try await Snapshot.renderInWindow(
            scrollPage(ProfileInterestsCard(details: catalog, initiallyExpanded: Set(ProfileInterestCategory.allCases))),
            name: "a7-interests-catalog-more"
        ) { view in
            Snapshot.scroll(in: view, by: 640)
        }
        // „+ Eigenes Interesse hinzufügen“: Feld offen mit eigenem Begriff, danach als Chip in der Auswahl.
        let custom = await interestsViewModel(A7Fixtures.someInterests, input: "Musik produzieren")
        try await Snapshot.renderInWindow(
            scrollPage(ProfileInterestsCard(details: custom, initiallyExpanded: [.creative], showsCustomFieldInitially: true)),
            name: "a7-interest-custom"
        )
        custom.addCustomInterest()
        custom.customInterestInput = "rap"
        try await Snapshot.renderInWindow(
            scrollPage(ProfileInterestsCard(details: custom, initiallyExpanded: [.creative], showsCustomFieldInitially: true)),
            name: "a7-interest-suggestion"
        )
        custom.customInterestInput = "musik PRODUZIEREN"
        custom.addCustomInterest()
        try await Snapshot.renderInWindow(
            scrollPage(ProfileInterestsCard(details: custom, initiallyExpanded: [.creative], showsCustomFieldInitially: true)),
            name: "a7-interest-duplicate"
        )
        // Älterer Server (ohne Migration 20261102100000): nur der ursprüngliche Katalog, höchstens fünf.
        let legacy = await interestsViewModel(ProfileDetails(interests: [.walking, .football]))
        try Snapshot.render(page(ProfileInterestsCard(details: legacy)), name: "a7-interests-legacy-server")

        // Sprachen und Land: Bereiche und Auswahllisten mit Suche.
        let background = await interestsViewModel(A7Fixtures.manyInterests)
        try Snapshot.render(
            page(VStack(spacing: PaceSpacing.s) { ProfileLanguagesCard(details: background); ProfileCountryCard(details: background) }),
            name: "a7-languages-country-cards",
            languages: languages
        )
        try await Snapshot.renderInWindow(ProfileLanguagePicker(details: background), name: "a7-languages-picker")
        try await Snapshot.renderInWindow(ProfileLanguagePicker(details: background, query: "Serb"), name: "a7-languages-search")
        try await Snapshot.renderInWindow(ProfileCountryPicker(details: background, query: "Ge"), name: "a7-country-picker")
    }

    @Test func profilesWithManyInterests() async throws {
        let (profile, loader) = try await A6Fixtures.profile(details: A7Fixtures.manyInterests)
        try Snapshot.render(page(ProfileContent(viewModel: profile), loader: loader), name: "a7-profile-many-interests", languages: languages)

        // Fremdes Profil: zunächst sechs Interessen, Rest über „Alle Interessen ansehen“.
        let (social, socialLoader) = await A6Fixtures.social()
        social.profileDetails = ProfileDetailsRepositoryStub { state in
            state.others[A6Fixtures.mia.publicID] = A7Fixtures.manyInterests
        }
        let model = try #require(social.userProfile(for: A6Fixtures.mia))
        await model.load()
        try Snapshot.render(page(UserProfileContent(model: model, social: social), loader: socialLoader), name: "a7-foreign-profile-compact", languages: languages)
    }

    // MARK: 16 Profil-Tab nach der Rückkehr

    @Test func profileTabAfterReturning() async throws {
        let (profile, loader) = try await A6Fixtures.profile(details: A7Fixtures.someInterests)
        // In Profil eine Unterseite öffnen, zu Social wechseln und zurück: wieder die Hauptseite, oben.
        profile.open(.privacy)
        profile.didLeaveTab()
        try await Snapshot.renderInWindow(
            MainScreenHarness(selected: 3, content: AnyView(ProfileView(viewModel: profile))).environment(\.paceImageLoader, loader),
            name: "a7-profile-after-return"
        )
    }
}

@MainActor
enum A7Fixtures {
    static let someInterests = ProfileDetails(
        bio: "Jeden Tag ein bisschen aktiver.",
        interests: [.walking, .football, .rap, .programming],
        customInterests: ["Freestyle Rap"],
        bannerPath: A6Fixtures.banner.path,
        supportsExtendedProfile: true
    )

    static let manyInterests = ProfileDetails(
        bio: "Fußball, Rap und lange Spaziergänge. Auf dem Weg zu 100 Tagen. 🚶",
        interests: [.football, .basketball, .running, .walking, .rap, .hipHop, .musicProduction, .programming, .webDevelopment, .gaming, .travel, .cooking],
        customInterests: ["Musik produzieren", "Рэп-баттлы", "Kaffee ☕", "Webcoding mit Swift"],
        spokenLanguages: ["de", "ru", "sr", "sq", "ka"],
        countryCode: "GE",
        bannerPath: A6Fixtures.banner.path,
        showsAchievements: true,
        achievements: [.streak30, .bestDay20k],
        supportsExtendedProfile: true
    )
}
