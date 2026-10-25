import CoreMotion
import Foundation
import PaceCore

/// Live-Schritte über `CMPedometer` – nur, solange jemand den Stream liest (Pace im Vordergrund). Der Sensor meldet
/// neue Werte ereignisbasiert (beim Gehen etwa alle paar Sekunden); es gibt keinen eigenen Timer und kein GPS.
///
/// Ablauf einer Messung
/// - Start ab Tagesbeginn: Der Bewegungscoprozessor speichert die Schritte der letzten Tage, daher enthält schon der
///   erste Wert alle Schritte, die das iPhone heute gezählt hat. Damit der Wert sofort da ist (und nicht erst beim
///   nächsten Schritt), wird er zusätzlich einmal abgefragt.
/// - Abfrage und laufende Meldungen kommen auf verschiedenen Threads an; gemeldet wird nur, was größer ist als der
///   zuletzt gemeldete Wert. So kann ein spät eintreffendes Abfrageergebnis nie als „Neustart“ missverstanden werden.
///
/// Braucht `NSMotionUsageDescription` in der Info.plist. Beim ersten Start fragt iOS nach „Bewegung & Fitness“; bei
/// verweigertem Zugriff endet der Stream sofort und Pace zeigt weiter die HealthKit-Werte.
public final class PedometerLiveSteps: LiveStepCounting, @unchecked Sendable {
    public init() {}

    /// Live-Schritte für die App: der echte Sensor. Nur in Entwicklungs-Builds kann stattdessen Gehen simuliert werden
    /// (Startoption `-PaceSimulatedStepsPerMinute 100` im Xcode-Schema oder der Schalter in der Live-Schritt-Diagnose),
    /// z. B. im Simulator, der keinen Schrittzähler hat.
    public static func appSource(defaults: UserDefaults = .standard) -> any LiveStepCounting {
        #if DEBUG
        if let simulated = SimulatedLiveSteps.endless(stepsPerMinute: defaults.double(forKey: SimulatedLiveSteps.launchArgumentKey)) {
            return simulated
        }
        #endif
        return PedometerLiveSteps()
    }

    public var status: LiveStepSensorStatus {
        guard CMPedometer.isStepCountingAvailable() else { return .unsupported }
        switch CMPedometer.authorizationStatus() {
        case .authorized: return .available
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .available
        }
    }

    public func readings(since start: Date) -> AsyncStream<LiveStepReading> {
        let (stream, continuation) = AsyncStream<LiveStepReading>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard isAvailable else {
            continuation.finish()
            return stream
        }
        let box = PedometerBox()
        let deliver: @Sendable (CMPedometerData?, (any Error)?) -> Void = { data, error in
            if let error = error as NSError?, error.domain == CMErrorDomain,
               error.code == Int(CMErrorMotionActivityNotAuthorized.rawValue) {
                continuation.finish()
                return
            }
            guard error == nil, let data else { return }
            let reading = LiveStepReading(steps: data.numberOfSteps.intValue, date: data.endDate)
            if box.accept(reading) {
                continuation.yield(reading)
            }
        }
        box.pedometer.startUpdates(from: start, withHandler: deliver)
        box.pedometer.queryPedometerData(from: start, to: Date(), withHandler: deliver)
        continuation.onTermination = { _ in
            box.pedometer.stopUpdates()
        }
        return stream
    }
}

/// Hält den Schrittzähler für die Dauer eines Streams; `CMPedometer` ist für Start und Stopp von jedem Thread aus
/// gedacht. Merkt sich den zuletzt gemeldeten Wert (Meldungen kommen auf beliebigen Threads an).
private final class PedometerBox: @unchecked Sendable {
    let pedometer = CMPedometer()
    private let lock = NSLock()
    private var lastSteps: Int?

    /// `true`, wenn der Wert neu und größer ist als der zuletzt gemeldete.
    func accept(_ reading: LiveStepReading) -> Bool {
        lock.withLock {
            if let lastSteps, reading.steps <= lastSteps { return false }
            lastSteps = reading.steps
            return true
        }
    }
}
