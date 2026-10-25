import Foundation

/// Gehen in Abschnitten mit gleichmäßigem Tempo – für Tests des Live-Abgleichs und den Simulator in
/// Entwicklungs-Builds. Ersetzt keinen Test mit echtem Sensor.
public struct WalkingProfile: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        /// Dauer in Sekunden.
        public var duration: TimeInterval
        /// Tempo; `0` ist eine Pause.
        public var stepsPerMinute: Double

        public init(duration: TimeInterval, stepsPerMinute: Double) {
            self.duration = max(0, duration)
            self.stepsPerMinute = max(0, stepsPerMinute)
        }
    }

    public var segments: [Segment]

    public init(_ segments: [Segment]) {
        self.segments = segments
    }

    /// Gleichmäßiges Tempo, z. B. 100 Schritte pro Minute für 5 Minuten.
    public static func constant(stepsPerMinute: Double, duration: TimeInterval) -> WalkingProfile {
        WalkingProfile([Segment(duration: duration, stepsPerMinute: stepsPerMinute)])
    }

    /// Gesamtdauer in Sekunden.
    public var duration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }

    /// Gezählte Schritte nach `elapsed` Sekunden (abgerundet). Nach dem letzten Abschnitt bleibt der Wert stehen.
    public func steps(after elapsed: TimeInterval) -> Int {
        var remaining = max(0, elapsed)
        var total = 0.0
        for segment in segments {
            let part = min(remaining, segment.duration)
            total += part * segment.stepsPerMinute / 60
            remaining -= part
            if remaining <= 0 { break }
        }
        return Int((total + 1e-9).rounded(.down))
    }
}

/// Simulierter Bewegungssensor: liefert in festen Abständen die Schritte eines ``WalkingProfile`` – wie
/// `CMPedometer`, nur ohne Gerät. Für Tests (mit Zeitraffer) und den Simulator in Entwicklungs-Builds.
public struct SimulatedLiveSteps: LiveStepCounting {
    /// Schlüssel für die Startoption in Entwicklungs-Builds: `-PaceSimulatedStepsPerMinute 100`.
    public static let launchArgumentKey = "PaceSimulatedStepsPerMinute"

    public let profile: WalkingProfile
    /// Beginn des simulierten Gehens.
    public let origin: Date
    /// Schritte, die der Sensor heute schon vor `origin` gezählt hat.
    public let stepsBeforeOrigin: Int
    /// Abstand zwischen zwei Messwerten in simulierter Zeit (echter Sensor beim Gehen: etwa alle 2–3 Sekunden).
    public let interval: TimeInterval
    /// Zeitraffer: simulierte Sekunden pro echter Sekunde (Tests: z. B. 600).
    public let timeScale: Double
    private let now: @Sendable () -> Date

    public init(
        profile: WalkingProfile,
        origin: Date = Date(),
        stepsBeforeOrigin: Int = 0,
        interval: TimeInterval = 2.5,
        timeScale: Double = 1,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.profile = profile
        self.origin = origin
        self.stepsBeforeOrigin = max(0, stepsBeforeOrigin)
        self.interval = max(0.1, interval)
        self.timeScale = max(1, timeScale)
        self.now = now
    }

    /// Simulator mit gleichmäßigem Tempo ohne Ende (nur Entwicklung), z. B. aus der Startoption.
    public static func endless(stepsPerMinute: Double, origin: Date = Date()) -> SimulatedLiveSteps? {
        guard stepsPerMinute > 0, stepsPerMinute <= 300 else { return nil }
        return SimulatedLiveSteps(profile: .constant(stepsPerMinute: stepsPerMinute, duration: 24 * 60 * 60), origin: origin)
    }

    public var status: LiveStepSensorStatus { .simulated }

    /// Simulierte Sekunden seit `origin` (auf Millisekunden gerundet, damit Rundungsfehler der Uhrzeit keine Schritte
    /// kosten).
    func elapsed(at date: Date) -> TimeInterval {
        (max(0, date.timeIntervalSince(origin)) * timeScale * 1_000).rounded() / 1_000
    }

    /// Messwert zu einem echten Zeitpunkt.
    public func reading(at date: Date) -> LiveStepReading {
        let elapsed = elapsed(at: date)
        return LiveStepReading(
            steps: stepsBeforeOrigin + profile.steps(after: elapsed),
            date: origin.addingTimeInterval(elapsed)
        )
    }

    public func readings(since start: Date) -> AsyncStream<LiveStepReading> {
        let (stream, continuation) = AsyncStream<LiveStepReading>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let task = Task { [self] in
            var last: Int?
            while !Task.isCancelled {
                let reading = reading(at: now())
                // Wie der echte Sensor: nur neue Werte melden.
                if reading.steps != last {
                    continuation.yield(reading)
                    last = reading.steps
                }
                try? await Task.sleep(nanoseconds: UInt64(interval / timeScale * 1_000_000_000))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}
