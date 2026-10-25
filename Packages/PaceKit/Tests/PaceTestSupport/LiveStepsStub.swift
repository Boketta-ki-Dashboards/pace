import Foundation
import PaceCore

/// Bewegungssensor zum Steuern im Test: `send(_:)` liefert einen neuen Zählerstand, `finish()` beendet die Messung.
public final class LiveStepsStub: LiveStepCounting, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<LiveStepReading>.Continuation?
    private var pending: [LiveStepReading] = []
    private var starts: [Date] = []
    private let defaultDate: @Sendable () -> Date
    public let status: LiveStepSensorStatus

    /// Beginn der zuletzt gestarteten Messung.
    public var lastStart: Date? { lock.withLock { starts.last } }
    /// Beginn aller gestarteten Messungen.
    public var allStarts: [Date] { lock.withLock { starts } }

    public init(status: LiveStepSensorStatus = .available, now: @escaping @Sendable () -> Date = { Date() }) {
        self.status = status
        defaultDate = now
    }

    public convenience init(isAvailable: Bool) {
        self.init(status: isAvailable ? .available : .denied)
    }

    public func readings(since start: Date) -> AsyncStream<LiveStepReading> {
        let (stream, continuation) = AsyncStream<LiveStepReading>.makeStream()
        lock.withLock {
            starts.append(start)
            self.continuation = continuation
            pending.forEach { continuation.yield($0) }
            pending = []
        }
        return stream
    }

    /// Neuer Zählerstand (Schritte seit Beginn der Messung), gemessen um `date` (Standard: `now`).
    public func send(_ steps: Int, at date: Date? = nil) {
        let reading = LiveStepReading(steps: steps, date: date ?? defaultDate())
        lock.withLock {
            if let continuation {
                continuation.yield(reading)
            } else {
                pending.append(reading)
            }
        }
    }

    public func finish() {
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
    }
}
