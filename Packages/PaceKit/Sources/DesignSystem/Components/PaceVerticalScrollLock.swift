import SwiftUI
import UIKit

public extension View {
    /// Für Inhalte **innerhalb** einer senkrechten Scrollansicht: Die Seite bleibt waagerecht fest in der Bildschirmbreite.
    ///
    /// Eine senkrechte `UIScrollView` lässt sich waagerecht verschieben, sobald ihr Inhalt auch nur wenig breiter ist als
    /// sie selbst (oder sie waagerecht nachfedert). Dann wandert beim diagonalen Scrollen oder Wischen die ganze Seite
    /// zur Seite und Texte am Rand werden abgeschnitten – auch wenn das Wischen zwischen den Tabs gesperrt ist
    /// (Anpassen-Modus von Home). Hier bekommt die umgebende Scrollansicht deshalb:
    /// - Richtungssperre (`isDirectionalLockEnabled`): Eine überwiegend senkrechte Bewegung bleibt senkrecht.
    /// - kein waagerechtes Nachfedern (`alwaysBounceHorizontal = false`),
    /// - einen festen waagerechten Versatz: Jede waagerechte Verschiebung wird sofort zurückgesetzt.
    ///
    /// Bewusst waagerechte Bedienelemente (Tab-Wischen, Monats- und Zeitraumwechsel, Karussells, Zurück-Geste) bleiben
    /// unberührt: Sie sind eigene Gesten bzw. eigene waagerechte Scrollansichten. Die Seitenleiste der Haupttabs wird nie
    /// gesperrt.
    func paceVerticalScrollLock() -> some View {
        modifier(PaceVerticalScrollLockModifier())
    }
}

public extension EnvironmentValues {
    /// Nur für die Gegenprobe in Tests: schaltet ``SwiftUI/View/paceVerticalScrollLock()`` ab.
    @Entry var paceVerticalScrollLockEnabled = true
}

private struct PaceVerticalScrollLockModifier: ViewModifier {
    @Environment(\.paceVerticalScrollLockEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.background {
            if isEnabled {
                PaceVerticalScrollLockView()
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Regeln der Sperre (getrennt testbar).
@MainActor
public enum PaceVerticalScrollLockRules {
    /// Scrollansichten, die waagerecht scrollen sollen (die Seitenleiste der Haupttabs meldet sich hier an).
    private static let horizontalScrollViews = NSHashTable<UIScrollView>.weakObjects()

    /// Meldet eine bewusst waagerechte Scrollansicht an – sie wird nie gesperrt.
    static func registerHorizontal(_ scrollView: UIScrollView) {
        horizontalScrollViews.add(scrollView)
    }

    /// Die waagerechte Seitenleiste der Haupttabs (angemeldet oder mehrere Seiten nebeneinander) – wird nie gesperrt.
    public static func isPager(_ scrollView: UIScrollView) -> Bool {
        horizontalScrollViews.contains(scrollView)
            || (scrollView.bounds.width > 0 && scrollView.contentSize.width >= scrollView.bounds.width * 1.5)
    }

    /// Ob die Sperre die Scrollansicht übernehmen darf: senkrechte Scrollansicht mit fertigem Layout.
    static func canLock(_ scrollView: UIScrollView) -> Bool {
        scrollView.bounds.width > 0 && !isPager(scrollView)
    }

    /// Waagerechter Versatz im Ruhezustand (linker Rand des Inhalts).
    public static func restingX(_ scrollView: UIScrollView) -> CGFloat {
        -scrollView.adjustedContentInset.left
    }

    /// Richtet die Scrollansicht ein und setzt einen waagerechten Versatz zurück.
    public static func lock(_ scrollView: UIScrollView) {
        if !scrollView.isDirectionalLockEnabled { scrollView.isDirectionalLockEnabled = true }
        if scrollView.alwaysBounceHorizontal { scrollView.alwaysBounceHorizontal = false }
        pin(scrollView)
    }

    /// Setzt einen waagerechten Versatz zurück (senkrechte Position bleibt).
    public static func pin(_ scrollView: UIScrollView) {
        let x = restingX(scrollView)
        guard abs(scrollView.contentOffset.x - x) > 0.25 else { return }
        scrollView.contentOffset = CGPoint(x: x, y: scrollView.contentOffset.y)
    }
}

/// Unsichtbarer Marker im Scroll-Inhalt: findet die umgebende senkrechte Scrollansicht und hält sie waagerecht fest.
private struct PaceVerticalScrollLockView: UIViewRepresentable {
    func makeUIView(context: Context) -> LockView {
        let view = LockView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: LockView, context: Context) {
        uiView.attach()
    }

    final class LockView: UIView {
        private weak var scrollView: UIScrollView?
        private var observations: [NSKeyValueObservation] = []

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                detach()
            } else {
                attach()
                // Beim ersten Erscheinen ist das Layout oft noch nicht fertig: danach noch einmal.
                DispatchQueue.main.async { [weak self] in self?.attach() }
            }
        }

        /// Nächste umgebende Scrollansicht – nur, wenn es eine senkrechte ist (nie die Seitenleiste der Haupttabs).
        func attach() {
            guard window != nil else { return }
            var candidate = superview
            while let view = candidate {
                if let found = view as? UIScrollView {
                    guard PaceVerticalScrollLockRules.canLock(found) else { return }
                    guard found !== scrollView else {
                        PaceVerticalScrollLockRules.lock(found)
                        return
                    }
                    detach()
                    scrollView = found
                    PaceVerticalScrollLockRules.lock(found)
                    // Jede Änderung des Versatzes (Finger, Nachfedern, Layout) – waagerecht sofort zurück.
                    observations = [
                        found.observe(\.contentOffset, options: [.new]) { scrollView, _ in
                            Self.pinOnMainThread(scrollView)
                        },
                        found.observe(\.contentSize, options: [.new]) { scrollView, _ in
                            Self.pinOnMainThread(scrollView)
                        },
                    ]
                    return
                }
                candidate = view.superview
            }
        }

        /// KVO meldet Änderungen von UIKit auf dem Hauptthread (die Scrollansicht wird nur dort verändert).
        nonisolated private static func pinOnMainThread(_ scrollView: UIScrollView) {
            nonisolated(unsafe) let target = scrollView
            MainActor.assumeIsolated { PaceVerticalScrollLockRules.pin(target) }
        }

        private func detach() {
            observations.forEach { $0.invalidate() }
            observations = []
            scrollView = nil
        }
    }
}

/// Meldet die umgebende Scrollansicht als bewusst waagerecht an (Seitenleiste der Haupttabs) und reicht sie weiter.
struct PaceHorizontalScrollRegistrar: UIViewRepresentable {
    var onFind: (UIScrollView) -> Void = { _ in }

    func makeUIView(context: Context) -> RegistrarView {
        let view = RegistrarView()
        view.isUserInteractionEnabled = false
        view.onFind = onFind
        return view
    }

    func updateUIView(_ uiView: RegistrarView, context: Context) {
        uiView.onFind = onFind
        uiView.register()
    }

    final class RegistrarView: UIView {
        var onFind: ((UIScrollView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            register()
        }

        func register() {
            var candidate = superview
            while let view = candidate {
                if let scrollView = view as? UIScrollView {
                    PaceVerticalScrollLockRules.registerHorizontal(scrollView)
                    onFind?(scrollView)
                    return
                }
                candidate = view.superview
            }
        }
    }
}
