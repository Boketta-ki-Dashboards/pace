import Foundation
import Observation

/// Protokoll des Live-Abgleichs für die Diagnose in Entwicklungs-Builds: Sensorzustand, Messwerte, HealthKit-Stände,
/// Neustarts. Wird nie hochgeladen und nicht im Home-Design angezeigt; das Protokoll ist auf ``capacity`` Einträge
/// begrenzt.
@MainActor
@Observable
public final class LiveStepDiagnostics {
    public struct Event: Identifiable, Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable {
            /// Messung gestartet (Wert: keiner).
            case started
            /// Neuer Sensorwert (Wert: Schritte seit Tagesbeginn).
            case sensor
            /// Geänderter HealthKit-Stand (Wert: Wettbewerbsschritte).
            case healthKit
            /// Sensor meldete einen kleineren Zählerstand (Neustart).
            case sensorRestarted
            /// Neuer Tag: Messung beginnt neu.
            case dayChanged
            /// Messung beendet (Hintergrund, Zugriff entzogen, Abbruch).
            case stopped
            /// Sensor nicht verfügbar (Wert: keiner).
            case unavailable
        }

        public let id: Int
        public let date: Date
        public let kind: Kind
        public let value: Int?
        /// Angezeigte Schritte nach dem Ereignis.
        public let shown: Int
    }

    /// Höchstzahl gespeicherter Ereignisse (älteste fallen weg).
    public static let capacity = 80

    public private(set) var status: LiveStepSensorStatus = .unsupported
    public private(set) var isMeasuring = false
    public private(set) var measurementStart: Date?
    public private(set) var lastReading: LiveStepReading?
    public private(set) var readingCount = 0
    public private(set) var lastHealthKitChange: Date?
    public private(set) var estimator = LiveStepEstimator()
    /// Neueste zuerst.
    public private(set) var events: [Event] = []
    private var nextID = 0

    public init() {}

    /// Mittlerer Abstand der letzten Sensorwerte in Sekunden (`nil` bei weniger als zwei Werten).
    public var averageReadingInterval: TimeInterval? {
        let dates = events.filter { $0.kind == .sensor }.prefix(11).map(\.date)
        guard dates.count >= 2, let newest = dates.first, let oldest = dates.last else { return nil }
        return newest.timeIntervalSince(oldest) / Double(dates.count - 1)
    }

    public func record(
        _ kind: Event.Kind,
        value: Int? = nil,
        at date: Date,
        status: LiveStepSensorStatus,
        estimator: LiveStepEstimator,
        start: Date? = nil
    ) {
        self.status = status
        self.estimator = estimator
        switch kind {
        case .started:
            isMeasuring = true
            measurementStart = start ?? date
        case .stopped, .unavailable:
            isMeasuring = false
        case .sensor:
            readingCount += 1
            lastReading = value.map { LiveStepReading(steps: $0, date: date) }
        case .healthKit:
            lastHealthKitChange = date
        case .sensorRestarted, .dayChanged:
            break
        }
        events.insert(Event(id: nextID, date: date, kind: kind, value: value, shown: estimator.steps), at: 0)
        nextID += 1
        if events.count > Self.capacity {
            events.removeLast(events.count - Self.capacity)
        }
    }

    /// Protokoll leeren (z. B. vor einem Testgang).
    public func reset() {
        events = []
        readingCount = 0
        lastReading = nil
    }
}
