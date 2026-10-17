import Auth
import Foundation

/// Speichert die Sitzung nur im Arbeitsspeicher – für Tests und Integrationstests. Die App verwendet die Keychain
/// (`SupabaseBackend.init(configuration:)`).
///
/// `@unchecked Sendable`: `AuthLocalStorage` verlangt synchrone, threadsichere Methoden, und `Mutex` gibt es erst ab
/// iOS 18. `values` wird ausschließlich unter `lock` gelesen und geschrieben.
public final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    public init() {}

    public func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    public func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = nil
    }
}
