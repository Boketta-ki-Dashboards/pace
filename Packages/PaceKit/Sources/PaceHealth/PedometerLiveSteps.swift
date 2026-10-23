import CoreMotion
import Foundation
import PaceCore

/// Live-Schritte über `CMPedometer` – nur, solange jemand den Stream liest (Pace im Vordergrund). Der Sensor meldet
/// neue Werte ereignisbasiert (beim Gehen etwa alle paar Sekunden); es gibt keinen eigenen Timer.
///
/// Braucht `NSMotionUsageDescription` in der Info.plist. Beim ersten Start fragt iOS nach „Bewegung & Fitness“; bei
/// verweigertem Zugriff endet der Stream sofort und Pace zeigt weiter die HealthKit-Werte.
public final class PedometerLiveSteps: LiveStepCounting, @unchecked Sendable {
    public init() {}

    public var isAvailable: Bool {
        guard CMPedometer.isStepCountingAvailable() else { return false }
        switch CMPedometer.authorizationStatus() {
        case .denied, .restricted: return false
        default: return true
        }
    }

    public func steps(since start: Date) -> AsyncStream<Int> {
        let (stream, continuation) = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard isAvailable else {
            continuation.finish()
            return stream
        }
        let box = PedometerBox()
        box.pedometer.startUpdates(from: start) { data, error in
            if let error = error as NSError?, error.domain == CMErrorDomain,
               error.code == Int(CMErrorMotionActivityNotAuthorized.rawValue) {
                continuation.finish()
                return
            }
            guard error == nil, let data else { return }
            continuation.yield(data.numberOfSteps.intValue)
        }
        continuation.onTermination = { _ in
            box.pedometer.stopUpdates()
        }
        return stream
    }
}

/// Hält den Schrittzähler für die Dauer eines Streams; `CMPedometer` ist für Start und Stopp von jedem Thread aus
/// gedacht.
private final class PedometerBox: @unchecked Sendable {
    let pedometer = CMPedometer()
}
