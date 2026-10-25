import Foundation
import PaceCore
import PaceTestSupport
import Testing

/// Simulation des Live-Abgleichs wie in der App: Der Sensor meldet etwa alle 2,5 s, das iPhone schreibt seine Schritte
/// gebündelt und Minuten später nach HealthKit, Pace fragt HealthKit im Vordergrund alle 15 s ab.
///
/// Das sind **simulierte** Ereignisse – kein Test mit echtem Sensor. Auf dem iPhone prüft man das mit der
/// 5-Minuten-Gehprobe aus `docs/IPHONE_TEST.md`.
struct LiveStepSimulationTests {
    /// 100 Schritte pro Minute für 5 Minuten: 30 s ≈ 50, 60 s ≈ 100, 120 s ≈ 200, 300 s ≈ 500.
    static let checkpoints: [(second: TimeInterval, steps: Int)] = [(30, 50), (60, 100), (120, 200), (300, 500)]

    // MARK: 1 Gleichmäßiges Gehen

    @Test func scenario01ConstantWalkingShowsEveryStep() {
        var scenario = LiveStepScenario(walk: .constant(stepsPerMinute: 100, duration: 300))
        let result = scenario.run(until: 300)
        for checkpoint in Self.checkpoints {
            result.expectShown(at: checkpoint.second, near: scenario.startTotal + checkpoint.steps)
        }
    }

    /// Wie 1, aber HealthKit liegt über dem iPhone-Zähler (Apple Watch zählt mit): Hier trägt nur der Abgleich über
    /// die Basis – genau dort ging früher der Fortschritt verloren.
    @Test func scenario01bConstantWalkingAboveAHigherHealthKitBase() {
        var scenario = LiveStepScenario(walk: .constant(stepsPerMinute: 100, duration: 300), otherSourceSteps: 2_000)
        let result = scenario.run(until: 300)
        for checkpoint in Self.checkpoints {
            result.expectShown(at: checkpoint.second, near: scenario.startTotal + checkpoint.steps)
        }
    }

    // MARK: 2–4 Tempo, Pause, Fortsetzung

    @Test func scenario02FasterWalking() {
        var scenario = LiveStepScenario(
            walk: WalkingProfile([.init(duration: 120, stepsPerMinute: 100), .init(duration: 120, stepsPerMinute: 150)]),
            otherSourceSteps: 1_000
        )
        let result = scenario.run(until: 240)
        result.expectShown(at: 120, near: scenario.startTotal + 200)
        result.expectShown(at: 180, near: scenario.startTotal + 350)
        result.expectShown(at: 240, near: scenario.startTotal + 500)
    }

    @Test func scenario03And04PauseHoldsAndWalkingContinues() {
        var scenario = LiveStepScenario(
            walk: WalkingProfile([
                .init(duration: 120, stepsPerMinute: 100),
                .init(duration: 120, stepsPerMinute: 0),
                .init(duration: 60, stepsPerMinute: 100),
            ]),
            otherSourceSteps: 500
        )
        let result = scenario.run(until: 300)
        result.expectShown(at: 120, near: scenario.startTotal + 200)
        // Pause: Der Wert bleibt stehen – auch wenn HealthKit währenddessen nachzieht.
        result.expectShown(at: 180, exactly: result.shown(at: 120))
        result.expectShown(at: 240, exactly: result.shown(at: 120))
        result.expectShown(at: 300, near: scenario.startTotal + 300)
    }

    // MARK: 5–7 HealthKit verspätet, holt ein, liegt höher

    @Test func scenario05HealthKitVeryLate() {
        var scenario = LiveStepScenario(walk: .constant(stepsPerMinute: 100, duration: 300), otherSourceSteps: 800, healthKitLag: 600)
        let result = scenario.run(until: 300)
        result.expectShown(at: 300, near: scenario.startTotal + 500)
        #expect(result.confirmed(at: 300) == scenario.startTotal)
    }

    @Test func scenario06HealthKitCatchesUpWithoutDoubleCounting() {
        var scenario = LiveStepScenario(walk: .constant(stepsPerMinute: 100, duration: 300), otherSourceSteps: 800)
        let result = scenario.run(until: 900)
        // HealthKit kennt jetzt alle 500 Schritte: Anzeige = HealthKit, nichts doppelt.
        #expect(result.confirmed(at: 900) == scenario.startTotal + 500)
        result.expectShown(at: 900, exactly: scenario.startTotal + 500)
    }

    /// Liegt ein neuer HealthKit-Wert über der Anzeige, ist unklar, ob er die schon angezeigten Sensorschritte enthält.
    /// Pace zählt sie deshalb nicht doppelt (keine erfundenen Schritte) und holt die Differenz mit dem nächsten
    /// HealthKit-Stand auf.
    @Test func scenario07HigherHealthKitValueFromAnotherDevice() {
        var scenario = LiveStepScenario(walk: .constant(stepsPerMinute: 100, duration: 300), otherSourceSteps: 300)
        scenario.extraHealthKitSteps = [(150, 400)]
        let result = scenario.run(until: 900)
        result.expectShown(at: 120, near: scenario.startTotal + 200)
        // Die Watch meldet 400 Schritte, die das iPhone nie gesehen hat: Anzeige springt auf HealthKit und läuft weiter.
        #expect(result.shown(at: 150) == scenario.startTotal + 400)
        result.expectShown(at: 300, near: scenario.startTotal + 400 + 250)
        // HealthKit kennt später alle Schritte des Gangs.
        result.expectShown(at: 900, exactly: scenario.startTotal + 400 + 500)
    }

    // MARK: 8–9 App verlassen, Sensor neu gestartet

    @Test func scenario08LeavingAndReturningToTheApp() {
        var scenario = LiveStepScenario(walk: .constant(stepsPerMinute: 100, duration: 300))
        scenario.background = 91...210
        let result = scenario.run(until: 300)
        result.expectShown(at: 90, near: scenario.startTotal + 150)
        // Im Hintergrund misst Pace nicht; der angezeigte Stand bleibt.
        #expect(result.shown(at: 200) >= result.shown(at: 90))
        // Zurück: Der Sensor zählt ab Tagesbeginn, die Schritte aus dem Hintergrund sind sofort da.
        result.expectShown(at: 215, near: scenario.startTotal + 358)
        result.expectShown(at: 300, near: scenario.startTotal + 500)
    }

    @Test func scenario09PedometerRestart() {
        var scenario = LiveStepScenario(walk: .constant(stepsPerMinute: 100, duration: 300), otherSourceSteps: 1_200)
        scenario.background = 150...150
        let result = scenario.run(until: 300)
        result.expectShown(at: 300, near: scenario.startTotal + 500)
    }

    // MARK: 11 Kein Sensor

    @Test func scenario11WithoutSensorTheDisplayFollowsHealthKit() {
        var scenario = LiveStepScenario(walk: .constant(stepsPerMinute: 100, duration: 300), healthKitLag: 60, healthKitBatch: 60)
        scenario.sensorAvailable = false
        let result = scenario.run(until: 300)
        // Nur HealthKit: verzögert, aber ehrlich – nie mehr als HealthKit bestätigt.
        result.expectShown(at: 300, exactly: result.confirmed(at: 300))
        #expect(result.shown(at: 300) < scenario.startTotal + 500)
    }

    // MARK: 13–14 Apple Watch, neue Quelle

    @Test func scenario13AppleWatchCountsTheSameWalk() {
        // Die Watch zählt denselben Gang und schreibt schneller nach HealthKit; HealthKit zählt jeden Schritt einmal.
        var scenario = LiveStepScenario(walk: .constant(stepsPerMinute: 100, duration: 300), otherSourceSteps: 2_500, healthKitLag: 45, healthKitBatch: 30)
        let result = scenario.run(until: 600)
        for checkpoint in Self.checkpoints {
            result.expectShown(at: checkpoint.second, near: scenario.startTotal + checkpoint.steps)
        }
        result.expectShown(at: 600, exactly: scenario.startTotal + 500)
    }

    @Test func scenario14NewSourceAddsSteps() {
        var scenario = LiveStepScenario(walk: .constant(stepsPerMinute: 100, duration: 300), otherSourceSteps: 400)
        scenario.extraHealthKitSteps = [(60, 1_000)]
        let result = scenario.run(until: 900)
        #expect(result.shown(at: 60) == scenario.startTotal + 1_000)
        result.expectShown(at: 120, near: scenario.startTotal + 1_000 + 100)
        result.expectShown(at: 900, exactly: scenario.startTotal + 1_000 + 500)
    }

    // MARK: 15 iPhone zählt mehr, als HealthKit bestätigt

    /// Health bevorzugt die Watch und verwirft einen Teil der iPhone-Schritte: HealthKit bestätigt nur 90 % des Gangs.
    /// Während des Gehens zählt die Anzeige jeden Sensorschritt, 20 Minuten nach dem letzten Schritt gilt HealthKit.
    @Test func scenario15UnconfirmedStepsExpireAfterTheWalk() {
        var scenario = LiveStepScenario(walk: .constant(stepsPerMinute: 100, duration: 300), otherSourceSteps: 500)
        scenario.healthKitShare = 0.9
        let end = 300 + LiveStepEstimator.confirmationWindow + 60
        let result = scenario.run(until: end)
        result.expectShown(at: 300, near: scenario.startTotal + 500)
        // Kurz vor Ablauf noch der vorläufige Stand …
        result.expectShown(at: 300 + LiveStepEstimator.confirmationWindow - 30, near: scenario.startTotal + 500)
        // … danach genau HealthKit: 450 der 500 Schritte bestätigt.
        result.expectShown(at: end, exactly: scenario.startTotal + 450)
        #expect(result.confirmed(at: end) == scenario.startTotal + 450)
    }

    // MARK: Simulierter Sensor

    @Test func walkingProfileCountsSteps() {
        let walk = WalkingProfile([.init(duration: 60, stepsPerMinute: 100), .init(duration: 30, stepsPerMinute: 0), .init(duration: 60, stepsPerMinute: 120)])
        #expect(walk.steps(after: 30) == 50)
        #expect(walk.steps(after: 60) == 100)
        #expect(walk.steps(after: 85) == 100)
        #expect(walk.steps(after: 120) == 160)
        #expect(walk.steps(after: 1_000) == 220)
        #expect(walk.duration == 150)
    }

    @Test func simulatedSensorDeliversRisingReadings() async {
        let origin = Date()
        // Zeitraffer 600×: 5 simulierte Minuten in etwa einer halben Sekunde.
        let simulated = SimulatedLiveSteps(
            profile: .constant(stepsPerMinute: 100, duration: 300),
            origin: origin,
            stepsBeforeOrigin: 1_000,
            interval: 2.5,
            timeScale: 600
        )
        #expect(simulated.status == .simulated)
        #expect(simulated.reading(at: origin).steps == 1_000)
        #expect(simulated.reading(at: origin.addingTimeInterval(0.05)).steps == 1_050)
        #expect(simulated.reading(at: origin.addingTimeInterval(0.5)).steps == 1_500)

        var readings: [Int] = []
        for await reading in simulated.readings(since: origin) {
            readings.append(reading.steps)
            if reading.steps >= 1_500 || readings.count > 400 { break }
        }
        #expect(readings.first.map { $0 >= 1_000 } == true)
        #expect(readings.last == 1_500)
        #expect(zip(readings, readings.dropFirst()).allSatisfy { $0 < $1 })
    }

    /// Neuer Tag während der Simulation: Messung ab Mitternacht zählt nur Schritte ab dann (Stabilitäts-Review).
    @Test func simulatedSensorCountsFromALaterStart() async {
        // Simulation lief seit 1 s (Zeitraffer 600× = 10 Minuten, 1.000 Schritte), Messung ab der Hälfte.
        let origin = Date().addingTimeInterval(-1)
        let simulated = SimulatedLiveSteps(
            profile: .constant(stepsPerMinute: 100, duration: 3_600),
            origin: origin,
            stepsBeforeOrigin: 1_000,
            interval: 2.5,
            timeScale: 600
        )
        var first: Int?
        for await reading in simulated.readings(since: origin.addingTimeInterval(0.5)) {
            first = reading.steps
            break
        }
        // ≈ 500 Schritte seit dem Messbeginn – weder die 1.000 vor der Simulation noch die erste Hälfte.
        #expect(first.map { (450...900).contains($0) } == true)
    }

    @Test func endlessSimulatorOnlyForPlausibleRates() {
        #expect(SimulatedLiveSteps.endless(stepsPerMinute: 0) == nil)
        #expect(SimulatedLiveSteps.endless(stepsPerMinute: 1_000) == nil)
        #expect(SimulatedLiveSteps.endless(stepsPerMinute: 100)?.status == .simulated)
    }
}

/// Spielt einen Gang in simulierter Zeit durch (Auflösung 0,5 s).
struct LiveStepScenario {
    var walk: WalkingProfile
    /// Schritte, die das iPhone heute vor dem Gang gezählt hat.
    var stepsBeforeWalk = 3_000
    /// Schritte anderer Quellen in HealthKit (z. B. Apple Watch ohne iPhone), die der iPhone-Sensor nie sieht.
    var otherSourceSteps = 0
    /// HealthKit kennt die Schritte des Gangs erst `healthKitLag` Sekunden später …
    var healthKitLag: TimeInterval = 180
    /// … und in Abschnitten dieser Länge.
    var healthKitBatch: TimeInterval = 120
    var sensorInterval: TimeInterval = 2.5
    var pollInterval: TimeInterval = 15
    var sensorAvailable = true
    /// Zeitraum, in dem Pace im Hintergrund ist (kein Sensor, keine Abfrage).
    var background: ClosedRange<TimeInterval>?
    /// Zusätzliche HealthKit-Schritte ab einem Zeitpunkt (andere Geräte, neue Quelle).
    var extraHealthKitSteps: [(second: TimeInterval, steps: Int)] = []
    /// Anteil der Gang-Schritte, den HealthKit bestätigt (unter 1: Health bevorzugt eine andere Quelle).
    var healthKitShare = 1.0
    /// Zeitpunkt 0 der Simulation (für Sensor-Zeitstempel und den Verfall unbestätigter Schritte).
    let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private let day = Fixtures.day(2026, 10, 23)

    init(
        walk: WalkingProfile,
        otherSourceSteps: Int = 0,
        healthKitLag: TimeInterval = 180,
        healthKitBatch: TimeInterval = 120
    ) {
        self.walk = walk
        self.otherSourceSteps = otherSourceSteps
        self.healthKitLag = healthKitLag
        self.healthKitBatch = healthKitBatch
    }

    /// Tagessumme laut HealthKit zu Beginn des Gangs.
    var startTotal: Int { stepsBeforeWalk + otherSourceSteps }

    func healthKit(at second: TimeInterval) -> Int {
        let known = second - healthKitLag
        let covered = known <= 0 ? 0 : (known / healthKitBatch).rounded(.down) * healthKitBatch
        let extra = extraHealthKitSteps.filter { $0.second <= second }.reduce(0) { $0 + $1.steps }
        return startTotal + Int((Double(walk.steps(after: covered)) * healthKitShare).rounded()) + extra
    }

    func sensor(at second: TimeInterval) -> Int {
        stepsBeforeWalk + walk.steps(after: second)
    }

    struct Result {
        var shown: [Int: Int] = [:]
        var confirmedValues: [Int: Int] = [:]

        private static func key(_ second: TimeInterval) -> Int { Int((second * 2).rounded()) }

        func shown(at second: TimeInterval) -> Int { shown[Self.key(second)] ?? -1 }
        func confirmed(at second: TimeInterval) -> Int { confirmedValues[Self.key(second)] ?? -1 }

        func expectShown(at second: TimeInterval, near expected: Int, tolerance: Int = 5, sourceLocation: SourceLocation = #_sourceLocation) {
            let value = shown(at: second)
            #expect(abs(value - expected) <= tolerance, "nach \(Int(second)) s: \(value) statt ≈ \(expected)", sourceLocation: sourceLocation)
        }

        func expectShown(at second: TimeInterval, exactly expected: Int, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(shown(at: second) == expected, "nach \(Int(second)) s", sourceLocation: sourceLocation)
        }

        mutating func record(_ second: TimeInterval, _ estimator: LiveStepEstimator) {
            shown[Self.key(second)] = estimator.steps
            confirmedValues[Self.key(second)] = estimator.confirmedSteps ?? 0
        }
    }

    mutating func run(until end: TimeInterval) -> Result {
        var estimator = LiveStepEstimator()
        var result = Result()
        var wasInBackground = false
        var previous = 0
        for tick in 0...Int(end * 2) {
            let second = Double(tick) / 2
            let inBackground = background?.contains(second) ?? false
            if inBackground {
                if !wasInBackground { estimator.sensorStopped() }
            } else {
                if sensorAvailable, second.truncatingRemainder(dividingBy: sensorInterval) == 0 {
                    estimator.sensor(sensor(at: second), on: day, at: origin.addingTimeInterval(second))
                }
                // Wie die App: Bei jeder Abfrage HealthKit übernehmen und unbestätigte Schritte ggf. verfallen lassen.
                if second.truncatingRemainder(dividingBy: pollInterval) == 0 || wasInBackground {
                    estimator.healthKit(healthKit(at: second), on: day)
                    estimator.settle(at: origin.addingTimeInterval(second))
                }
            }
            wasInBackground = inBackground
            // Zurück nur beim Verfall unbestätigter Schritte – dann genau auf HealthKit und nach dem Zeitfenster.
            if estimator.steps < previous {
                #expect(estimator.steps == estimator.confirmedSteps, "Rückgang nach \(second) s")
                let quiet = estimator.lastSensorProgress.map { origin.addingTimeInterval(second).timeIntervalSince($0) } ?? .infinity
                #expect(quiet >= LiveStepEstimator.confirmationWindow, "Rückgang nach \(second) s vor Ablauf")
            }
            previous = estimator.steps
            result.record(second, estimator)
        }
        return result
    }
}

@MainActor
struct LiveStepDiagnosticsTests {
    @Test func theLogIsBounded() {
        let diagnostics = LiveStepDiagnostics()
        let start = Date(timeIntervalSince1970: 1_000_000)
        var estimator = LiveStepEstimator()
        let day = Fixtures.day(2026, 10, 23)
        diagnostics.record(.started, at: start, status: .available, estimator: estimator)
        for index in 1...500 {
            estimator.sensor(index * 4, on: day)
            diagnostics.record(.sensor, value: index * 4, at: start.addingTimeInterval(Double(index) * 2.5), status: .available, estimator: estimator)
        }
        #expect(diagnostics.events.count == LiveStepDiagnostics.capacity)
        #expect(diagnostics.events.first?.value == 2_000)
        #expect(diagnostics.readingCount == 500)
        #expect(diagnostics.isMeasuring)
        #expect(diagnostics.averageReadingInterval == 2.5)
        diagnostics.reset()
        #expect(diagnostics.events.isEmpty)
        #expect(diagnostics.averageReadingInterval == nil)
    }
}
