import DesignSystem
import Foundation
import PaceCore
import SwiftUI
import Testing
import UIKit

/// Snapshot-Tests laufen nur, wenn `PACE_SNAPSHOT_DIR` gesetzt ist (CI-Artefakt „snapshots“), und prüfen nichts:
/// Es entstehen nur Bilder zur visuellen Kontrolle.
extension Trait where Self == ConditionTrait {
    static var snapshotsEnabled: Self {
        .enabled(if: ProcessInfo.processInfo.environment["PACE_SNAPSHOT_DIR"] != nil)
    }
}

/// Rendert Inhalte als PNG in Hell und Dunkel.
///
/// Gerendert werden die Inhalte ohne Navigation und Scrollen (`ImageRenderer` kann keine UIKit-Container zeichnen);
/// systemeigene Controls wie Schalter erscheinen dabei als Platzhalter. Kopfzeilen (`PaceSubpageHeader`) und die
/// Tab-Leiste (`PaceTabBar`) sind reine SwiftUI-Views und können mitgerendert werden.
@MainActor
enum Snapshot {
    /// Breite eines iPhone 15/16.
    static let width: CGFloat = 393

    enum Failure: Error {
        case renderFailed(String)
    }

    static var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["PACE_SNAPSHOT_DIR"] ?? NSTemporaryDirectory())
    }

    /// - Parameters:
    ///   - name: Dateiname ohne Endung, z. B. `social` → `social-light.png`, `social-dark.png`.
    ///   - languages: Für jede Sprache entstehen eigene Bilder; Deutsch ohne Zusatz, sonst mit Kürzel
    ///     (`social-en-light.png`, `social-ru-dark.png`).
    static func render(
        _ content: some View,
        name: String,
        width: CGFloat = width,
        languages: [AppLanguage] = [.german]
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in languages {
            try PaceLocalization.$languageOverride.withValue(language) {
                for scheme in [ColorScheme.light, .dark] {
                    let view = content
                        .frame(width: width)
                        .background(PaceColor.background)
                        .environment(\.colorScheme, scheme)
                        .environment(\.locale, language.locale)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    renderer.proposedSize = ProposedViewSize(width: width, height: nil)
                    guard let data = renderer.uiImage?.pngData() else { throw Failure.renderFailed(name) }
                    let languageSuffix = language == .german ? "" : "-\(language.rawValue)"
                    let schemeSuffix = scheme == .dark ? "dark" : "light"
                    try data.write(to: directory.appendingPathComponent("\(name)\(languageSuffix)-\(schemeSuffix).png"))
                }
            }
        }
    }
}
