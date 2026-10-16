import Foundation
import HealthKit
import PaceCore

/// Zuordnung der plattformunabhängigen Kennzahlen zu HealthKit-Typen und -Einheiten.
enum HealthMetricMapping {
    /// Die fünf gelesenen Typen – bewusst nur Bewegungsdaten.
    /// Berechnet statt gespeichert, damit kein globaler Zustand mit HealthKit-Objekten entsteht.
    static var quantityTypes: [HKQuantityType] {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.flightsClimbed),
            HKQuantityType(.appleExerciseTime),
        ]
    }

    static func quantityType(for metric: ActivityMetric) -> HKQuantityType {
        switch metric {
        case .steps, .competitionSteps: HKQuantityType(.stepCount)
        case .walkingRunningDistance: HKQuantityType(.distanceWalkingRunning)
        case .activeEnergy: HKQuantityType(.activeEnergyBurned)
        case .flightsClimbed: HKQuantityType(.flightsClimbed)
        case .exerciseTime: HKQuantityType(.appleExerciseTime)
        }
    }

    static func unit(for metric: ActivityMetric) -> HKUnit {
        switch metric {
        case .steps, .competitionSteps, .flightsClimbed: .count()
        case .walkingRunningDistance: .meter()
        case .activeEnergy: .kilocalorie()
        case .exerciseTime: .minute()
        }
    }

    /// Zusätzlicher Filter je Kennzahl.
    ///
    /// Wettbewerbsschritte schließen Samples aus, die als manuell eingetragen markiert sind
    /// (`HKMetadataKeyWasUserEntered == true`, z. B. „Daten hinzufügen“ in der Health-App). Automatisch erfasste
    /// Samples von iPhone und Apple Watch tragen den Schlüssel nicht und erfüllen deshalb `!= true`.
    /// Nicht `== false` verwenden – das würde fast alle Sensordaten ausschließen.
    static func additionalPredicate(for metric: ActivityMetric) -> NSPredicate? {
        guard metric == .competitionSteps else { return nil }
        return HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyWasUserEntered,
            operatorType: .notEqualTo,
            value: NSNumber(value: true)
        )
    }
}

/// Übersetzt HealthKit-Fehler in plattformunabhängige Fehler.
enum HealthKitErrorMapping {
    static func map(_ error: Error, fallback: (String) -> HealthDataError) -> HealthDataError {
        if let error = error as? HealthDataError {
            return error
        }
        if let error = error as? HKError {
            switch error.code {
            case .errorHealthDataUnavailable, .errorHealthDataRestricted:
                return .healthDataUnavailable
            case .errorDatabaseInaccessible:
                return .protectedDataUnavailable
            default:
                break
            }
        }
        return fallback(error.localizedDescription)
    }
}
