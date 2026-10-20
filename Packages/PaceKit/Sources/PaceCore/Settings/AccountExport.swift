import Foundation

/// Datenexport (DSGVO Art. 15/20): fasst die Daten vom Server und die nur auf diesem iPhone gespeicherten Daten zu einer
/// lesbaren JSON-Datei zusammen.
///
/// Aufbau:
/// ```json
/// {
///   "format": "pace-export",
///   "version": 1,
///   "exportedAt": "2026-10-20T08:15:00Z",
///   "appVersion": "0.1.0 (1)",
///   "server": { … Antwort von account_export … },
///   "device": { "settings": { … }, "stepGoalHistory": [ … ], … },
///   "notes": [ … ]
/// }
/// ```
public enum AccountExport {
    public static let format = "pace-export"
    public static let version = 1

    public enum Failure: Error, Equatable, Sendable {
        /// Die Antwort des Servers ist kein gültiges JSON.
        case invalidServerData
    }

    /// Erstellt die Exportdatei.
    /// - Parameters:
    ///   - server: JSON aus `AccountRepository.exportData()`.
    ///   - device: Lokale Abschnitte aus `LocalAccountDataStoring.exportSections()`. Ungültige Abschnitte werden
    ///     übersprungen statt den ganzen Export zu verhindern.
    public static func document(
        server: Data,
        device: [LocalDataSection],
        exportedAt: Date,
        appVersion: String
    ) throws -> Data {
        guard let serverObject = try? JSONSerialization.jsonObject(with: server, options: [.fragmentsAllowed]) else {
            throw Failure.invalidServerData
        }
        var deviceObject: [String: Any] = [:]
        for section in device {
            guard let value = try? JSONSerialization.jsonObject(with: section.json, options: [.fragmentsAllowed]) else {
                continue
            }
            deviceObject[section.name] = value
        }
        let root: [String: Any] = [
            "format": format,
            "version": version,
            "exportedAt": timestamp(exportedAt),
            "appVersion": appVersion,
            "server": serverObject,
            "device": deviceObject,
            "notes": notes,
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// Dateiname, z. B. `pace-export-2026-10-20.json`.
    public static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "pace-export-\(day).json"
    }

    /// Erklärungen in der Datei selbst (bewusst auf Englisch, damit die Datei unabhängig von der App-Sprache
    /// verständlich bleibt).
    static let notes = [
        "server: personal data stored by Pace on its server (profile, daily competition steps, friends, groups, chats, reports, feedback).",
        "device: data stored only on this iPhone (settings, daily goal history, streak record, home layout, cached profile).",
        "Health data from Apple Health is not stored by Pace and is therefore not part of this export.",
    ]

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
