import PaceCore
import SwiftUI
import UIKit

/// Kopf einer Unterseite in fester Reihenfolge: Zurück-Link, Pace-Wortmarke, Seitentitel – alles linksbündig.
///
/// Beispiel: „‹ Social“ → „pace“ → „Freund hinzufügen“. Zusammen mit ``SwiftUI/View/paceSubpage()`` verwenden, das die
/// Systemleiste ausblendet und die Wisch-Geste zum Zurückgehen erhält.
public struct PaceSubpageHeader<Trailing: View>: View {
    public enum TitleSize {
        /// Große Überschrift (Standard).
        case large
        /// Kleinere Überschrift, damit die Wortmarke dominiert (z. B. „Tagesdetails“).
        case medium
    }

    private let backTitle: String
    private let title: String
    private let subtitle: String?
    private let titleSize: TitleSize
    private let onBack: (() -> Void)?
    private let trailing: Trailing

    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - backTitle: Ziel des Zurück-Links, z. B. „Social“.
    ///   - onBack: Eigene Zurück-Aktion; ohne Angabe schließt der Link die Seite.
    ///   - trailing: Optionale Buttons rechts neben der Wortmarke.
    public init(
        backTitle: String,
        title: String,
        subtitle: String? = nil,
        titleSize: TitleSize = .large,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.backTitle = backTitle
        self.title = title
        self.subtitle = subtitle
        self.titleSize = titleSize
        self.onBack = onBack
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            Button {
                if let onBack { onBack() } else { dismiss() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(.body, weight: .semibold))
                    Text(backTitle)
                        .font(.body)
                        .lineLimit(1)
                }
                .foregroundStyle(PaceColor.accent)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PaceLocalization.text(
                de: "Zurück zu \(backTitle)", en: "Back to \(backTitle)", ru: "Назад: \(backTitle)"
            ))

            HStack(alignment: .center, spacing: PaceSpacing.s) {
                PaceWordmark(height: titleSize == .large ? 33 : 56)
                Spacer(minLength: PaceSpacing.xs)
                trailing
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(titleSize == .large ? .system(.title, weight: .bold) : .system(.title2, weight: .bold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.title3))
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, PaceSpacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PaceSubpageHeader where Trailing == EmptyView {
    public init(
        backTitle: String,
        title: String,
        subtitle: String? = nil,
        titleSize: TitleSize = .large,
        onBack: (() -> Void)? = nil
    ) {
        self.init(backTitle: backTitle, title: title, subtitle: subtitle, titleSize: titleSize, onBack: onBack) {
            EmptyView()
        }
    }
}

public extension View {
    /// Für Unterseiten mit ``PaceSubpageHeader``: blendet die Navigationsleiste aus und erhält die Wisch-Geste vom
    /// linken Rand zum Zurückgehen.
    func paceSubpage() -> some View {
        toolbar(.hidden, for: .navigationBar)
            .paceStatusBarBackdrop()
            .background(SwipeBackEnabler().frame(width: 0, height: 0).accessibilityHidden(true))
    }

    /// Für die Startseite eines Tabs: ohne Navigationsleiste (die Seite zeigt ihren eigenen Kopf).
    func paceRootPage() -> some View {
        toolbar(.hidden, for: .navigationBar)
            .paceStatusBarBackdrop()
    }

    /// Hintergrund hinter der Statusleiste für Seiten ohne Navigationsleiste.
    ///
    /// Ohne Systemleiste läuft scrollender Inhalt sonst bis unter Uhrzeit und Symbole der Statusleiste und überlagert
    /// sich mit ihnen. Der Streifen hat genau die Höhe der oberen Safe Area (Dynamic Island, Notch, ohne feste Werte),
    /// die Farbe des Seitenhintergrunds und belegt selbst keinen Platz: Am oberen Ende ist er unsichtbar, nichts
    /// verschiebt sich, und der Inhalt bleibt bis zum Ende scrollbar.
    func paceStatusBarBackdrop() -> some View {
        modifier(PaceStatusBarBackdrop())
    }
}

public extension EnvironmentValues {
    /// Nur für Vorher-Nachher-Bilder in Snapshot-Tests: schaltet den Statusleisten-Hintergrund ab.
    @Entry var paceStatusBarBackdropEnabled = true
}

private struct PaceStatusBarBackdrop: ViewModifier {
    @Environment(\.paceStatusBarBackdropEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if isEnabled {
                Color.clear
                    .frame(height: 0)
                    .background(PaceColor.background, ignoresSafeAreaEdges: .top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Ohne sichtbare Navigationsleiste schaltet UIKit die Wisch-Geste zum Zurückgehen ab. Dieser unsichtbare Controller
/// schaltet sie für die Unterseite wieder ein; ein gemeinsamer Delegate verhindert sie auf der Startseite eines Stacks.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let recognizer = navigationController?.interactivePopGestureRecognizer else { return }
            recognizer.isEnabled = true
            recognizer.delegate = SwipeBackDelegate.shared
        }
    }
}

@MainActor
private final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackDelegate()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Die Geste gehört zur Ansicht des Navigation Controllers; auf der Startseite gibt es nichts zum Zurückgehen.
        guard let navigationController = gestureRecognizer.view?.next as? UINavigationController else { return false }
        return navigationController.viewControllers.count > 1
    }
}
