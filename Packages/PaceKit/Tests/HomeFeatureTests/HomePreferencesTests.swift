import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
import Testing

// MARK: - Speicherformat

struct HomePreferencesCodingTests {
    private func decode(_ json: String) throws -> HomePreferences {
        try JSONDecoder().decode(HomePreferences.self, from: Data(json.utf8))
    }

    private func roundTrip(_ preferences: HomePreferences) throws -> HomePreferences {
        try JSONDecoder().decode(HomePreferences.self, from: JSONEncoder().encode(preferences))
    }

    @Test func versionThreeStoresIDKindSizeAndConfiguration() throws {
        let leon = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
        let marie = UUID(uuidString: "40000000-0000-4000-8000-000000000002")!
        let group = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
        let preferences = HomePreferences(modules: [
            HomeModule(id: "steps", kind: .stepsToday, size: .max),
            HomeModule(id: "run", kind: .friends, size: .large, configuration: HomeWidgetConfiguration(friendIDs: [leon, marie], customName: "Meine Laufrunde")),
            HomeModule(id: "class", kind: .groups, size: .small, configuration: HomeWidgetConfiguration(groupID: group)),
            HomeModule(id: "ranks", kind: .regionRanks, configuration: HomeWidgetConfiguration(regionLevels: [.country, .municipality])),
            HomeModule(id: "distance", kind: .activity, size: .max, configuration: HomeWidgetConfiguration(metric: .distance)),
            HomeModule(id: "near", kind: .neighborhood, size: .max, regionLevel: .state),
            HomeModule(id: "month", kind: .calendar, size: .large),
        ])

        let data = try JSONEncoder().encode(preferences)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == 3)
        let modules = try #require(json["modules"] as? [[String: Any]])
        let run = try #require(modules.first { $0["id"] as? String == "run" })
        let config = try #require(run["config"] as? [String: Any])
        #expect(config["name"] as? String == "Meine Laufrunde")
        #expect(config["friendIDs"] as? [String] == [leon.uuidString, marie.uuidString])
        // Widgets ohne eigene Einstellungen speichern keine leere Konfiguration.
        #expect(modules.first { $0["id"] as? String == "month" }?["config"] == nil)

        let decoded = try roundTrip(preferences)
        #expect(decoded == preferences)
        #expect(decoded.modules[1].title == "Meine Laufrunde")
        #expect(decoded.modules[2].configuration.groupID == group)
        // Ebenen stehen immer von klein nach groß.
        #expect(decoded.modules[3].regionLevels == [.municipality, .country])
        #expect(decoded.modules[4].metric == .distance)
        #expect(decoded.modules[5].regionLevel == .state)
        #expect(decoded.modules[5].neighborhoodRows == 7)
        #expect(decoded.modules[5].neighborhoodRadius == 6)
    }

    @Test func versionTwoIsTakenOverWithoutLoss() throws {
        let preferences = try decode(#"""
        {"version": 2, "stepGoal": 9000, "modules": [
          {"id": "a", "kind": "regionRanks", "size": "small"},
          {"id": "b", "kind": "stepsToday", "size": "large"},
          {"id": "c", "kind": "week", "size": "medium"},
          {"id": "d", "kind": "neighborhood", "size": "large", "regionLevel": "district"},
          {"id": "e", "kind": "friends", "size": "small"},
          {"id": "f", "kind": "groups", "size": "large"},
          {"id": "g", "kind": "streak", "size": "medium"}
        ]}
        """#)

        #expect(preferences.legacyStepGoal == 9_000)
        #expect(preferences.modules.map(\.id) == ["a", "b", "c", "d", "e", "f", "g"])
        #expect(preferences.modules.map(\.size) == [.small, .large, .medium, .large, .small, .large, .medium])
        #expect(preferences.modules[3].regionLevel == .district)
        // Alte Freunde- und Gruppen-Module zeigen weiter alle Freunde bzw. alle Gruppen.
        #expect(preferences.modules[4].configuration.friendIDs == nil)
        #expect(preferences.modules[5].configuration.groupID == nil)
        #expect(preferences.modules[0].regionLevels == RegionLevel.allCases)

        // Danach wird Version 3 gespeichert – mit allen Werten.
        let reloaded = try roundTrip(preferences)
        #expect(reloaded == preferences)
    }

    @Test func versionOneIsMigrated() throws {
        let preferences = try decode(#"""
        {"stepGoal": 12500, "sections": [
          {"section": "stepsToday", "isVisible": true},
          {"section": "regionRanks", "isVisible": false},
          {"section": "week", "isVisible": true},
          {"section": "neighborhood", "isVisible": true},
          {"section": "friends", "isVisible": false},
          {"section": "groups", "isVisible": true}
        ]}
        """#)

        #expect(preferences.legacyStepGoal == 12_500)
        // Reihenfolge bleibt, Ausgeblendetes entfällt, die Serie kommt nach der Woche.
        #expect(preferences.modules.map(\.kind) == [.stepsToday, .week, .streak, .neighborhood, .groups])
        #expect(preferences.modules.allSatisfy { $0.size == .medium })
        #expect(try roundTrip(preferences) == preferences)
    }

    @Test func unknownKindsSizesAndFieldsAreSkippedTolerantly() throws {
        let preferences = try decode(#"""
        {"version": 7, "futureFlag": true, "modules": [
          {"id": "a", "kind": "challenges", "size": "medium"},
          {"id": "b", "kind": "week", "size": "huge", "sparkle": 3},
          {"id": "c", "kind": "friends", "size": "max",
           "config": {"friendIDs": ["40000000-0000-4000-8000-000000000001", "kaputt"], "name": "  Büro   Runde ", "color": "red"}},
          {"id": "d", "kind": "regionRanks", "config": {"levels": ["state", "galaxy"]}},
          {"id": "e", "kind": "activity", "config": {"metric": "heartRate"}},
          {"kind": "streak"}
        ]}
        """#)

        // Unbekannte Art und Widget ohne ID entfallen, alles andere bleibt.
        #expect(preferences.modules.map(\.id) == ["b", "c", "d", "e"])
        // Unbekannte Größe → Standardgröße.
        #expect(preferences.modules[0].size == .medium)
        #expect(preferences.modules[1].size == .max)
        #expect(preferences.modules[1].configuration.friendIDs == [UUID(uuidString: "40000000-0000-4000-8000-000000000001")!])
        #expect(preferences.modules[1].configuration.customName == "Büro Runde")
        #expect(preferences.modules[2].regionLevels == [.state])
        #expect(preferences.modules[3].metric == .steps)
    }

    @Test func emptyOrBrokenDataFallsBackToDefaults() throws {
        #expect(try decode("{}").modules.map(\.kind) == HomePreferences.defaultModules().map(\.kind))
        #expect(try decode(#"{"sections": []}"#).modules.map(\.kind) == HomePreferences.defaultModules().map(\.kind))
    }

    @Test func configurationKeepsOnlyFieldsOfItsKind() {
        let messy = HomeWidgetConfiguration(
            friendIDs: [UUID(), UUID()],
            customName: "   ",
            groupID: UUID(),
            regionLevels: RegionLevel.allCases,
            metric: .distance
        )
        #expect(HomeModule(kind: .week, configuration: messy).configuration.isEmpty)
        #expect(HomeModule(kind: .friends, configuration: messy).configuration.groupID == nil)
        #expect(HomeModule(kind: .friends, configuration: messy).configuration.customName == nil)
        // Alle vier Ebenen gelten als Standard und werden nicht gespeichert.
        #expect(HomeModule(kind: .regionRanks, configuration: messy).configuration.regionLevels == nil)
        #expect(HomeModule(kind: .groups, configuration: messy).configuration.friendIDs == nil)
        #expect(HomeWidgetConfiguration.cleanedName(String(repeating: "x", count: 50))?.count == HomeWidgetConfiguration.nameLength)

        let id = UUID()
        let duplicates = HomeWidgetConfiguration(friendIDs: [id, id])
        #expect(HomeModule(kind: .friends, configuration: duplicates).configuration.friendIDs == [id])
    }

    @Test func titlesAndSizesAreLocalized() {
        let module = HomeModule(kind: .neighborhood, size: .large, regionLevel: .district)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(module.detailText == "Groß · Kreis")
            #expect(HomeModuleKind.friends.galleryTitle == "Freunde")
            #expect(HomeModuleKind.regionRanks.gallerySubtitle == "Stadt · Landkreis · Bundesland · Deutschland")
            #expect(HomeModuleSize.allCases.map(\.title) == ["Klein", "Mittel", "Groß", "Max"])
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(module.detailText == "Large · District")
            #expect(HomeModuleKind.stepsToday.title == "Your steps today")
            #expect(HomeModule(kind: .activity, configuration: HomeWidgetConfiguration(metric: .distance)).title == "Distance · 7 days")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(HomeModuleSize.allCases.map(\.title) == ["Маленький", "Средний", "Большой", "Максимум"])
            #expect(HomeModuleKind.streak.galleryTitle == "Личная серия")
        }
    }
}

// MARK: - Einstellungen

@MainActor
struct HomeSettingsTests {
    private func kinds(_ settings: HomeSettings) -> [HomeModuleKind] {
        settings.modules.map(\.kind)
    }

    @Test func defaultLayoutFollowsTheApprovedHomeDesign() {
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())

        #expect(kinds(settings) == [.regionRanks, .stepsToday, .week, .neighborhood, .friends, .groups, .streak])
        #expect(settings.modules.allSatisfy { $0.size == .medium })
        #expect(settings.modules.first { $0.kind == .neighborhood }?.regionLevel == .municipality)
        #expect(settings.modules.first { $0.kind == .week }?.regionLevel == nil)
        #expect(settings.addableKinds == [.regionRanks, .neighborhood, .friends, .groups, .activity, .calendar])
    }

    @Test func widgetsCanBeAddedRemovedResizedAndPersistAcrossRestarts() throws {
        let store = InMemoryHomePreferencesStore()
        let settings = HomeSettings(store: store)
        let friends = try #require(settings.modules.first { $0.kind == .friends })

        let removed = try #require(settings.remove(friends.id))
        #expect(removed.index == 4)
        #expect(!kinds(settings).contains(.friends))

        let district = try #require(settings.add(.neighborhood))
        settings.setRegionLevel(.district, for: district.id)
        settings.setSize(.max, for: district.id)
        #expect(settings.modules.last?.detailText == "Max · Kreis")
        #expect(settings.add(.week) == nil) // gibt es schon

        // Die Schrittkarte lässt sich nicht entfernen, aber in jeder Größe zeigen (seit Auftrag 5 auch „Klein“).
        let steps = try #require(settings.modules.first { $0.kind == .stepsToday })
        #expect(settings.remove(steps.id) == nil)
        settings.setSize(.small, for: steps.id)
        #expect(settings.module(id: steps.id)?.size == .small)
        settings.setSize(.max, for: steps.id)
        #expect(settings.module(id: steps.id)?.size == .max)

        // „Neustart“: ein neuer Leser desselben Speichers sieht dasselbe Layout.
        let restarted = HomeSettings(store: store)
        #expect(restarted.modules == settings.modules)

        // Auch über das echte Speicherformat (JSON in den UserDefaults).
        let suite = "pace.tests.home.\(UUID().uuidString)"
        let defaultsStore = UserDefaultsHomePreferencesStore(suiteName: suite)
        let persisted = HomeSettings(store: defaultsStore)
        persisted.setSize(.large, for: try #require(persisted.modules.first { $0.kind == .week }).id)
        #expect(HomeSettings(store: UserDefaultsHomePreferencesStore(suiteName: suite)).modules == persisted.modules)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    @Test func removedWidgetsCanBeRestoredAtTheirPosition() throws {
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())
        let week = try #require(settings.modules.first { $0.kind == .week })

        let removed = try #require(settings.remove(week.id))
        #expect(!kinds(settings).contains(.week))
        settings.restore(removed)
        #expect(kinds(settings) == [.regionRanks, .stepsToday, .week, .neighborhood, .friends, .groups, .streak])
        #expect(settings.module(id: week.id) == week)

        // Doppelt wiederherstellen ändert nichts.
        settings.restore(removed)
        #expect(settings.modules.count == 7)
    }

    @Test func severalFriendsWidgetsKeepTheirOwnSelection() throws {
        let store = InMemoryHomePreferencesStore()
        let settings = HomeSettings(store: store)
        let leon = UUID(), marie = UUID(), gotscha = UUID(), kollege = UUID()

        let run = try #require(settings.add(HomeModule(
            kind: .friends,
            size: .medium,
            configuration: HomeWidgetConfiguration(friendIDs: [leon, marie, gotscha], customName: "Meine Laufrunde")
        )))
        let work = try #require(settings.add(HomeModule(
            kind: .friends,
            size: .small,
            configuration: HomeWidgetConfiguration(friendIDs: [kollege], customName: "Arbeitskollegen")
        )))

        // Änderungen an Widget A betreffen Widget B nicht.
        #expect(settings.setConfiguration(HomeWidgetConfiguration(friendIDs: [leon], customName: "Sprint"), for: run.id))
        let restarted = HomeSettings(store: store)
        #expect(restarted.module(id: run.id)?.configuration.friendIDs == [leon])
        #expect(restarted.module(id: run.id)?.title == "Sprint")
        #expect(restarted.module(id: work.id)?.configuration.friendIDs == [kollege])
        #expect(restarted.module(id: work.id)?.title == "Arbeitskollegen")
        #expect(restarted.module(id: work.id)?.size == .small)
        #expect(restarted.modules.filter { $0.kind == .friends }.count == 3)
    }

    @Test func duplicateWidgetsAreRejected() throws {
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())
        let group = UUID()

        let first = try #require(settings.add(HomeModule(kind: .groups, configuration: HomeWidgetConfiguration(groupID: group))))
        let same = HomeModule(kind: .groups, size: .large, configuration: HomeWidgetConfiguration(groupID: group))
        #expect(settings.duplicate(of: same)?.id == first.id)
        #expect(settings.add(same) == nil)
        // „Alle Gruppen“ gibt es im Standardlayout schon.
        #expect(settings.add(HomeModule(kind: .groups)) == nil)
        // Eine andere Gruppe geht.
        #expect(settings.add(HomeModule(kind: .groups, configuration: HomeWidgetConfiguration(groupID: UUID()))) != nil)
        // Zwei Aktivitäts-Widgets mit derselben Kennzahl nicht, mit einer anderen schon.
        #expect(settings.add(HomeModule(kind: .activity)) != nil)
        #expect(settings.add(HomeModule(kind: .activity)) == nil)
        #expect(settings.add(HomeModule(kind: .activity, configuration: HomeWidgetConfiguration(metric: .activeEnergy))) != nil)
        // Ein Widget lässt sich nicht so bearbeiten, dass es ein anderes doppelt.
        #expect(!settings.setConfiguration(HomeWidgetConfiguration(groupID: group), for: settings.modules.last!.id))
    }

    @Test func replacingKeepsPositionAndIdentity() throws {
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())
        let neighborhood = try #require(settings.modules.first { $0.kind == .neighborhood })

        #expect(settings.replace(HomeModule(id: neighborhood.id, kind: .neighborhood, size: .large, regionLevel: .state)))
        #expect(settings.modules[3].id == neighborhood.id)
        #expect(settings.modules[3].size == .large)
        #expect(settings.modules[3].regionLevel == .state)
        // Die Art eines Widgets ändert sich beim Bearbeiten nicht.
        #expect(!settings.replace(HomeModule(id: neighborhood.id, kind: .week)))
        // Unbekannte Widgets lassen sich nicht ersetzen.
        #expect(!settings.replace(HomeModule(id: "gibt-es-nicht", kind: .week)))
    }

    @Test func dragAndDropAndVoiceOverMovesReorder() {
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())
        let ids = settings.modules.map(\.id)

        // Von oben nach unten: landet hinter dem Ziel.
        settings.move(ids[0], to: ids[2])
        #expect(kinds(settings) == [.stepsToday, .week, .regionRanks, .neighborhood, .friends, .groups, .streak])
        // Von unten nach oben: landet vor dem Ziel.
        settings.move(ids[6], to: ids[1])
        #expect(kinds(settings) == [.streak, .stepsToday, .week, .regionRanks, .neighborhood, .friends, .groups])

        settings.moveDown(ids[6])
        #expect(kinds(settings).prefix(2) == [.stepsToday, .streak])
        settings.moveUp(ids[6])
        #expect(kinds(settings).first == .streak)
        #expect(!settings.canMoveUp(ids[6]))
        #expect(settings.canMoveDown(ids[6]))
        // Am Rand passiert nichts.
        settings.moveUp(ids[6])
        #expect(kinds(settings).first == .streak)
    }

    @Test func listStyleMovesAndReset() {
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())

        settings.moveModules(fromOffsets: [1], toOffset: 0)
        #expect(kinds(settings).prefix(2) == [.stepsToday, .regionRanks])

        settings.moveModules(fromOffsets: [6], toOffset: 2)
        #expect(kinds(settings) == [.stepsToday, .regionRanks, .streak, .week, .neighborhood, .friends, .groups])

        settings.resetLayout()
        #expect(kinds(settings) == [.regionRanks, .stepsToday, .week, .neighborhood, .friends, .groups, .streak])
    }

    @Test func neighborhoodRadiiFollowTheWidgets() throws {
        let settings = HomeSettings(store: InMemoryHomePreferencesStore())
        #expect(settings.neighborhoodRadii == [.municipality: 2])

        let municipality = try #require(settings.modules.first { $0.kind == .neighborhood })
        settings.setSize(.small, for: municipality.id)
        #expect(settings.neighborhoodRadii == [.municipality: 1])

        let state = try #require(settings.add(.neighborhood))
        settings.setRegionLevel(.state, for: state.id)
        settings.setSize(.max, for: state.id)
        #expect(settings.neighborhoodRadii == [.municipality: 1, .state: 6])

        // Große Platzierungs-Widgets brauchen den Platz darüber in jeder Ebene.
        let ranks = try #require(settings.modules.first { $0.kind == .regionRanks })
        settings.setSize(.large, for: ranks.id)
        #expect(settings.neighborhoodRadii == [.municipality: 1, .district: 1, .state: 6, .country: 1])

        settings.remove(municipality.id)
        settings.remove(state.id)
        settings.setSize(.medium, for: ranks.id)
        #expect(settings.neighborhoodRadii.isEmpty)
        #expect(settings.showsStandings) // Platzierungs-Karten zeigen weiterhin Ränge
        settings.remove(ranks.id)
        #expect(!settings.showsStandings)
    }

    @Test func storedPreferencesAreRepaired() throws {
        let decoded = try JSONDecoder().decode(HomePreferences.self, from: Data(#"""
        {"version": 3, "modules": [
          {"id": "a", "kind": "week", "size": "large"},
          {"id": "b", "kind": "week", "size": "small"},
          {"id": "c", "kind": "neighborhood", "size": "small"},
          {"id": "c", "kind": "friends", "size": "small"},
          {"id": "d", "kind": "challenges", "size": "medium"},
          {"id": "e", "kind": "regionRanks", "size": "medium"},
          {"id": "f", "kind": "groups", "config": {"groupID": "50000000-0000-4000-8000-000000000001"}},
          {"id": "g", "kind": "groups", "config": {"groupID": "50000000-0000-4000-8000-000000000001"}}
        ]}
        """#.utf8))
        let settings = HomeSettings(store: InMemoryHomePreferencesStore(decoded))

        // Doppelte Woche, doppelte ID und doppelte Gruppe entfallen, unbekannte Art wird übersprungen, die Schrittkarte
        // ergänzt (nach den Platzierungen).
        #expect(kinds(settings) == [.week, .neighborhood, .regionRanks, .stepsToday, .groups])
        #expect(settings.modules[1].regionLevel == .municipality)
    }
}
