import Foundation
import HealthKit
import PaceCore
@testable import PaceHealth
import Testing

/// Prüft die Abfrage-Bausteine für HealthKit. Läuft nur auf Apple-Plattformen (iOS-Simulator in der CI).
struct HealthMetricMappingTests {
    /// Wettbewerbsschritte schließen manuell eingetragene Samples aus: `HKMetadataKeyWasUserEntered != true`.
    @Test func competitionStepsExcludeManuallyEnteredSamples() throws {
        let predicate = try #require(HealthMetricMapping.additionalPredicate(for: .competitionSteps))

        let expected = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyWasUserEntered,
            operatorType: .notEqualTo,
            value: NSNumber(value: true)
        )
        #expect(predicate == expected)
        #expect(predicate.predicateFormat.contains(HKMetadataKeyWasUserEntered))

        // `== false` würde fast alle Sensordaten ausschließen, weil sie den Schlüssel gar nicht tragen.
        let wrong = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyWasUserEntered,
            operatorType: .equalTo,
            value: NSNumber(value: false)
        )
        #expect(predicate != wrong)
    }

    @Test(arguments: [ActivityMetric.steps, .walkingRunningDistance, .activeEnergy, .flightsClimbed, .exerciseTime])
    func otherMetricsAreNotFiltered(_ metric: ActivityMetric) {
        #expect(HealthMetricMapping.additionalPredicate(for: metric) == nil)
    }

    /// Health- und Wettbewerbsschritte stammen aus derselben Quelle; nur der Filter unterscheidet sie.
    @Test func bothStepCountsUseTheStepCountType() {
        #expect(HealthMetricMapping.quantityType(for: .steps) == HKQuantityType(.stepCount))
        #expect(HealthMetricMapping.quantityType(for: .competitionSteps) == HKQuantityType(.stepCount))
    }

    /// Pace liest ausschließlich diese fünf Bewegungsdaten – keine Herzfrequenz, keinen Schlaf, kein Gewicht.
    @Test func readsOnlyTheFiveActivityTypes() {
        let identifiers = Set(HealthMetricMapping.quantityTypes.map(\.identifier))

        #expect(identifiers == [
            HKQuantityTypeIdentifier.stepCount.rawValue,
            HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
            HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            HKQuantityTypeIdentifier.flightsClimbed.rawValue,
            HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
        ])
    }
}
