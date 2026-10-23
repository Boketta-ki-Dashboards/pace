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

    /// Rendert eine Ansicht in einem echten Fenster: UIKit-Layout mit `NavigationStack`, Textfeldern und Safe Areas
    /// wie auf einem iPhone 15/16 (Dynamic Island oben, Home-Indikator unten). So wird sichtbar, wo Kopf, Inhalte,
    /// Eingabeleisten und Tab-Leiste tatsächlich landen. Sprache: App-Sprache (Deutsch).
    /// - Parameters:
    ///   - prepare: Wird nach dem ersten Layout aufgerufen (z. B. ans Ende scrollen).
    static func renderInWindow(
        _ content: some View,
        name: String,
        size: CGSize = CGSize(width: 393, height: 852),
        safeArea: UIEdgeInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
        prepare: ((UIView) -> Void)? = nil
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let controller = UIHostingController(rootView: content.environment(\.colorScheme, scheme))
            controller.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
            controller.additionalSafeAreaInsets = safeArea
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = controller
            window.isHidden = false
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            // SwiftUI baut Navigation und Inhalte asynchron auf.
            try await Task.sleep(for: .milliseconds(700))
            controller.view.layoutIfNeeded()
            if let prepare {
                prepare(controller.view)
                try await Task.sleep(for: .milliseconds(400))
                controller.view.layoutIfNeeded()
            }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            guard let data = image.pngData() else { throw Failure.renderFailed(name) }
            let schemeSuffix = scheme == .dark ? "dark" : "light"
            try data.write(to: directory.appendingPathComponent("\(name)-\(schemeSuffix).png"))
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    /// Scrollt die größte Scrollansicht im Fenster ans Ende (z. B. um zu prüfen, ob das Letzte über der Tab-Leiste
    /// erreichbar ist).
    static func scrollToBottom(in view: UIView) {
        var scrollViews: [UIScrollView] = []
        func collect(_ view: UIView) {
            if let scrollView = view as? UIScrollView { scrollViews.append(scrollView) }
            view.subviews.forEach(collect)
        }
        collect(view)
        guard let scrollView = scrollViews.max(by: { $0.contentSize.height < $1.contentSize.height }) else { return }
        let inset = scrollView.adjustedContentInset
        let bottom = max(-inset.top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        scrollView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
    }
}
