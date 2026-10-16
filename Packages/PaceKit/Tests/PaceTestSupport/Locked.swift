import Foundation

/// Threadsicherer Container für veränderlichen Test-Zustand.
///
/// `@unchecked Sendable`: `value` wird ausschließlich innerhalb von `withLock` gelesen und geschrieben.
public final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }

    public var current: Value {
        withLock { $0 }
    }
}
