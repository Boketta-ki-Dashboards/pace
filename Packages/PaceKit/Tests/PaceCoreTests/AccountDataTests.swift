import Foundation
@testable import PaceCore
import Testing

/// Datenexport, lokale Daten (Export und Löschen) und gespeicherte Einstellungen.
@MainActor
struct AccountDataTests {
    // MARK: Export

    @Test func exportDocumentContainsServerAndDeviceData() throws {
        let server = Data(#"{"profile":{"username":"niklas"},"daily_activity":[{"day":"2026-10-19","steps":8432}]}"#.utf8)
        let device = [
            LocalDataSection(name: "settings", json: Data(#"{"appearance":"dark"}"#.utf8)),
            LocalDataSection(name: "stepGoalHistory", json: Data(#"[{"goal":10000}]"#.utf8)),
            LocalDataSection(name: "broken", json: Data("{".utf8)),
        ]
        let exportedAt = Date(timeIntervalSince1970: 1_792_224_000) // 2026-10-17T08:00:00Z

        let data = try AccountExport.document(server: server, device: device, exportedAt: exportedAt, appVersion: "0.1.0 (1)")
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["format"] as? String == "pace-export")
        #expect(json["version"] as? Int == 1)
        #expect(json["exportedAt"] as? String == "2026-10-17T08:00:00Z")
        #expect(json["appVersion"] as? String == "0.1.0 (1)")
        let serverPart = try #require(json["server"] as? [String: Any])
        #expect((serverPart["daily_activity"] as? [[String: Any]])?.first?["steps"] as? Int == 8432)
        let devicePart = try #require(json["device"] as? [String: Any])
        #expect(Set(devicePart.keys) == ["settings", "stepGoalHistory"]) // ungültige Abschnitte übersprungen
        #expect((json["notes"] as? [String])?.isEmpty == false)
    }

    @Test func invalidServerDataIsRejected() {
        #expect(throws: AccountExport.Failure.invalidServerData) {
            try AccountExport.document(server: Data("<html>".utf8), device: [], exportedAt: Date(), appVersion: "")
        }
    }

    @Test func fileNameContainsTheLocalDay() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let lateEvening = Date(timeIntervalSince1970: 1_792_274_400) // 2026-10-17T22:00:00Z = 18.10. 00:00 in Berlin
        #expect(AccountExport.fileName(for: lateEvening, timeZone: berlin) == "pace-export-2026-10-18.json")
        #expect(AccountExport.fileName(for: lateEvening, timeZone: TimeZone(identifier: "UTC") ?? berlin) == "pace-export-2026-10-17.json")
    }

    // MARK: Lokale Daten

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "pace-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    @Test func localDataExportsAndErasesOnlyPaceKeys() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        UserDefaultsAppPreferencesStore(suiteName: suite).save(AppPreferences(appearance: .dark, language: .fixed(.russian)))
        UserDefaultsStepStreakRecordStore(suiteName: suite).save(StepStreakRecord(
            days: 12,
            start: LocalDate(year: 2026, month: 10, day: 1),
            end: LocalDate(year: 2026, month: 10, day: 12)
        ))
        defaults.set(Data(#"{"id":"x"}"#.utf8), forKey: "pace.profile.abc")
        defaults.set(true, forKey: "pace.flag")
        defaults.set("bleibt", forKey: "other.key")

        let localData = UserDefaultsLocalAccountData(suiteName: suite)
        let sections = localData.exportSections()

        #expect(sections.map(\.name) == ["pace.flag", "profileCache", "settings", "streakRecord"])
        let settings = try #require(sections.first { $0.name == "settings" })
        let settingsJSON = try #require(try JSONSerialization.jsonObject(with: settings.json) as? [String: Any])
        #expect(settingsJSON["appearance"] as? String == "dark")

        localData.eraseAll()

        #expect(localData.exportSections().isEmpty)
        #expect(UserDefaultsAppPreferencesStore(suiteName: suite).load() == AppPreferences())
        #expect(defaults.string(forKey: "other.key") == "bleibt")
    }

    @Test func simpleValuesAreWrappedAsJSON() throws {
        #expect(UserDefaultsLocalAccountData.json(for: true).map { String(decoding: $0, as: UTF8.self) } == "true")
        #expect(UserDefaultsLocalAccountData.json(for: 42).map { String(decoding: $0, as: UTF8.self) } == "42")
        #expect(UserDefaultsLocalAccountData.json(for: Data([0xFF, 0x00])) == nil) // kein JSON
        #expect(UserDefaultsLocalAccountData.sectionName(for: "pace.home.preferences") == "homeLayout")
        #expect(UserDefaultsLocalAccountData.sectionName(for: "pace.goals.steps") == "stepGoalHistory")
    }

    @Test func inMemoryLocalDataCountsErasures() {
        let localData = InMemoryLocalAccountData([LocalDataSection(name: "a", json: Data("1".utf8))])
        localData.eraseAll()
        #expect(localData.exportSections().isEmpty)
        #expect(localData.erasures == 1)
    }

    // MARK: Einstellungen

    @Test func settingsArePersistedAppliedAndReset() {
        let store = InMemoryAppPreferencesStore()
        let applied = AppliedLanguages()
        let settings = AppSettings(store: store, preferredLanguages: { ["en-US"] }, applyLanguage: { applied.append($0) })
        #expect(applied.values == [.english]) // „Wie iPhone“ beim Start angewendet

        settings.language = .fixed(.russian)
        settings.appearance = .light
        settings.streakReminder = StreakReminderSettings(isEnabled: true, hour: 21, minute: 30)

        #expect(applied.values == [.english, .russian])
        #expect(store.load() == AppPreferences(
            appearance: .light,
            language: .fixed(.russian),
            streakReminder: StreakReminderSettings(isEnabled: true, hour: 21, minute: 30)
        ))

        settings.reset()
        #expect(store.load() == AppPreferences())
        #expect(applied.values.last == .english)
        #expect(settings.systemLanguage == .english)
    }

    @Test func unknownStoredValuesFallBackToDefaults() throws {
        let data = Data(#"{"appearance":"sepia","language":{"fixed":{"_0":"fr"}},"streakReminder":{"isEnabled":true,"hour":7,"minute":5}}"#.utf8)
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)
        #expect(preferences.appearance == .automatic)
        #expect(preferences.language == .system)
        #expect(preferences.streakReminder == StreakReminderSettings(isEnabled: true, hour: 7, minute: 5))
        // Ältere Versionen kannten keine Chat-Hinweise: eingeschaltet.
        #expect(preferences.chatMessageHints)
    }
}

/// Zeichnet angewendete Sprachen auf (statt die Sprache der App umzustellen).
@MainActor
private final class AppliedLanguages {
    private(set) var values: [AppLanguage] = []

    func append(_ language: AppLanguage) {
        values.append(language)
    }
}
