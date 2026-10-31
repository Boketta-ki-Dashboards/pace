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

/// Vorschaubilder für Auftrag 6 (docs/previews/auftrag6): Home-Anpassen ohne seitliches Verrutschen, Profil- und
/// Gruppenbilder, Social-Profil 2.0, Darstellungsauswahl, Willkommensmitteilung und Pace-Bot. Simulator-Bilder mit
/// Beispieldaten und Beispielbildern – keine Aufnahmen vom iPhone.
@MainActor
@Suite(.snapshotsEnabled)
struct Auftrag6SnapshotTests {
    private let languages: [AppLanguage] = [.german, .english, .russian]

    private func page(_ content: some View, loader: PaceImageLoader? = nil) -> some View {
        content
            .padding(.horizontal, PaceSpacing.m)
            .padding(.vertical, PaceSpacing.m)
            .environment(\.paceImageLoader, loader)
    }

    // MARK: 1–4 Home und Anpassen

    @Test func homeAndEditMode() async throws {
        let (dashboard, loader) = try await A6Fixtures.dashboard()
        try await Snapshot.renderInWindow(
            MainScreenHarness(selected: 0, content: AnyView(HomeView(viewModel: dashboard))).environment(\.paceImageLoader, loader),
            name: "a6-home"
        )
        dashboard.beginEditing()
        try await Snapshot.renderInWindow(
            MainScreenHarness(selected: 0, content: AnyView(HomeView(viewModel: dashboard))).environment(\.paceImageLoader, loader),
            name: "a6-home-edit"
        )
        // Nachgestellter waagerechter Versatz von 64 pt (wie ein seitliches Ziehen): mit Sperre bleibt die Seite stehen,
        // ohne Sperre (früherer Zustand) wandert sie zur Seite.
        for (enabled, name) in [(true, "a6-home-edit-swipe"), (false, "a6-home-edit-swipe-before")] {
            let screen = MainScreenHarness(selected: 0, content: AnyView(HomeView(viewModel: dashboard)))
                .environment(\.paceImageLoader, loader)
                .environment(\.paceVerticalScrollLockEnabled, enabled)
            try await Snapshot.renderInWindow(screen, name: name) { view in
                A6Fixtures.shiftPageHorizontally(in: view, by: 64)
            }
        }
        // Widget am Griff verschieben: das gezogene Widget ist angehoben und mint umrandet.
        if let second = dashboard.modules.dropFirst().first?.id {
            dashboard.draggingModuleID = second
            dashboard.activeModuleID = second
        }
        try await Snapshot.renderInWindow(
            MainScreenHarness(selected: 0, content: AnyView(HomeView(viewModel: dashboard))).environment(\.paceImageLoader, loader),
            name: "a6-home-widget-move"
        ) { view in
            Snapshot.scroll(in: view, by: 260)
        }
        dashboard.draggingModuleID = nil
        dashboard.endEditing()
    }

    // MARK: 5–8 Profil- und Gruppenbilder

    @Test func profileAndGroupImages() async throws {
        let (dashboard, loader) = try await A6Fixtures.dashboard()
        let friends = HomeModule(id: "friends", kind: .friends, size: .large)
        try Snapshot.render(page(HomeModuleView(module: friends, viewModel: dashboard, mode: .normal), loader: loader), name: "a6-avatar-home")
        let ranking = dashboard.social.friendsRanking()
        await ranking.load()
        try Snapshot.render(page(FriendsRankingContent(model: ranking), loader: loader), name: "a6-avatar-friends-ranking")
        let groups = HomeModule(id: "groups", kind: .groups, size: .large)
        try Snapshot.render(page(HomeModuleView(module: groups, viewModel: dashboard, mode: .normal), loader: loader), name: "a6-group-image-widget")
        let detail = try #require(dashboard.social.detail(groupID: A6Fixtures.groupID))
        await detail.load()
        try Snapshot.render(page(GroupDetailContent(viewModel: detail), loader: loader), name: "a6-group-image-info")
    }

    // MARK: 9–16 Social-Profil 2.0 und Darstellung

    @Test func ownProfileWithAndWithoutBanner() async throws {
        let (profile, loader) = try await A6Fixtures.profile(details: A6Fixtures.richDetails)
        try Snapshot.render(page(ProfileContent(viewModel: profile), loader: loader), name: "a6-profile-banner", languages: languages)
        let (plain, plainLoader) = try await A6Fixtures.profile(details: .empty)
        try Snapshot.render(page(ProfileContent(viewModel: plain), loader: plainLoader), name: "a6-profile-no-banner")
    }

    @Test func editProfile() async throws {
        let (profile, loader) = try await A6Fixtures.profile(details: A6Fixtures.richDetails)
        try await Snapshot.renderInWindow(
            NavigationStack { ProfileEditPage(viewModel: profile, backTitle: ProfileTexts.profileTitle) }.environment(\.paceImageLoader, loader),
            name: "a6-profile-edit"
        )
        try await Snapshot.renderInWindow(
            NavigationStack { ProfileEditPage(viewModel: profile, backTitle: ProfileTexts.profileTitle) }.environment(\.paceImageLoader, loader),
            name: "a6-profile-edit-bio"
        ) { view in
            Snapshot.scroll(in: view, by: 260)
        }
        try await Snapshot.renderInWindow(
            NavigationStack { ProfileEditPage(viewModel: profile, backTitle: ProfileTexts.profileTitle) }.environment(\.paceImageLoader, loader),
            name: "a6-profile-edit-interests"
        ) { view in
            Snapshot.scroll(in: view, by: 560)
        }
    }

    @Test func foreignProfiles() async throws {
        let (social, loader) = await A6Fixtures.social()
        let model = try #require(social.userProfile(for: A6Fixtures.mia))
        await model.load()
        try Snapshot.render(page(UserProfileContent(model: model, social: social), loader: loader), name: "a6-foreign-profile", languages: languages)
        let achiever = try #require(social.userProfile(for: A6Fixtures.jonas))
        await achiever.load()
        try Snapshot.render(page(UserProfileContent(model: achiever, social: social), loader: loader), name: "a6-profile-achievements")
    }

    @Test func appearanceSelection() async throws {
        let (profile, loader) = try await A6Fixtures.profile(details: .empty)
        try Snapshot.render(page(AppearancePageContent(viewModel: profile, backTitle: ProfileTexts.profileTitle), loader: loader), name: "a6-appearance", languages: languages)
    }

    // MARK: 17–18 Willkommensmitteilung

    @Test func welcomeNotification() async throws {
        let (dashboard, loader) = try await A6Fixtures.dashboard()
        dashboard.systemMessages.activate(owner: "snapshot")
        try Snapshot.render(page(HomeNotificationsContent(viewModel: dashboard), loader: loader), name: "a6-notifications-welcome", languages: languages)
        dashboard.onOpenAddFriend = {}
        dashboard.onOpenHelpBot = {}
        try Snapshot.render(page(WelcomeMessageContentView(viewModel: dashboard), loader: loader), name: "a6-welcome-detail", languages: languages)
    }

    // MARK: 19–24 Pace-Bot

    @Test func paceBot() async throws {
        let (social, loader) = await A6Fixtures.social()
        await social.chats.load()
        try Snapshot.render(page(ChatListContent(viewModel: social.chats, onOpenHelpBot: {}), loader: loader), name: "a6-chatlist-bot", languages: languages)

        let none = PaceSupportContact(email: nil)
        let greeting = PaceHelpBotSession()
        greeting.start()
        try Snapshot.render(page(PaceBotContent(session: greeting, support: none)), name: "a6-bot-greeting", languages: languages)

        let selected = PaceHelpBotSession(store: InMemoryPaceHelpHistoryStore([
            PaceHelpMessage(role: .bot, content: .greeting, date: .now),
            PaceHelpMessage(role: .user, content: .question(.groupFlame), date: .now),
        ]))
        try Snapshot.render(page(PaceBotContent(session: selected, support: none)), name: "a6-bot-question")

        let answered = PaceHelpBotSession()
        answered.start()
        answered.ask(.groupFlame)
        try Snapshot.render(page(PaceBotContent(session: answered, support: none)), name: "a6-bot-answer", languages: languages)
        // So sieht man es auf dem iPhone: Frage und Antwort oben im Bild, darunter die Eingabe.
        try await Snapshot.renderInWindow(
            NavigationStack { PaceBotView(session: answered, support: none, onOpenFeedback: {}) },
            name: "a6-bot-answer-screen"
        )

        let unknown = PaceHelpBotSession()
        unknown.start()
        unknown.send("Wie wird das Wetter morgen?")
        try Snapshot.render(page(PaceBotContent(session: unknown, support: none, showsSupport: false)), name: "a6-bot-unknown")

        try Snapshot.render(
            page(PaceBotContent(session: unknown, support: none, showsSupport: true, onOpenFeedback: {})),
            name: "a6-bot-support",
            languages: languages
        )
    }
}

// MARK: - Beispieldaten

@MainActor
enum A6Fixtures {
    static let groupID = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!

    static func person(_ index: Int, _ name: String, avatar: Bool = true) -> SocialProfile {
        let id = UUID(uuidString: String(format: "40000000-0000-4000-8000-%012d", index))!
        return SocialProfile(
            publicID: id,
            username: name.lowercased(),
            displayName: name,
            avatarPath: avatar ? "\(id.uuidString.lowercased())/photo.jpg" : nil
        )
    }

    static let mia = person(1, "Mia")
    static let jonas = person(2, "Jonas")
    static let lea = person(3, "Lea", avatar: false)
    static let groupImage = MediaReference(bucket: .groupImages, path: "\(groupID.uuidString.lowercased())/group.jpg")
    static let banner = MediaReference(bucket: .avatars, path: "\(Fixtures.publicUserID.uuidString.lowercased())/banner.jpg")
    static let ownAvatar = MediaReference(bucket: .avatars, path: "\(Fixtures.publicUserID.uuidString.lowercased())/me.jpg")

    static let richDetails = ProfileDetails(
        bio: "Jeden Tag ein bisschen aktiver. Fußball, lange Spaziergänge und meine erste 100-Tage-Serie. 🚶",
        interests: [.walking, .football, .hiking, .challenges],
        bannerPath: banner.path,
        showsAchievements: true,
        achievements: [.streak30, .bestDay20k]
    )

    /// Beispielbild: Farbverlauf mit einem Symbol (kein echtes Foto).
    static func image(_ colors: [UIColor], symbol: String, size: CGSize = CGSize(width: 400, height: 400)) -> Data {
        UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { context in
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil)!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let configuration = UIImage.SymbolConfiguration(pointSize: min(size.width, size.height) * 0.45, weight: .medium)
            if let glyph = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal) {
                glyph.draw(at: CGPoint(x: (size.width - glyph.size.width) / 2, y: (size.height - glyph.size.height) / 2))
            }
        }
    }

    /// Bildlader mit Beispielbildern, schon in allen Größen im Speicher (der Bild-Renderer wartet nicht auf Ladevorgänge).
    static func loader() async -> PaceImageLoader {
        let files: [MediaReference: Data] = [
            .avatar(mia.avatarPath)!: image([.systemTeal, .systemGreen], symbol: "figure.run"),
            .avatar(jonas.avatarPath)!: image([.systemOrange, .systemPink], symbol: "figure.walk"),
            ownAvatar: image([.systemIndigo, .systemTeal], symbol: "figure.hiking"),
            groupImage: image([.systemGreen, .systemMint], symbol: "figure.2"),
            banner: image([UIColor(red: 0.05, green: 0.35, blue: 0.25, alpha: 1), .systemMint], symbol: "mountain.2", size: CGSize(width: 1_200, height: 400)),
        ]
        let media = MediaRepositoryStub { $0.files = files }
        let loader = PaceImageLoader(repository: media)
        for reference in files.keys {
            for size in [PaceImageLoader.Size.pixels(96), .pixels(192), .pixels(384), .pixels(512), .bubble] {
                _ = await loader.image(for: reference, size: size)
            }
        }
        return loader
    }

    static func socialRepository() -> SocialRepositoryStub {
        SocialRepositoryStub { state in
            state.friends = [mia, jonas, lea].map { Friend(profile: $0, friendsSince: Fixtures.date(2026, 3, 14)) }
            let me = LeaderboardEntry(rank: 2, publicUserID: Fixtures.publicUserID, username: "niklas", displayName: "Niklas", competitionSteps: 8_432, isCurrentUser: true, avatarPath: ownAvatar.path)
            state.ranking = [
                LeaderboardEntry(rank: 1, publicUserID: mia.publicID, username: "mia", displayName: "Mia", competitionSteps: 10_204, isCurrentUser: false, avatarPath: mia.avatarPath),
                me,
                LeaderboardEntry(rank: 3, publicUserID: jonas.publicID, username: "jonas", displayName: "Jonas", competitionSteps: 6_870, isCurrentUser: false, avatarPath: jonas.avatarPath),
                LeaderboardEntry(rank: 4, publicUserID: lea.publicID, username: "lea", displayName: "Lea", competitionSteps: 3_115, isCurrentUser: false),
            ]
            state.groups = [
                SocialRepositoryStub.group(
                    id: groupID, name: "Smoking red", description: "Jeden Abend eine Runde.", kind: .friends,
                    memberCount: 12, currentStreak: 12, reached: 4, imagePath: groupImage.path
                ),
                SocialRepositoryStub.group(name: "Laufteam Büro", kind: .work, memberCount: 7, currentStreak: 2, reached: 1),
            ]
            state.groupRankings[groupID] = GroupRanking(
                totalParticipants: 12,
                groupToday: Fixtures.day(2026, 10, 16),
                dailyGoal: 8_000,
                entries: [
                    GroupRankingEntry(rank: 1, profile: mia, competitionSteps: 12_480, isCurrentUser: false, role: .member, reachedGoalToday: true),
                    GroupRankingEntry(rank: 2, profile: jonas, competitionSteps: 10_920, isCurrentUser: false, role: .member, reachedGoalToday: true),
                    GroupRankingEntry(rank: 3, profile: lea, competitionSteps: 7_280, isCurrentUser: false, role: .member, reachedGoalToday: false),
                ]
            )
            state.searchableProfiles = [mia, jonas]
        }
    }

    static func details() -> ProfileDetailsRepositoryStub {
        ProfileDetailsRepositoryStub { state in
            state.others[mia.publicID] = ProfileDetails(
                bio: "Laufen am Morgen, Fußball am Wochenende. ⚽️",
                interests: [.running, .football, .outdoor],
                bannerPath: banner.path,
                showsAchievements: false,
                achievements: [.streak7]
            )
            state.others[jonas.publicID] = ProfileDetails(
                bio: "Auf dem Weg zu 365 Tagen.",
                interests: [.walking, .everydayMovement],
                showsAchievements: true,
                achievements: [.streak100, .bestDay30k]
            )
        }
    }

    static func social() async -> (SocialViewModel, PaceImageLoader) {
        let chats = ChatListViewModel(repository: ChatRepositoryStub { state in
            state.conversations = [
                ChatFixtures.direct(id: UUID(), peer: mia, updatedAt: Fixtures.date(2026, 10, 16, 18, 5)),
                ChatFixtures.group(id: UUID(), groupID: groupID, title: "Smoking red", memberCount: 12, updatedAt: Fixtures.date(2026, 10, 16, 17, 40)),
            ]
        }, media: nil, calendar: Fixtures.activityCalendar, now: { Fixtures.date(2026, 10, 16, 18, 30) })
        let social = SocialViewModel(
            repository: socialRepository(),
            chats: chats,
            ownUsername: { "niklas" },
            calendar: Fixtures.activityCalendar,
            now: { Fixtures.date(2026, 10, 16, 18, 30) }
        )
        social.profileDetails = details()
        await social.load()
        return (social, await loader())
    }

    static func dashboard() async throws -> (HomeDashboardViewModel, PaceImageLoader) {
        let (social, loader) = await Self.social()
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard(social: social)
        await dashboard.loadStreakIfNeeded()
        return (dashboard, loader)
    }

    static func profile(details: ProfileDetails) async throws -> (ProfileViewModel, PaceImageLoader) {
        let (dashboard, store) = try await SnapshotFixtures.makeDashboard()
        try await store.updateAvatar(path: ownAvatar.path)
        let profile = ProfileViewModel(
            store: store,
            regions: RegionRepositoryStub(),
            streak: dashboard.streak,
            statistics: { dashboard.statistics(for: $0) },
            formatter: ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar),
            services: ProfileSettingsServices(
                settings: AppSettings(
                    store: InMemoryAppPreferencesStore(AppPreferences(appearance: .automatic, language: .system)),
                    preferredLanguages: { ["de-DE"] },
                    applyLanguage: { _ in }
                ),
                profiles: ProfileRepositoryStub(),
                media: MediaRepositoryStub(),
                profileDetails: ProfileDetailsRepositoryStub { $0.own = details },
                appVersion: "0.1.0 (1)"
            )
        )
        await profile.load()
        await profile.loadActivity()
        return (profile, await loader())
    }

    /// Verschiebt die senkrechte Scrollansicht der Seite waagerecht (wie es ein seitliches Ziehen früher konnte).
    static func shiftPageHorizontally(in view: UIView, by offset: CGFloat) {
        var candidates: [UIScrollView] = []
        func collect(_ view: UIView) {
            if let scrollView = view as? UIScrollView, !PaceVerticalScrollLockRules.isPager(scrollView),
               scrollView.contentSize.height > scrollView.bounds.height {
                candidates.append(scrollView)
            }
            view.subviews.forEach(collect)
        }
        collect(view)
        guard let page = candidates.max(by: { $0.contentSize.height < $1.contentSize.height }) else { return }
        page.contentOffset = CGPoint(x: page.contentOffset.x - offset, y: page.contentOffset.y)
        // Ein kleiner senkrechter Schritt hin und zurück, damit SwiftUI den sichtbaren Bereich neu bestimmt (sonst
        // fehlen im Bild Teile der Seite, die beim Versatz außerhalb lagen).
        page.contentOffset.y += 1
        page.contentOffset.y -= 1
        page.layoutIfNeeded()
    }
}
