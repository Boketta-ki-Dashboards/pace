import SwiftUI
import UIKit

/// Verbindung eines Haupttabs zur Tab-Navigation: Der Tab meldet, ob seine Startseite sichtbar ist (nur dann darf
/// zwischen den Tabs gewischt werden), und reagiert auf erneutes Antippen seines Tabs.
public struct PaceTabRootContext {
    /// Zählt jedes erneute Antippen des schon aktiven Tabs.
    public var reselection: Int
    /// Meldet, ob die Startseite des Tabs sichtbar ist (keine Unterseite offen).
    public var reportRoot: (Bool) -> Void

    public init(reselection: Int = 0, reportRoot: @escaping (Bool) -> Void = { _ in }) {
        self.reselection = reselection
        self.reportRoot = reportRoot
    }
}

private struct PaceTabRootKey: EnvironmentKey {
    static var defaultValue: PaceTabRootContext { PaceTabRootContext() }
}

public extension EnvironmentValues {
    var paceTabRoot: PaceTabRootContext {
        get { self[PaceTabRootKey.self] }
        set { self[PaceTabRootKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// Die Seite gehört zum gerade gewählten Haupttab. Seiten anderer Tabs bleiben im Pager aufgebaut (ohne
    /// `onDisappear`) – z. B. ein offener Chat gilt dann nicht mehr als sichtbar.
    @Entry public var paceTabIsActive: Bool = true
}

public extension View {
    /// Für den Inhalt der Startseite eines Haupttabs **innerhalb** ihrer Scrollansicht. Hält die Seite zugleich
    /// waagerecht fest (``SwiftUI/View/paceVerticalScrollLock()``).
    ///
    /// Erneutes Antippen des aktiven Tabs: Auf der Startseite scrollt sie animiert ganz nach oben, auf einer Unterseite
    /// geht es zurück zur Startseite (wie bei iOS-Tab-Leisten) – nie zu einem anderen Tab.
    /// - Parameters:
    ///   - isAtRoot: Ob gerade die Startseite sichtbar ist (z. B. leerer Navigationspfad).
    ///   - popToRoot: Schließt alle Unterseiten.
    func paceTabRoot(isAtRoot: Bool, popToRoot: @escaping () -> Void) -> some View {
        modifier(PaceTabRootModifier(isAtRoot: isAtRoot, popToRoot: popToRoot))
    }
}

private struct PaceTabRootModifier: ViewModifier {
    let isAtRoot: Bool
    let popToRoot: () -> Void

    @Environment(\.paceTabRoot) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollView = WeakScrollView()

    func body(content: Content) -> some View {
        content
            // Startseiten scrollen nur senkrecht – auch im Anpassen-Modus von Home rutscht nichts zur Seite.
            .paceVerticalScrollLock()
            .background {
                EnclosingScrollViewFinder { [scrollView] found in
                    scrollView.value = found
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            .onChange(of: isAtRoot, initial: true) { _, isAtRoot in
                context.reportRoot(isAtRoot)
            }
            .onChange(of: context.reselection) {
                if isAtRoot {
                    scrollToTop()
                } else {
                    popToRoot()
                }
            }
    }

    private func scrollToTop() {
        guard let view = scrollView.value else { return }
        let top = CGPoint(x: view.contentOffset.x, y: -view.adjustedContentInset.top)
        view.setContentOffset(top, animated: !reduceMotion)
    }
}

/// Schwache Referenz auf die Scrollansicht (als `@State`, damit sie über Neuzeichnungen erhalten bleibt).
@MainActor
private final class WeakScrollView {
    weak var value: UIScrollView?
}

/// Findet die `UIScrollView`, in der dieser (unsichtbare) View liegt.
private struct EnclosingScrollViewFinder: UIViewRepresentable {
    let onFind: (UIScrollView) -> Void

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.isUserInteractionEnabled = false
        view.onFind = onFind
        return view
    }

    func updateUIView(_ uiView: FinderView, context: Context) {
        uiView.onFind = onFind
        uiView.find()
    }

    final class FinderView: UIView {
        var onFind: ((UIScrollView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            find()
        }

        func find() {
            var candidate = superview
            while let view = candidate {
                if let scrollView = view as? UIScrollView {
                    onFind?(scrollView)
                    return
                }
                candidate = view.superview
            }
        }
    }
}
