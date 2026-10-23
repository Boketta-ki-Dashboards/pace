import Foundation

/// Schnelle Schritt-Messwerte des Bewegungssensors (Core Motion), solange Pace im Vordergrund ist.
///
/// Nur für die Anzeige: Gespeicherte Gesundheitsdaten, Wettbewerbsschritte, Rankings und Sync kommen weiterhin
/// ausschließlich aus HealthKit (ohne manuell eingetragene Schritte).
public protocol LiveStepCounting: Sendable {
    /// Ob das Gerät Schritte live zählen kann (und der Zugriff nicht verweigert ist).
    var isAvailable: Bool { get }

    /// Schritte seit `start` laut Bewegungssensor (aufsteigend), sobald neue Sensordaten vorliegen. Endet bei
    /// verweigertem Zugriff oder Abbruch der Aufgabe (dann stoppt auch der Sensor).
    func steps(since start: Date) -> AsyncStream<Int>
}

/// Kein Live-Zählen (Tests, Geräte ohne Bewegungssensor).
public struct NoLiveStepCounting: LiveStepCounting {
    public init() {}
    public var isAvailable: Bool { false }
    public func steps(since start: Date) -> AsyncStream<Int> { AsyncStream { $0.finish() } }
}

/// Verbindet die maßgeblichen HealthKit-Wettbewerbsschritte mit den schnelleren Sensorwerten, ohne doppelt zu zählen.
///
/// Abgleich
/// - Bei jedem neuen HealthKit-Wert wird die Basis neu gesetzt: `Basis = HealthKit`, `Sensor-Basis = aktueller
///   Sensorwert`. Angezeigt wird `Basis + (Sensor − Sensor-Basis)` – also nur Schritte, die der Sensor **nach** dem
///   letzten HealthKit-Stand gezählt hat. Sensor- und HealthKit-Werte werden nie einfach addiert.
/// - Die Anzeige fällt innerhalb eines Tages nicht zurück (HealthKit trägt Schritte oft erst verzögert nach).
/// - Neuer Tag: alles beginnt neu beim HealthKit-Wert.
/// - Ohne Sensorwerte (kein Zugriff, App im Hintergrund) gilt der HealthKit-Wert.
public struct LiveStepEstimator: Equatable, Sendable {
    public private(set) var day: LocalDate?
    private var healthKitSteps = 0
    private var sensorBaseline: Int?
    private var latestSensor: Int?
    private var lastShown = 0

    public init() {}

    /// Angezeigte Schritte für heute.
    public var steps: Int {
        guard day != nil else { return 0 }
        return max(lastShown, healthKitSteps + sensorDelta)
    }

    private var sensorDelta: Int {
        guard let sensorBaseline, let latestSensor else { return 0 }
        return max(0, latestSensor - sensorBaseline)
    }

    /// Neuer Stand aus HealthKit (Wettbewerbsschritte des Tages).
    public mutating func healthKit(_ steps: Int, on day: LocalDate) {
        if self.day != day {
            self = LiveStepEstimator()
            self.day = day
        }
        lastShown = self.steps
        healthKitSteps = steps
        sensorBaseline = latestSensor
    }

    /// Neuer Sensorwert (Schritte seit Tagesbeginn bzw. seit Beginn der Messung).
    public mutating func sensor(_ steps: Int, on day: LocalDate) {
        guard self.day == day else { return }
        if let latestSensor, steps < latestSensor {
            // Sensor neu gestartet (z. B. nach Rückkehr in den Vordergrund): neue Basis, nichts doppelt zählen.
            lastShown = self.steps
            healthKitSteps = self.steps
            sensorBaseline = steps
        } else if sensorBaseline == nil {
            sensorBaseline = steps
        }
        latestSensor = steps
    }

    /// Sensor beendet (Hintergrund, Zugriff entzogen): Der bisher angezeigte Stand bleibt, bis HealthKit nachzieht.
    public mutating func sensorStopped() {
        lastShown = steps
        healthKitSteps = max(healthKitSteps, lastShown)
        sensorBaseline = nil
        latestSensor = nil
    }
}
