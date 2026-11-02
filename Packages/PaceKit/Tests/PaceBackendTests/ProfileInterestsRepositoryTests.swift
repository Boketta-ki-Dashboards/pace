import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PaceBackend
import PaceCore
import Testing

/// Interessen 2.0 (Migration 20261102100000): Erkennen des Serverstands, eigene Interessen, Sprachen und Land – und
/// unveränderter Betrieb mit Servern, die nur 20261030100000 kennen.
struct ProfileInterestsRepositoryTests {
    private static let legacyJSON = """
    {"bio":"Hallo","interests":["walking","hiking","fitness"],"banner_path":null,"shows_achievements":false,"achievements":[]}
    """

    private static let extendedJSON = """
    {"bio":null,"interests":["rap","walking","galaxy"],"custom_interests":["Musik produzieren","musik produzieren","Рэп-баттлы"],
     "spoken_languages":["de","sr","Deutsch"],"country_code":"IT","banner_path":null,"shows_achievements":false,"achievements":[]}
    """

    private func body(_ request: RecordedRequest?) throws -> [String: Any] {
        let data = try #require(request?.body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func olderServerKeepsTheOldLimitsAndColumns() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("POST", "/rest/v1/rpc/social_profile_details", .json(Self.legacyJSON))
        harness.stub("PATCH", "/rest/v1/profiles", .json(Self.legacyJSON))

        let details = try await harness.backend.profileDetails.details(of: UUID())
        #expect(!details.supportsExtendedProfile)
        #expect(details.interests == [.walking, .hiking, .fitness])
        #expect(details.interestLimit == 5)

        // Neue Katalogeinträge und eigene Angaben gehen an einen älteren Server nicht mit (er würde sie ablehnen).
        var changed = details
        changed.interests = [.walking, .rap, .hiking, .fitness, .cycling, .running, .football]
        changed.customInterests = ["Freestyle"]
        changed.spokenLanguages = ["de"]
        changed.countryCode = "IT"
        _ = try await harness.backend.profileDetails.saveOwnDetails(changed)
        let request = harness.lastRequest("PATCH", "/rest/v1/profiles")
        let sent = try body(request)
        #expect(sent["interests"] as? [String] == ["walking", "hiking", "fitness", "cycling", "running"])
        #expect(sent["custom_interests"] == nil)
        #expect(sent["spoken_languages"] == nil)
        #expect(sent.keys.contains("country_code") == false)
        #expect(request?.query("select")?.contains("custom_interests") == false)
    }

    @Test func extendedServerIsDetectedAndValuesAreCleanedUp() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("POST", "/rest/v1/rpc/social_profile_details", .json(Self.extendedJSON))

        let details = try await harness.backend.profileDetails.details(of: UUID())
        #expect(details.supportsExtendedProfile)
        #expect(details.interestLimit == 20)
        // Unbekannte ID (neuere App) fällt weg, Doppelte und ungültige Werte auch.
        #expect(details.interests == [.rap, .walking])
        #expect(details.customInterests == ["Musik produzieren", "Рэп-баттлы"])
        #expect(details.spokenLanguages == ["de", "sr"])
        #expect(details.countryCode == "IT")
        #expect(details.allInterests.map(\.id) == ["catalog:rap", "catalog:walking", "custom:musik produzieren", "custom:рэп-баттлы"])
    }

    @Test func extendedSaveSendsTheNewColumnsAndRemovesTheCountryWithNull() async throws {
        let harness = BackendTestHarness()
        try await harness.signIn()
        harness.stub("PATCH", "/rest/v1/profiles", .json(Self.extendedJSON))

        var details = ProfileDetails(
            interests: [.rap, .basketball],
            customInterests: ["Freestyle Rap", "Kaffee ☕"],
            spokenLanguages: ["de", "ru", "ka"],
            countryCode: nil,
            supportsExtendedProfile: true
        )
        _ = try await harness.backend.profileDetails.saveOwnDetails(details)
        let request = harness.lastRequest("PATCH", "/rest/v1/profiles")
        let sent = try body(request)
        #expect(sent["interests"] as? [String] == ["rap", "basketball"])
        #expect(sent["custom_interests"] as? [String] == ["Freestyle Rap", "Kaffee ☕"])
        #expect(sent["spoken_languages"] as? [String] == ["de", "ru", "ka"])
        #expect(sent["country_code"] is NSNull)
        #expect(request?.query("select")?.contains("custom_interests,spoken_languages,country_code") == true)

        // Ungültige Angaben gar nicht erst senden.
        details.customInterests = ["Rap", "rap"]
        await #expect(throws: ProfileDetailsError.invalid) {
            _ = try await harness.backend.profileDetails.saveOwnDetails(details)
        }
        details.customInterests = []
        details.spokenLanguages = ["Deutsch"]
        await #expect(throws: ProfileDetailsError.invalid) {
            _ = try await harness.backend.profileDetails.saveOwnDetails(details)
        }
        details.spokenLanguages = []
        details.interests = Array(ProfileInterest.allCases.prefix(15))
        details.customInterests = ["Eins", "Zwei", "Drei", "Vier", "Fünf", "Sechs"]
        await #expect(throws: ProfileDetailsError.invalid) {
            _ = try await harness.backend.profileDetails.saveOwnDetails(details)
        }
        #expect(harness.requests("PATCH", pathPrefix: "/rest/v1/profiles").count == 1)
    }
}
