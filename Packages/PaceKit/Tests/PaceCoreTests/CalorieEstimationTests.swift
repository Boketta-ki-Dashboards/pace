import Foundation
import PaceCore
import PaceTestSupport
import Testing

/// Kalorienschätzung ohne Apple Watch (Auftrag 4, §14): Vorrang gemessener Werte, keine Doppelzählung, eindeutige
/// Kennzeichnung, Validierung, private Speicherung.
struct CalorieEstimationTests {
    private let metrics = BodyMetrics(heightCentimeters: 180, weightKilograms: 75, isEstimationEnabled: true)

    private func day(
        steps: Int,
        competition: Int? = nil,
        distance: Double? = nil,
        energy: Double? = nil
    ) -> DailyActivitySummary {
        DailyActivitySummary(
            date: Fixtures.day(2026, 10, 20),
            healthSteps: steps,
            competitionSteps: competition ?? steps,
            walkingRunningDistanceMeters: distance,
            activeEnergyKilocalories: energy
        )
    }

    @Test func modelUsesWeightAndDistanceNotAFixedValuePerStep() throws {
        // 5 km bei 75 kg: 5.000 m × 75 kg × 0,0005 = 187,5 kcal (ACSM, netto).
        let fromDistance = try #require(CalorieEstimator.kilocalories(automaticSteps: 6_500, measuredDistanceMeters: 5_000, metrics: metrics))
        #expect(abs(fromDistance - 187.5) < 0.001)
        // Ohne Strecke: Schritte × Schrittlänge (0,414 × 1,80 m = 0,7452 m).
        let fromSteps = try #require(CalorieEstimator.kilocalories(automaticSteps: 10_000, measuredDistanceMeters: nil, metrics: metrics))
        #expect(abs(fromSteps - 10_000 * 0.7452 * 75 * 0.0005) < 0.001)
        #expect(fromSteps > 270 && fromSteps < 290)
    }

    @Test func changedWeightOrHeightChangesTheEstimate() throws {
        let base = try #require(CalorieEstimator.kilocalories(automaticSteps: 8_000, measuredDistanceMeters: nil, metrics: metrics))
        var heavier = metrics
        heavier.weightKilograms = 90
        let heavy = try #require(CalorieEstimator.kilocalories(automaticSteps: 8_000, measuredDistanceMeters: nil, metrics: heavier))
        #expect(abs(heavy / base - 90.0 / 75.0) < 0.0001)
        var taller = metrics
        taller.heightCentimeters = 195
        let tall = try #require(CalorieEstimator.kilocalories(automaticSteps: 8_000, measuredDistanceMeters: nil, metrics: taller))
        #expect(tall > base)
    }

    @Test func measuredHealthKitCaloriesAlwaysWin() {
        let measured = day(steps: 9_000, distance: 6_500, energy: 324).estimatingActiveEnergy(with: metrics)
        #expect(measured.activeEnergy == .measured(324))
        #expect(measured.estimatedActiveEnergyKilocalories == nil)
        // Auch gemessene 0 bleibt gemessen.
        #expect(day(steps: 0, energy: 0).estimatingActiveEnergy(with: metrics).activeEnergy == .measured(0))
    }

    @Test func missingHealthKitCaloriesAreEstimatedOnlyWhenEnabled() throws {
        let missing = day(steps: 8_000, distance: 6_000)
        let estimated = missing.estimatingActiveEnergy(with: metrics)
        let value = try #require(estimated.activeEnergy.kilocalories)
        #expect(estimated.activeEnergy.isEstimated)
        #expect(abs(value - 6_000 * 75 * 0.0005) < 0.001)
        // Schritte und Wettbewerbsschritte bleiben unverändert.
        #expect(estimated.competitionSteps == missing.competitionSteps)
        #expect(estimated.healthSteps == missing.healthSteps)
        #expect(estimated.activeEnergyKilocalories == nil)

        var off = metrics
        off.isEstimationEnabled = false
        #expect(missing.estimatingActiveEnergy(with: off).activeEnergy == .unavailable)
        // Ohne Körperdaten keine Schätzung.
        #expect(missing.estimatingActiveEnergy(with: BodyMetrics(isEstimationEnabled: true)).activeEnergy == .unavailable)
        // Wieder ausgeschaltet: Die Schätzung verschwindet.
        #expect(estimated.estimatingActiveEnergy(with: off).activeEnergy == .unavailable)
    }

    @Test func noStepsMeansNothingToEstimate() {
        #expect(day(steps: 0).estimatingActiveEnergy(with: metrics).activeEnergy == .unavailable)
    }

    @Test func manualStepsDoNotInflateTheEstimate() throws {
        // 12.000 Schritte in Health, davon 4.000 manuell; die Health-Strecke könnte die manuellen enthalten.
        let manual = day(steps: 12_000, competition: 8_000, distance: 9_000)
        let value = try #require(manual.estimatingActiveEnergy(with: metrics).activeEnergy.kilocalories)
        #expect(abs(value - 8_000 * 0.7452 * 75 * 0.0005) < 0.001)
    }

    @Test func periodsNeverCountADayTwice() {
        let measured = DailyActivitySummary(date: Fixtures.day(2026, 10, 19), healthSteps: 9_000, competitionSteps: 9_000, activeEnergyKilocalories: 300)
        let missing = DailyActivitySummary(date: Fixtures.day(2026, 10, 20), healthSteps: 8_000, competitionSteps: 8_000, walkingRunningDistanceMeters: 6_000)
        let empty = DailyActivitySummary(date: Fixtures.day(2026, 10, 21), healthSteps: 0, competitionSteps: 0)
        let days = [measured, missing, empty].map { $0.estimatingActiveEnergy(with: metrics) }

        let period = ActivityPeriodSummary(period: .lastSevenDays, days: days)
        #expect(period.activeEnergy == .estimated(300 + 225))
        // Nur gemessene Tage: gemessen.
        #expect(ActivityPeriodSummary(period: .lastSevenDays, days: [days[0]]).activeEnergy == .measured(300))
        #expect(ActivityPeriodSummary(period: .lastSevenDays, days: [days[2]]).activeEnergy == .unavailable)
        // Bisherige Summe gemessener Werte bleibt unverändert (keine Schätzung darin).
        #expect(period.totalActiveEnergyKilocalories == 300)
    }

    @Test func historyAndOverviewGetEstimatesWithoutTouchingMeasuredDays() {
        let measured = DailyActivitySummary(date: Fixtures.day(2026, 10, 19), healthSteps: 9_000, competitionSteps: 9_000, activeEnergyKilocalories: 300)
        let missing = DailyActivitySummary(date: Fixtures.day(2026, 10, 20), healthSteps: 8_000, competitionSteps: 8_000)
        let history = ActivityHistory(days: [measured, missing], range: Fixtures.day(2026, 10, 19)...Fixtures.day(2026, 10, 20), updatedAt: Date())
            .estimatingActiveEnergy(with: metrics)
        #expect(history.summary(for: Fixtures.day(2026, 10, 19)) == measured)
        #expect(history.summary(for: Fixtures.day(2026, 10, 20))?.activeEnergy.isEstimated == true)
    }

    @Test func onlyValidBodyDataEnablesTheEstimate() {
        #expect(metrics.canEstimate)
        #expect(!BodyMetrics(heightCentimeters: 99, weightKilograms: 75, isEstimationEnabled: true).canEstimate)
        #expect(!BodyMetrics(heightCentimeters: 180, weightKilograms: 301, isEstimationEnabled: true).canEstimate)
        #expect(!BodyMetrics(heightCentimeters: 180, weightKilograms: 75, isEstimationEnabled: false).canEstimate)
    }
}

/// Eingaben und Speicherung der Körperdaten (nur auf dem Gerät).
@MainActor
struct BodyMetricsSettingsTests {
    @Test func inputsAreValidatedAndSaved() {
        let store = InMemoryBodyMetricsStore()
        let settings = BodyMetricsSettings(store: store)
        #expect(settings.metrics == BodyMetrics())

        #expect(settings.setHeight("abc") == .notANumber)
        #expect(settings.setHeight("20") == .outOfRange(BodyMetrics.heightRange))
        #expect(settings.setHeight("251") == .outOfRange(BodyMetrics.heightRange))
        #expect(settings.metrics.heightCentimeters == nil)
        #expect(settings.setHeight(" 182,5 ") == nil)
        #expect(settings.metrics.heightCentimeters == 182.5)

        #expect(settings.setWeight("29.9") == .outOfRange(BodyMetrics.weightRange))
        #expect(settings.setWeight("1e3") == .outOfRange(BodyMetrics.weightRange))
        #expect(settings.setWeight("nan") == .notANumber)
        #expect(settings.setWeight("74.44") == nil)
        #expect(settings.metrics.weightKilograms == 74.4)

        settings.setEstimationEnabled(true)
        #expect(settings.metrics.canEstimate)
        // „Neustart“: dieselben Werte.
        #expect(BodyMetricsSettings(store: store).metrics == settings.metrics)

        // Leere Eingabe löscht den Wert – dann wird nicht mehr geschätzt.
        #expect(settings.setWeight("") == nil)
        #expect(settings.metrics.weightKilograms == nil)
        #expect(!settings.metrics.canEstimate)
    }

    @Test func storedInUserDefaultsUnderAPaceKey() throws {
        let suite = "pace.tests.bodyMetrics.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsBodyMetricsStore(defaults: defaults)
        store.save(BodyMetrics(heightCentimeters: 170, weightKilograms: 60, isEstimationEnabled: true))
        #expect(store.load() == BodyMetrics(heightCentimeters: 170, weightKilograms: 60, isEstimationEnabled: true))
        // Der Schlüssel beginnt mit „pace.“: Datenexport und Löschen nach Kontolöschung erfassen ihn automatisch.
        #expect(defaults.data(forKey: "pace.bodyMetrics.v1") != nil)
    }
}
