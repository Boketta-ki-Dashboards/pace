import Foundation
import PaceCore

/// Bewegungssensor zum Steuern im Test: `send(_:)` liefert einen neuen Zählerstand, `finish()` beendet die Messung.
public final class LiveStepsStub: LiveStepCounting, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Int>.Continuation?
    private var pending: [Int] = []
    public let isAvailable: Bool
    /// Beginn der zuletzt gestarteten Messung.
    public private(set) var lastStart: Date?

    public init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
    }

    public func steps(since start: Date) -> AsyncStream<Int> {
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        lock.withLock {
            lastStart = start
            self.continuation = continuation
            pending.forEach { continuation.yield($0) }
            pending = []
        }
        return stream
    }

    public func send(_ steps: Int) {
        lock.withLock {
            if let continuation {
                continuation.yield(steps)
            } else {
                pending.append(steps)
            }
        }
    }

    public func finish() {
        lock.withLock { continuation?.finish() }
    }
}
