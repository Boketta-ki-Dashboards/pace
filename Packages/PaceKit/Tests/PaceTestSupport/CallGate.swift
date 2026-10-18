import Foundation

/// Hält ausgewählte Aufrufe eines Test-Doubles an, bis der Test sie freigibt – damit lassen sich überholende
/// Antworten (eine ältere Anfrage kommt nach einer neueren zurück) gezielt nachstellen.
public final class CallGate: Sendable {
    private struct State {
        var closed: Set<String> = []
        var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
    }

    private let state = Locked(State())

    public init() {}

    /// Aufrufe mit diesem Namen warten ab jetzt, bis `open(_:)` sie freigibt.
    public func close(_ name: String) {
        state.withLock { _ = $0.closed.insert(name) }
    }

    /// Gibt wartende Aufrufe frei; spätere laufen direkt durch.
    public func open(_ name: String) {
        let continuations = state.withLock { state in
            state.closed.remove(name)
            return state.waiting.removeValue(forKey: name) ?? []
        }
        continuations.forEach { $0.resume() }
    }

    /// Anzahl der Aufrufe, die gerade warten.
    public func waitingCount(_ name: String) -> Int {
        state.withLock { $0.waiting[name]?.count ?? 0 }
    }

    func pass(_ name: String) async {
        await withCheckedContinuation { continuation in
            let passes = state.withLock { state in
                guard state.closed.contains(name) else { return true }
                state.waiting[name, default: []].append(continuation)
                return false
            }
            if passes { continuation.resume() }
        }
    }
}
