@testable import ActivityFeature
import DesignSystem
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
@testable import ProfileFeature
import SwiftUI
import Testing

/// Profil-Tab und alle Einstellungs-Unterseiten – jeweils mit Kopfzeile, in Hell und Dunkel.
@MainActor
@Suite(.snapshotsEnabled)
struct ProfileSnapshotTests {
    /// Profil mit allen Diensten als Test-Doubles (nur für Bilder).
    private func makeProfile() async throws -> ProfileViewModel {
        let (dashboard, store) = try await SnapshotFixtures.makeDashboard()
        let settings = AppSettings(
            store: InMemoryAppPreferencesStore(AppPreferences(
                appearance: .automatic,
                language: .system,
                streakReminder: StreakReminderSettings(isEnabled: true, hour: 19, minute: 0)
            )),
            preferredLanguages: { ["de-DE"] },
            applyLanguage: { _ in }
        )
        let social = SocialRepositoryStub { state in
            state.blocked = [
                SocialProfile(publicID: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!, username: "spam_bot", displayName: "Max Muster"),
            ]
        }
        let profile = ProfileViewModel(
            store: store,
            regions: RegionRepositoryStub(),
            appIcons: AppIconSettingStub(),
            streak: dashboard.streak,
            statistics: { dashboard.statistics(for: $0) },
            formatter: ActivityFormatter(locale: Locale(identifier: "de_DE"), calendar: Fixtures.activityCalendar),
            services: ProfileSettingsServices(
                settings: settings,
                profiles: ProfileRepositoryStub(),
                notifications: NotificationSchedulerStub { $0.authorization = .authorized },
                account: AccountRepositoryStub(),
                media: MediaRepositoryStub(),
                social: social,
                auth: AuthStub(storedSession: AuthSession(userID: Fixtures.userID, isAnonymous: true)),
                appVersion: "0.1.0 (1)"
            )
        )
        profile.openSocial = {}
        await profile.load()
        await profile.loadActivity()
        await profile.notifications.refreshAuthorization()
        await profile.privacy.blockedUsers.load()
        await profile.account.loadSession()
        return profile
    }

    private var backTitle: String { ProfileTexts.profileTitle }

    @Test func profile() async throws {
        let profile = try await makeProfile()
        try Snapshot.render(
            ProfileContent(viewModel: profile).padding(PaceSpacing.m),
            name: "profile",
            languages: [.german, .english, .russian]
        )
    }

    @Test func account() async throws {
        let profile = try await makeProfile()
        try Snapshot.render(
            AccountPageContent(viewModel: profile.account, backTitle: backTitle).padding(PaceSpacing.m),
            name: "profile-account",
            languages: [.german, .english, .russian]
        )
    }

    @Test func appearance() async throws {
        let profile = try await makeProfile()
        try Snapshot.render(
            AppearancePageContent(viewModel: profile, backTitle: backTitle).padding(PaceSpacing.m),
            name: "profile-appearance"
        )
    }

    @Test func language() async throws {
        let profile = try await makeProfile()
        try Snapshot.render(
            LanguagePageContent(viewModel: profile, backTitle: backTitle).padding(PaceSpacing.m),
            name: "profile-language",
            languages: [.german, .english, .russian]
        )
    }

    @Test func privacy() async throws {
        let profile = try await makeProfile()
        try Snapshot.render(
            PrivacyPageContent(viewModel: profile, backTitle: backTitle).padding(PaceSpacing.m),
            name: "profile-privacy"
        )
        try Snapshot.render(
            SocialSettingsPageContent(viewModel: profile, backTitle: backTitle).padding(PaceSpacing.m),
            name: "profile-social"
        )
    }

    @Test func notifications() async throws {
        let profile = try await makeProfile()
        try Snapshot.render(
            NotificationsPageContent(viewModel: profile.notifications, backTitle: backTitle).padding(PaceSpacing.m),
            name: "profile-notifications"
        )
    }

    @Test func dataPrivacy() async throws {
        let profile = try await makeProfile()
        try Snapshot.render(
            DataPrivacyPageContent(viewModel: profile.dataPrivacy, backTitle: backTitle).padding(PaceSpacing.m),
            name: "profile-data-privacy",
            languages: [.german, .english, .russian]
        )
        profile.dataPrivacy.confirmationText = "niklas"
        try Snapshot.render(
            DeleteAccountPageContent(viewModel: profile.dataPrivacy, backTitle: ProfileRoute.dataPrivacy.title) {
                Text(verbatim: "niklas")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(PaceSpacing.m),
            name: "profile-delete-account"
        )
    }

    @Test func help() async throws {
        let profile = try await makeProfile()
        try Snapshot.render(
            HelpPageContent(appVersion: profile.appVersion, backTitle: backTitle, expanded: ["steps"]).padding(PaceSpacing.m),
            name: "profile-help",
            languages: [.german, .english, .russian]
        )
        let feedback = profile.makeFeedback(.problem)
        feedback.message = "Die Statistik zeigt für gestern keine Schritte an."
        try Snapshot.render(
            FeedbackPageContent(viewModel: feedback, backTitle: ProfileRoute.help.title) {
                Text(verbatim: feedback.message)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            }
            .padding(PaceSpacing.m),
            name: "profile-feedback"
        )
        try Snapshot.render(
            LegalDocumentPageContent(document: .privacyPolicy, backTitle: ProfileRoute.legal.title).padding(PaceSpacing.m),
            name: "profile-legal-privacy"
        )
    }
}
