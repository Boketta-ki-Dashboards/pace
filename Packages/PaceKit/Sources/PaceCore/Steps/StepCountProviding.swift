import Foundation

/// Liest Schrittdaten aus einer Gesundheitsdatenquelle (in der App: HealthKit).
public protocol StepCountProviding: Sendable {
    /// Summe der Schritte im Intervall, dedupliziert über alle Quellen (iPhone, Apple Watch, …).
    /// - Returns: `nil`, wenn im Intervall keine lesbaren Samples existieren.
    func stepCount(in interval: DateInterval) async throws -> Int?

    /// Ob überhaupt irgendein Schritt-Sample lesbar ist – unabhängig vom Zeitraum.
    func hasAnyStepSamples() async throws -> Bool

    /// Meldet, dass sich Schrittdaten geändert haben. Der Stream endet, wenn der konsumierende Task beendet wird.
    func stepCountChanges() -> AsyncStream<Void>
}
