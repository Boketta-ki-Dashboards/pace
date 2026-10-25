import Foundation

/// Ein Messwert des Bewegungssensors.
public struct LiveStepReading: Equatable, Sendable {
    /// Schritte seit Beginn der Messung laut Sensor (innerhalb einer Messung aufsteigend).
    public var steps: Int
    /// Ende des gemessenen Zeitraums.
    public var date: Date

    public init(steps: Int, date: Date) {
        self.steps = steps
        self.date = date
    }
}

/// Zustand des Bewegungssensors (Core Motion, „Bewegung & Fitness“).
public enum LiveStepSensorStatus: String, Equatable, Sendable {
    /// Zugriff erlaubt, das Gerät zählt Schritte.
    case available
    /// Noch nicht gefragt – iOS fragt beim ersten Start der Messung.
    case notDetermined
    /// Zugriff in den iOS-Einstellungen verweigert.
    case denied
    /// Zugriff eingeschränkt (z. B. Bildschirmzeit, Geräteverwaltung).
    case restricted
    /// Kein Schrittzähler (z. B. Simulator, iPad ohne Bewegungscoprozessor).
    case unsupported
    /// Simulierte Schritte – nur in Entwicklungs-Builds.
    case simulated

    /// Ob eine Messung gestartet werden kann.
    public var canCount: Bool {
        switch self {
        case .available, .notDetermined, .simulated: true
        case .denied, .restricted, .unsupported: false
        }
    }
}

/// Schnelle Schritt-Messwerte des Bewegungssensors (Core Motion), solange Pace im Vordergrund ist.
///
/// Nur für die Anzeige: Gespeicherte Gesundheitsdaten, Wettbewerbsschritte, Rankings und Sync kommen weiterhin
/// ausschließlich aus HealthKit (ohne manuell eingetragene Schritte).
public protocol LiveStepCounting: Sendable {
    /// Zustand des Sensors (Gerät, Zugriff).
    var status: LiveStepSensorStatus { get }

    /// Messwerte seit `start` (Schritte seit `start`, innerhalb der Messung aufsteigend), sobald neue Sensordaten
    /// vorliegen. Liegt `start` in der Vergangenheit, enthält der erste Wert die bis dahin gezählten Schritte. Endet bei
    /// verweigertem Zugriff oder Abbruch der Aufgabe (dann stoppt auch der Sensor).
    func readings(since start: Date) -> AsyncStream<LiveStepReading>
}

public extension LiveStepCounting {
    /// Ob das Gerät Schritte live zählen kann (und der Zugriff nicht verweigert ist).
    var isAvailable: Bool { status.canCount }
}

/// Kein Live-Zählen (Tests, Geräte ohne Bewegungssensor).
public struct NoLiveStepCounting: LiveStepCounting {
    public init() {}
    public var status: LiveStepSensorStatus { .unsupported }
    public func readings(since start: Date) -> AsyncStream<LiveStepReading> { AsyncStream { $0.finish() } }
}

/// Verbindet die maßgeblichen HealthKit-Wettbewerbsschritte mit den schnelleren Sensorwerten, ohne doppelt zu zählen.
///
/// Abgleich
/// - Der Sensor misst ab Tagesbeginn; sein Wert ist die Tagessumme des iPhones. Angezeigt wird das Größte aus
///   HealthKit-Stand, Sensor-Tagessumme und `Basis + Sensor-Fortschritt seit der Basis`. Sensor- und HealthKit-Werte
///   werden nie einfach addiert.
/// - Eine neue Basis entsteht nur, wenn sich der HealthKit-Wert **ändert** (nicht bei jeder Abfrage): `Basis =
///   max(angezeigt, HealthKit)`, `Sensor-Basis = aktueller Sensorwert`. HealthKit trägt Schritte oft Minuten später
///   nach; der Sensor-Fortschritt geht dabei nicht verloren, und Schritte, die HealthKit inzwischen kennt, zählen
///   nicht doppelt. Zählt eine andere Quelle (z. B. die Apple Watch) mehr, gilt der höhere HealthKit-Wert.
/// - Die Anzeige fällt innerhalb eines Tages nie zurück.
/// - Messung gestoppt und neu gestartet (Hintergrund): Zählt der Sensor weiter ab Tagesbeginn, kommen die Schritte aus
///   der Pause dazu, solange HealthKit sich in der Zwischenzeit nicht geändert hat.
/// - Neuer Tag: alles beginnt neu. Werte eines früheren Tages werden ignoriert.
/// - Ohne Sensorwerte (kein Zugriff, App im Hintergrund) gilt der HealthKit-Wert bzw. der zuletzt angezeigte Stand.
public struct LiveStepEstimator: Equatable, Sendable {
    public private(set) var day: LocalDate?
    /// Letzter HealthKit-Stand des Tages (Wettbewerbsschritte); `nil`, solange keiner vorliegt.
    public private(set) var confirmedSteps: Int?
    /// Letzter Sensorwert der laufenden Messung (Schritte seit Tagesbeginn).
    public private(set) var latestSensor: Int?
    /// Angezeigter Stand bei der letzten Basis.
    private var base = 0
    /// Sensorwert bei der letzten Basis.
    private var sensorBaseline: Int?
    /// Letzter Sensorwert vor dem Stopp der Messung. Zählt der Sensor nach dem Neustart vom selben Tagesbeginn weiter,
    /// kommen die Schritte aus der Pause dazu – außer HealthKit hat sich inzwischen geändert (dann könnte es sie schon
    /// enthalten).
    private var sensorAtStop: Int?

    public init() {}

    /// Angezeigte Schritte für heute.
    public var steps: Int {
        guard day != nil else { return 0 }
        return max(base + sensorDelta, latestSensor ?? 0, confirmedSteps ?? 0)
    }

    /// Schritte, die der Sensor seit der letzten Basis gezählt hat.
    public var sensorDelta: Int {
        guard let sensorBaseline, let latestSensor else { return 0 }
        return max(0, latestSensor - sensorBaseline)
    }

    /// Angezeigte Schritte, die HealthKit (noch) nicht bestätigt hat – vorläufig, zählen nicht für Rankings.
    public var unconfirmedSteps: Int {
        max(0, steps - (confirmedSteps ?? 0))
    }

    /// Neuer Stand aus HealthKit (Wettbewerbsschritte des Tages). Ein unveränderter Wert ändert nichts.
    public mutating func healthKit(_ steps: Int, on day: LocalDate) {
        guard begin(day), steps != confirmedSteps else { return }
        rebase()
        sensorAtStop = nil
        confirmedSteps = steps
        base = max(base, steps)
    }

    /// Neuer Sensorwert (Schritte seit Tagesbeginn laut Sensor).
    public mutating func sensor(_ steps: Int, on day: LocalDate) {
        guard begin(day) else { return }
        if let latestSensor, steps < latestSensor {
            // Sensor neu gestartet (kleinerer Zählerstand): neue Basis, nichts doppelt zählen, nichts verlieren.
            rebase()
            sensorBaseline = steps
        } else if sensorBaseline == nil {
            if let sensorAtStop, latestSensor == nil, steps >= sensorAtStop {
                sensorBaseline = sensorAtStop
            } else {
                sensorBaseline = steps
            }
        }
        sensorAtStop = nil
        latestSensor = steps
    }

    /// Sensor beendet (Hintergrund, Zugriff entzogen): Der bisher angezeigte Stand bleibt, bis HealthKit nachzieht.
    public mutating func sensorStopped() {
        base = steps
        sensorAtStop = latestSensor ?? sensorAtStop
        sensorBaseline = nil
        latestSensor = nil
    }

    private mutating func rebase() {
        base = steps
        sensorBaseline = latestSensor
    }

    /// Stellt auf `day` um. `false` für Werte eines früheren Tages (verspätete Abfrage nach Mitternacht).
    private mutating func begin(_ day: LocalDate) -> Bool {
        if let current = self.day {
            if day < current { return false }
            if day == current { return true }
        }
        self = LiveStepEstimator()
        self.day = day
        return true
    }
}
