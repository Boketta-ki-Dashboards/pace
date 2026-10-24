import Foundation
import Observation

/// Körperdaten für die Kalorienschätzung. Private Gesundheitsdaten: Sie bleiben auf dem Gerät und werden nie an den
/// Server, an Freunde, Gruppen, Rankings oder Chats gegeben.
public struct BodyMetrics: Codable, Equatable, Sendable {
    /// Körpergröße in Zentimetern.
    public var heightCentimeters: Double?
    /// Körpergewicht in Kilogramm.
    public var weightKilograms: Double?
    /// Geschätzte aktive Kalorien anzeigen, wenn Apple Health keine gemessenen liefert.
    public var isEstimationEnabled: Bool

    public init(heightCentimeters: Double? = nil, weightKilograms: Double? = nil, isEstimationEnabled: Bool = false) {
        self.heightCentimeters = heightCentimeters
        self.weightKilograms = weightKilograms
        self.isEstimationEnabled = isEstimationEnabled
    }

    /// Gültige Körpergröße (Zentimeter).
    public static let heightRange: ClosedRange<Double> = 100...250
    /// Gültiges Körpergewicht (Kilogramm).
    public static let weightRange: ClosedRange<Double> = 30...300

    /// Eingeschaltet und mit gültigen Werten – nur dann wird geschätzt.
    public var canEstimate: Bool {
        guard isEstimationEnabled, let heightCentimeters, let weightKilograms else { return false }
        return Self.heightRange.contains(heightCentimeters) && Self.weightRange.contains(weightKilograms)
    }
}

/// Aktive Kalorien eines Tages oder Zeitraums – immer eindeutig gemessen, geschätzt oder nicht verfügbar.
public enum ActiveEnergy: Equatable, Sendable {
    /// Von Apple Health gemessen (z. B. Apple Watch).
    case measured(Double)
    /// Von Pace geschätzt (ganz oder an einzelnen Tagen des Zeitraums).
    case estimated(Double)
    case unavailable

    public var kilocalories: Double? {
        switch self {
        case .measured(let value), .estimated(let value): value
        case .unavailable: nil
        }
    }

    public var isEstimated: Bool {
        if case .estimated = self { return true }
        return false
    }
}

/// Schätzung der aktiven Kalorien beim Gehen ohne gemessene Werte.
///
/// Modell: ACSM-Gleichung für Gehen auf ebener Strecke. Der Sauerstoffbedarf über Ruhe beträgt 0,1 ml je Kilogramm und
/// Meter (unabhängig vom Tempo im üblichen Gehbereich); 1 Liter Sauerstoff entspricht etwa 5 kcal. Daraus folgt
/// 0,0005 kcal je Kilogramm Körpergewicht und Meter – rund 0,5 kcal je kg und km (Netto, ohne Grundumsatz). Die Strecke
/// kommt von Apple Health, sonst aus den automatisch erfassten Schritten mal geschätzter Schrittlänge (0,414 ×
/// Körpergröße). Kein fester Wert pro Schritt: Gewicht und Größe gehen ein.
///
/// Grenzen: Steigungen, Treppen und Laufen werden nicht eigens berücksichtigt (Laufen kostet etwa doppelt so viel);
/// deshalb heißt der Wert ausdrücklich „geschätzt“.
public enum CalorieEstimator {
    /// Netto-Energiebedarf des Gehens: kcal je Kilogramm und Meter.
    public static let kilocaloriesPerKilogramMeter = 0.0005
    /// Schrittlänge als Anteil der Körpergröße (Mittel aus Studien für Frauen und Männer).
    public static let strideFactor = 0.414

    /// Geschätzte Schrittlänge in Metern.
    public static func strideLengthMeters(heightCentimeters: Double) -> Double {
        heightCentimeters / 100 * strideFactor
    }

    /// Geschätzte aktive Kalorien für einen Tag; `nil`, wenn nicht geschätzt werden kann (aus, Körperdaten fehlen, keine
    /// Bewegung erfasst).
    /// - Parameters:
    ///   - automaticSteps: Automatisch erfasste Schritte (ohne manuelle Einträge).
    ///   - measuredDistanceMeters: Strecke laut Apple Health, falls verlässlich (sonst aus den Schritten).
    public static func kilocalories(automaticSteps: Int, measuredDistanceMeters: Double?, metrics: BodyMetrics) -> Double? {
        guard metrics.canEstimate, let height = metrics.heightCentimeters, let weight = metrics.weightKilograms else { return nil }
        let distance: Double
        if let measuredDistanceMeters, measuredDistanceMeters > 0 {
            distance = measuredDistanceMeters
        } else if automaticSteps > 0 {
            distance = Double(automaticSteps) * strideLengthMeters(heightCentimeters: height)
        } else {
            // Keine Bewegung erfasst (z. B. iPhone nicht dabei): nichts zu schätzen, keine erfundene 0.
            return nil
        }
        return distance * weight * kilocaloriesPerKilogramMeter
    }
}

public extension DailyActivitySummary {
    /// Aktive Kalorien des Tages: Gemessene Werte aus Apple Health haben Vorrang, eine Schätzung gibt es nur, wenn
    /// keine gemessenen vorliegen – nie beides zusammen.
    var activeEnergy: ActiveEnergy {
        if let activeEnergyKilocalories { return .measured(activeEnergyKilocalories) }
        if let estimatedActiveEnergyKilocalories { return .estimated(estimatedActiveEnergyKilocalories) }
        return .unavailable
    }

    /// Derselbe Tag mit Schätzung, falls Apple Health keine aktiven Kalorien liefert und geschätzt werden kann. Schritte,
    /// Wettbewerbsschritte und gemessene Werte bleiben unverändert.
    func estimatingActiveEnergy(with metrics: BodyMetrics) -> DailyActivitySummary {
        let estimate: Double? = activeEnergyKilocalories == nil
            ? CalorieEstimator.kilocalories(
                automaticSteps: competitionSteps,
                // Manuell eingetragene Schritte könnten auch die Strecke enthalten – dann zählen nur die automatischen.
                measuredDistanceMeters: hasNonCompetitionSteps ? nil : walkingRunningDistanceMeters,
                metrics: metrics
            )
            : nil
        guard estimate != estimatedActiveEnergyKilocalories else { return self }
        return DailyActivitySummary(
            date: date,
            healthSteps: healthSteps,
            competitionSteps: competitionSteps,
            walkingRunningDistanceMeters: walkingRunningDistanceMeters,
            activeEnergyKilocalories: activeEnergyKilocalories,
            flightsClimbed: flightsClimbed,
            exerciseMinutes: exerciseMinutes,
            estimatedActiveEnergyKilocalories: estimate
        )
    }
}

public extension ActivityPeriodSummary {
    /// Aktive Kalorien des Zeitraums: je Tag gemessen oder geschätzt (nie beides). Ist mindestens ein Tag geschätzt,
    /// gilt die Summe als geschätzt.
    var activeEnergy: ActiveEnergy {
        var total = 0.0
        var hasValue = false
        var isEstimated = false
        for day in days {
            switch day.activeEnergy {
            case .measured(let value):
                total += value
                hasValue = true
            case .estimated(let value):
                total += value
                hasValue = true
                isEstimated = true
            case .unavailable:
                continue
            }
        }
        guard hasValue else { return .unavailable }
        return isEstimated ? .estimated(total) : .measured(total)
    }
}

public extension ActivityOverview {
    /// Dieselbe Übersicht mit geschätzten aktiven Kalorien an Tagen ohne gemessene (siehe
    /// ``DailyActivitySummary/estimatingActiveEnergy(with:)``).
    func estimatingActiveEnergy(with metrics: BodyMetrics) -> ActivityOverview {
        guard metrics.canEstimate else { return self }
        func estimate(_ period: ActivityPeriodSummary) -> ActivityPeriodSummary {
            ActivityPeriodSummary(period: period.period, days: period.days.map { $0.estimatingActiveEnergy(with: metrics) })
        }
        return ActivityOverview(
            today: today.estimatingActiveEnergy(with: metrics),
            yesterday: yesterday.estimatingActiveEnergy(with: metrics),
            currentWeek: estimate(currentWeek),
            lastSevenDays: estimate(lastSevenDays),
            updatedAt: updatedAt
        )
    }
}

/// Speicher der Körperdaten (nur auf dem Gerät).
public protocol BodyMetricsStoring: Sendable {
    func load() -> BodyMetrics?
    func save(_ metrics: BodyMetrics)
}

/// Körperdaten in den `UserDefaults` der App (Gerät, App-Sandbox; nicht synchronisiert, nicht im Backend).
public struct UserDefaultsBodyMetricsStore: BodyMetricsStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "pace.bodyMetrics.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> BodyMetrics? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(BodyMetrics.self, from: $0) }
    }

    public func save(_ metrics: BodyMetrics) {
        if let data = try? JSONEncoder().encode(metrics) {
            defaults.set(data, forKey: key)
        }
    }
}

public final class InMemoryBodyMetricsStore: BodyMetricsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: BodyMetrics?

    public init(_ metrics: BodyMetrics? = nil) {
        stored = metrics
    }

    public func load() -> BodyMetrics? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    public func save(_ metrics: BodyMetrics) {
        lock.lock()
        defer { lock.unlock() }
        stored = metrics
    }
}

/// Einstellungen der Kalorienschätzung – eine Quelle für Einstellungen, Home, Statistik und Kalender.
@MainActor
@Observable
public final class BodyMetricsSettings {
    /// Ergebnis einer Eingabe.
    public enum InputError: Error, Equatable, Sendable {
        case notANumber
        case outOfRange(ClosedRange<Double>)
    }

    public private(set) var metrics: BodyMetrics

    @ObservationIgnored private let store: any BodyMetricsStoring

    public init(store: any BodyMetricsStoring) {
        self.store = store
        metrics = store.load() ?? BodyMetrics()
    }

    public func setEstimationEnabled(_ enabled: Bool) {
        update { $0.isEstimationEnabled = enabled }
    }

    /// Größe aus einer Eingabe (z. B. „182“ oder „182,5“); leer löscht den Wert.
    @discardableResult
    public func setHeight(_ text: String) -> InputError? {
        set(text, range: BodyMetrics.heightRange) { metrics, value in metrics.heightCentimeters = value }
    }

    /// Gewicht aus einer Eingabe (z. B. „74“ oder „74,5“); leer löscht den Wert.
    @discardableResult
    public func setWeight(_ text: String) -> InputError? {
        set(text, range: BodyMetrics.weightRange) { metrics, value in metrics.weightKilograms = value }
    }

    /// Eingabe als Zahl (Komma oder Punkt); `nil` bei leerer Eingabe.
    public static func number(from text: String) -> Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        return .some(value)
    }

    private func set(_ text: String, range: ClosedRange<Double>, apply: (inout BodyMetrics, Double?) -> Void) -> InputError? {
        guard let parsed = Self.number(from: text) else { return .notANumber }
        if let value = parsed, !range.contains(value) { return .outOfRange(range) }
        update { apply(&$0, parsed.map { ($0 * 10).rounded() / 10 }) }
        return nil
    }

    private func update(_ change: (inout BodyMetrics) -> Void) {
        var updated = metrics
        change(&updated)
        guard updated != metrics else { return }
        metrics = updated
        store.save(updated)
    }
}
