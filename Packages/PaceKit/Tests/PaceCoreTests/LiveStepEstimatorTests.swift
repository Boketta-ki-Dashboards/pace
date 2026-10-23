import Foundation
import PaceCore
import PaceTestSupport
import Testing

/// Live-Anzeige der Schritte: Sensor beschleunigt, HealthKit bleibt maßgeblich, nichts wird doppelt gezählt.
struct LiveStepEstimatorTests {
    private let today = Fixtures.day(2026, 10, 23)
    private let tomorrow = Fixtures.day(2026, 10, 24)

    @Test func sensorStepsAfterTheHealthKitValueAreAdded() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(8_432, on: today)
        estimator.sensor(5_000, on: today)
        #expect(estimator.steps == 8_432)
        estimator.sensor(5_001, on: today)
        estimator.sensor(5_002, on: today)
        #expect(estimator.steps == 8_434)
    }

    @Test func aNewHealthKitValueRebasesInsteadOfAddingTwice() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(8_432, on: today)
        estimator.sensor(5_000, on: today)
        estimator.sensor(5_100, on: today)
        #expect(estimator.steps == 8_532)
        // HealthKit hat die 100 Schritte inzwischen selbst: 8 532 – nicht 8 632.
        estimator.healthKit(8_532, on: today)
        #expect(estimator.steps == 8_532)
        estimator.sensor(5_120, on: today)
        #expect(estimator.steps == 8_552)
    }

    @Test func displayDoesNotDropWhenHealthKitLagsBehind() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(8_432, on: today)
        estimator.sensor(5_000, on: today)
        estimator.sensor(5_200, on: today)
        #expect(estimator.steps == 8_632)
        // HealthKit kennt erst 50 der 200 Schritte – die Anzeige bleibt stehen, bis es aufholt.
        estimator.healthKit(8_482, on: today)
        #expect(estimator.steps == 8_632)
        estimator.healthKit(8_700, on: today)
        #expect(estimator.steps == 8_700)
    }

    @Test func withoutSensorHealthKitAlone() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(3_000, on: today)
        #expect(estimator.steps == 3_000)
        estimator.healthKit(3_400, on: today)
        #expect(estimator.steps == 3_400)
    }

    @Test func sensorBeforeTheFirstHealthKitValueIsIgnored() {
        var estimator = LiveStepEstimator()
        estimator.sensor(5_000, on: today)
        #expect(estimator.steps == 0)
        estimator.healthKit(1_200, on: today)
        estimator.sensor(5_010, on: today)
        estimator.sensor(5_030, on: today)
        #expect(estimator.steps == 1_220)
    }

    @Test func restartedSensorDoesNotCountTwice() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(2_000, on: today)
        estimator.sensor(4_000, on: today)
        estimator.sensor(4_050, on: today)
        #expect(estimator.steps == 2_050)
        // App im Hintergrund, Sensor gestoppt …
        estimator.sensorStopped()
        #expect(estimator.steps == 2_050)
        // … und neu gestartet mit kleinerem Zählerstand.
        estimator.sensor(10, on: today)
        estimator.sensor(30, on: today)
        #expect(estimator.steps == 2_070)
    }

    @Test func aNewDayStartsFromTheHealthKitValue() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(12_000, on: today)
        estimator.sensor(9_000, on: today)
        estimator.sensor(9_500, on: today)
        estimator.healthKit(40, on: tomorrow)
        #expect(estimator.steps == 40)
        estimator.sensor(9_600, on: tomorrow)
        estimator.sensor(9_650, on: tomorrow)
        #expect(estimator.steps == 90)
        // Werte vom Vortag zählen nicht mehr.
        estimator.sensor(9_700, on: today)
        #expect(estimator.steps == 90)
    }
}
