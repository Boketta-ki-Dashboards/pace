import Foundation
import PaceBackend
import PaceCore
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Profilangaben mit Interessen 2.0 gegen den lokalen Stack (Migrationen 20261030100000 und 20261102100000): Katalog,
/// eigene Interessen, Sprachen, Land, Sichtbarkeit für andere und bei Blockierung.
@Suite(.enabled(if: IntegrationEnvironment.configuration != nil, "PACE_SUPABASE_URL/PACE_SUPABASE_PUBLISHABLE_KEY fehlen"))
struct ProfileInterestsIntegrationTests {
    @Test func interestsLanguagesAndCountryRoundTripWithVisibilityRules() async throws {
        let anna = try await IntegrationUser.make("Interessen", steps: 0)
        let ben = try await IntegrationUser.make("Leser", steps: 0)

        // Neues Profil: leer, Server kennt die Erweiterung.
        var details = try await anna.backend.profileDetails.ownDetails()
        #expect(details.supportsExtendedProfile)
        #expect(details.allInterests.isEmpty)

        details.interests = [.walking, .rap, .webDevelopment, .travel]
        details.customInterests = ["Musik produzieren", "Рэп-баттлы", "Kaffee ☕"]
        details.spokenLanguages = ["de", "ru", "sr"]
        details.countryCode = "GE"
        let saved = try await anna.backend.profileDetails.saveOwnDetails(details)
        #expect(saved == details)
        #expect(try await anna.backend.profileDetails.ownDetails() == details)

        // Andere sehen alles davon (Sichtbarkeit wie die Bio).
        let seen = try await ben.backend.profileDetails.details(of: anna.publicID)
        #expect(seen.interests == details.interests)
        #expect(seen.customInterests == details.customInterests)
        #expect(seen.spokenLanguages == ["de", "ru", "sr"])
        #expect(seen.countryCode == "GE")

        // Zwanzig insgesamt sind erlaubt, Land entfernen geht mit null.
        details.interests = Array(ProfileInterest.allCases.prefix(17))
        details.countryCode = nil
        let twenty = try await anna.backend.profileDetails.saveOwnDetails(details)
        #expect(twenty.allInterests.count == 20)
        #expect(twenty.countryCode == nil)

        // Gesperrt: Ben hat Anna blockiert – Anna kann Bens Profil nicht mehr öffnen, Ben sieht von Anna nichts davon.
        try await ben.social.block(anna.publicID)
        let blocked = try await ben.backend.profileDetails.details(of: anna.publicID)
        #expect(blocked.allInterests.isEmpty)
        #expect(blocked.spokenLanguages.isEmpty)
        #expect(blocked.countryCode == nil)
        try await ben.social.unblock(anna.publicID)
    }

    @Test func serverRejectsWhatTheAppWouldNeverSend() async throws {
        let anna = try await IntegrationUser.make("Regeln", steps: 0)
        var details = try await anna.backend.profileDetails.ownDetails()
        details.customInterests = ["Freestyle"]
        _ = try await anna.backend.profileDetails.saveOwnDetails(details)
        // Die App prüft vorher; ungültige Werte erreichen den Server nicht (invalid ohne Anfrage).
        details.customInterests = ["Freestyle", "FREESTYLE"]
        await #expect(throws: ProfileDetailsError.invalid) {
            _ = try await anna.backend.profileDetails.saveOwnDetails(details)
        }
        #expect(try await anna.backend.profileDetails.ownDetails().customInterests == ["Freestyle"])
    }
}
