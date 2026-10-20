import ActivityFeature
import Foundation
import PaceCore
import PaceTestSupport
@testable import ProfileFeature
import Testing

/// Darstellung, Sprache, Navigation und Texte des Profil-Tabs.
@MainActor
struct ProfileSettingsTests {
    // MARK: Darstellung

    @Test func appearanceIsStoredAndApplied() {
        let env = ProfileSettingsEnvironment()
        #expect(env.viewModel.appearance == .automatic)

        env.viewModel.setAppearance(.dark)

        #expect(env.viewModel.appearance == .dark)
        #expect(env.settings.appearance == .dark)
        #expect(env.preferences.load().appearance == .dark)
        // Nach einem Neustart (neue Einstellungen aus demselben Speicher) bleibt die Wahl erhalten.
        let restarted = AppSettings(store: env.preferences, preferredLanguages: { [] }, applyLanguage: { _ in })
        #expect(restarted.appearance == .dark)
    }

    // MARK: Sprache

    @Test func languageChangeIsAppliedStoredAndReschedulesTheReminder() async {
        let notifications = NotificationSchedulerStub { $0.authorization = .authorized }
        let env = ProfileSettingsEnvironment(
            preferences: AppPreferences(language: .fixed(.german), streakReminder: StreakReminderSettings(isEnabled: true)),
            notifications: notifications
        )
        await env.viewModel.notifications.reschedule()
        #expect(notifications.state.withLock { $0.scheduled }.count == 1)

        // Die App-Sprache wechselt hier nur für diese Aufgabe (der Test darf die Sprache der App nicht umstellen).
        await PaceLocalization.$languageOverride.withValue(.russian) {
            await env.viewModel.setLanguage(.fixed(.russian))
        }

        // Neu geplant, damit die Erinnerung in der neuen Sprache erscheint.
        #expect(notifications.state.withLock { $0.scheduled }.count == 2)
        #expect(env.viewModel.language == .fixed(.russian))
        #expect(env.preferences.load().language == .fixed(.russian))
        #expect(env.appliedLanguages.current == [.german, .russian])
        #expect(env.settings.resolvedLanguage == .russian)
    }

    @Test func systemLanguageFollowsTheIPhone() async {
        let env = ProfileSettingsEnvironment(preferredLanguages: ["ru-RU", "en-US"])

        await env.viewModel.setLanguage(.system)

        #expect(env.appliedLanguages.current.last == .russian)
        #expect(env.viewModel.languageSummary == "Wie iPhone (Русский)")
        #expect(env.settings.systemLanguage == .russian)
    }

    @Test func unsupportedSystemLanguageFallsBackToGerman() {
        let settings = AppSettings(
            store: InMemoryAppPreferencesStore(AppPreferences(language: .system)),
            preferredLanguages: { ["fr-FR", "es"] },
            applyLanguage: { _ in }
        )
        #expect(settings.resolvedLanguage == .german)

        let english = AppSettings(
            store: InMemoryAppPreferencesStore(AppPreferences(language: .system)),
            preferredLanguages: { ["fr-FR", "en-GB"] },
            applyLanguage: { _ in }
        )
        #expect(english.resolvedLanguage == .english)
    }

    @Test func languageChoicesShowNativeAndLocalizedNames() {
        let env = ProfileSettingsEnvironment()
        let choices = env.viewModel.languageChoices

        #expect(choices.map(\.preference) == [.system, .fixed(.german), .fixed(.english), .fixed(.russian)])
        #expect(choices.map(\.title) == ["Wie iPhone", "Deutsch", "English", "Русский"])
        #expect(choices.map(\.subtitle) == ["Deutsch", nil, "Englisch", "Russisch"])
        #expect(env.viewModel.languageSummary == "Deutsch")

        PaceLocalization.$languageOverride.withValue(.english) {
            let english = env.viewModel.languageChoices
            #expect(english.first?.title == "Same as iPhone")
            #expect(english.map(\.subtitle) == ["Deutsch", "German", nil, "Russian"])
        }
    }

    // MARK: Navigation

    @Test func routesCanBeOpenedFromOutside() {
        let env = ProfileSettingsEnvironment()

        env.viewModel.open(.dataPrivacy)
        env.viewModel.open(.deleteAccount)
        #expect(env.viewModel.path == [.dataPrivacy, .deleteAccount])

        env.viewModel.show(.privacy)
        #expect(env.viewModel.path == [.privacy])
    }

    @Test func routeTitlesExistInAllLanguages() {
        let routes: [ProfileRoute] = [
            .account, .appearance, .language, .privacy, .notifications, .social, .dataPrivacy, .deleteAccount, .help,
            .feedback(.problem), .feedback(.idea), .legal, .legalDocument(.privacyPolicy), .legalDocument(.imprint),
            .legalDocument(.terms), .statistics(.init(period: .week)),
        ]
        for language in AppLanguage.allCases {
            PaceLocalization.$languageOverride.withValue(language) {
                let titles = routes.map(\.title)
                #expect(titles.allSatisfy { !$0.isEmpty })
            }
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(ProfileRoute.dataPrivacy.title == "Data & privacy")
            #expect(ProfileRoute.feedback(.idea).title == "Send feedback")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(ProfileRoute.notifications.title == "Уведомления")
        }
    }

    // MARK: Texte

    @Test func profileTextsFollowTheLanguage() async {
        let env = ProfileSettingsEnvironment()
        await env.viewModel.load()

        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(env.viewModel.recordText == "No record yet")
            #expect(AppearancePreference.dark.title == "Dark")
            #expect(AppIconChoice.automatic.title == "Automatic")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(AppIconChoice.light.title == "Светлая")
            #expect(ProfileViewModel.regionChangeMessage(for: ProfileError.network) == ProfileError.network.message)
            #expect(ProfileViewModel.regionChangeMessage(for: ProfileError.unexpected("x")) == "Не удалось изменить регион. Попробуй снова.")
        }
    }

    @Test func russianPluralFormsAreUsedForCounts() {
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(ProfileTexts.characters(1) == "1 символ")
            #expect(ProfileTexts.characters(3) == "3 символа")
            #expect(ProfileTexts.characters(20) == "20 символов")
            #expect(PaceLocalization.days(21) == "21 день")
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(ProfileTexts.characters(1) == "1 character")
            #expect(ProfileTexts.characters(2_000) == "2,000 characters")
        }
    }

    @Test func helpAndLegalContentIsCompleteInAllLanguages() {
        var germanTitles: [String] = []
        for language in AppLanguage.allCases {
            PaceLocalization.$languageOverride.withValue(language) {
                let sections = HelpContent.faq + PrivacyContent.dataSections
                    + LegalDocument.allCases.flatMap { PrivacyContent.sections(for: $0) }
                #expect(sections.allSatisfy { !$0.title.isEmpty && !$0.body.isEmpty })
                #expect(Set(HelpContent.faq.map(\.id)).count == HelpContent.faq.count)
                if language == .german {
                    germanTitles = HelpContent.faq.map(\.title)
                } else {
                    #expect(HelpContent.faq.map(\.title) != germanTitles)
                }
            }
        }
        // Keine erfundenen Adressen: Impressum und Verantwortlicher sind als „vom Betreiber zu ergänzen“ markiert.
        #expect(PrivacyContent.sections(for: .imprint).first?.body.contains("vom Betreiber ergänzt") == true)
        #expect(!PrivacyContent.sections(for: .imprint).contains { $0.body.contains("@") })
    }

    @Test func appVersionIsAvailable() {
        let env = ProfileSettingsEnvironment()
        #expect(env.viewModel.appVersion == "0.1.0 (1)")
    }
}
