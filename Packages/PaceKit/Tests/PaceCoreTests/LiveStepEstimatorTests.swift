import Foundation
import PaceCore
import PaceTestSupport
import Testing

/// Live-Anzeige der Schritte: Sensor beschleunigt, HealthKit bleibt maßgeblich, nichts wird doppelt gezählt, nichts
/// fällt zurück. Die Sensorwerte sind wie bei `CMPedometer` ab Tagesbeginn gezählt.
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
        #expect(estimator.unconfirmedSteps == 2)
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
        #expect(estimator.unconfirmedSteps == 0)
        estimator.sensor(5_120, on: today)
        #expect(estimator.steps == 8_552)
    }

    /// Ursache von „nur +24 in Minuten“: Früher setzte jede Abfrage (alle 15 s) die Sensor-Basis neu, auch ohne neuen
    /// HealthKit-Wert. Hinkte HealthKit hinterher, ging der Sensor-Fortschritt dabei verloren.
    @Test func anUnchangedHealthKitValueDoesNotSwallowSensorSteps() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(8_000, on: today)
        estimator.sensor(3_000, on: today)
        for second in stride(from: 15, through: 120, by: 15) {
            estimator.sensor(3_000 + second * 100 / 60, on: today)
            // Abfrage im Vordergrund: HealthKit noch beim alten Stand.
            estimator.healthKit(8_000, on: today)
        }
        #expect(estimator.steps == 8_200)
    }

    @Test func aLaggingHealthKitValueDoesNotFreezeTheDisplay() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(8_432, on: today)
        estimator.sensor(5_000, on: today)
        estimator.sensor(5_200, on: today)
        #expect(estimator.steps == 8_632)
        // HealthKit kennt erst 50 der 200 Schritte: Anzeige bleibt, neue Sensorschritte kommen sofort dazu.
        estimator.healthKit(8_482, on: today)
        #expect(estimator.steps == 8_632)
        estimator.sensor(5_230, on: today)
        #expect(estimator.steps == 8_662)
        // HealthKit holt ein: kein Sprung, keine Doppelzählung.
        estimator.healthKit(8_662, on: today)
        #expect(estimator.steps == 8_662)
        estimator.sensor(5_240, on: today)
        #expect(estimator.steps == 8_672)
    }

    @Test func aHigherHealthKitValueWins() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(2_000, on: today)
        estimator.sensor(1_500, on: today)
        estimator.sensor(1_600, on: today)
        #expect(estimator.steps == 2_100)
        // Apple Watch hat ohne iPhone 900 Schritte gezählt.
        estimator.healthKit(3_000, on: today)
        #expect(estimator.steps == 3_000)
        estimator.sensor(1_650, on: today)
        #expect(estimator.steps == 3_050)
    }

    @Test func theSensorDayTotalIsAFloor() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(1_000, on: today)
        // Erster Wert nach dem Start ab Tagesbeginn: das iPhone hat heute schon 1 400 Schritte gezählt.
        estimator.sensor(1_400, on: today)
        #expect(estimator.steps == 1_400)
        estimator.sensor(1_450, on: today)
        #expect(estimator.steps == 1_450)
    }

    @Test func withoutSensorHealthKitAlone() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(3_000, on: today)
        #expect(estimator.steps == 3_000)
        estimator.healthKit(3_400, on: today)
        #expect(estimator.steps == 3_400)
        // Weniger (z. B. Einträge gelöscht): Die Anzeige fällt am selben Tag nicht zurück.
        estimator.healthKit(3_100, on: today)
        #expect(estimator.steps == 3_400)
    }

    @Test func restartedSensorDoesNotCountTwice() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(2_000, on: today)
        estimator.sensor(1_000, on: today)
        estimator.sensor(1_050, on: today)
        #expect(estimator.steps == 2_050)
        // App im Hintergrund, Sensor gestoppt …
        estimator.sensorStopped()
        #expect(estimator.steps == 2_050)
        // … und neu gestartet: weiterhin ab Tagesbeginn, inzwischen 1 080 – die 30 Schritte der Pause kommen dazu.
        estimator.sensor(1_080, on: today)
        #expect(estimator.steps == 2_080)
        estimator.sensor(1_100, on: today)
        #expect(estimator.steps == 2_100)
    }

    @Test func stepsOfThePauseAreNotAddedWhenHealthKitChangedMeanwhile() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(2_000, on: today)
        estimator.sensor(1_000, on: today)
        estimator.sensor(1_050, on: today)
        estimator.sensorStopped()
        // HealthKit hat in der Pause nachgezogen und enthält die Schritte aus der Pause womöglich schon.
        estimator.healthKit(2_120, on: today)
        estimator.sensor(1_120, on: today)
        #expect(estimator.steps == 2_120)
        estimator.sensor(1_130, on: today)
        #expect(estimator.steps == 2_130)
    }

    @Test func aSmallerCounterWithinAMeasurementStartsANewBase() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(2_000, on: today)
        estimator.sensor(4_000, on: today)
        estimator.sensor(4_050, on: today)
        #expect(estimator.steps == 4_050)
        estimator.sensor(10, on: today)
        #expect(estimator.steps == 4_050)
        estimator.sensor(30, on: today)
        #expect(estimator.steps == 4_070)
    }

    @Test func aNewDayStartsFromScratchAndIgnoresTheOldDay() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(12_000, on: today)
        estimator.sensor(11_000, on: today)
        estimator.sensor(11_500, on: today)
        estimator.healthKit(40, on: tomorrow)
        #expect(estimator.steps == 40)
        estimator.sensor(40, on: tomorrow)
        estimator.sensor(90, on: tomorrow)
        #expect(estimator.steps == 90)
        // Werte und Abfragen vom Vortag zählen nicht mehr.
        estimator.sensor(11_700, on: today)
        estimator.healthKit(12_500, on: today)
        #expect(estimator.steps == 90)
        #expect(estimator.day == tomorrow)
    }

    @Test func theFirstSensorValueOfANewDayStartsThatDay() {
        var estimator = LiveStepEstimator()
        estimator.healthKit(12_000, on: today)
        estimator.sensor(25, on: tomorrow)
        #expect(estimator.day == tomorrow)
        #expect(estimator.steps == 25)
        #expect(estimator.confirmedSteps == nil)
    }

    /// Zufällige Abfolgen: Die Anzeige fällt nie zurück, liegt nie unter HealthKit und nie über dem, was HealthKit
    /// und Sensor zusammen erklären können.
    @Test(arguments: 1...40)
    func neverDropsAndNeverInventsSteps(seed: Int) {
        var random = SeededRandom(seed: UInt64(seed))
        var estimator = LiveStepEstimator()
        var healthKit = Int(random.next() % 5_000)
        var sensor = Int(random.next() % 5_000)
        let initialSensor = sensor
        var maximumHealthKit = healthKit
        var maximumSensor = 0
        var shown = 0
        estimator.healthKit(healthKit, on: today)
        for _ in 0..<200 {
            switch random.next() % 10 {
            case 0...5:
                sensor += Int(random.next() % 40)
                maximumSensor = max(maximumSensor, sensor)
                estimator.sensor(sensor, on: today)
            case 6...8:
                healthKit += Int(random.next() % 120)
                maximumHealthKit = max(maximumHealthKit, healthKit)
                estimator.healthKit(healthKit, on: today)
            default:
                estimator.sensorStopped()
            }
            #expect(estimator.steps >= shown)
            #expect(estimator.steps >= healthKit)
            #expect(estimator.steps <= max(maximumHealthKit, maximumSensor) + sensor - initialSensor)
            shown = estimator.steps
        }
    }
}

/// Deterministische Zufallszahlen für wiederholbare Tests.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
