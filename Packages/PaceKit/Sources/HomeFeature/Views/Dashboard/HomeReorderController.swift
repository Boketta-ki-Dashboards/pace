import DesignSystem
import Observation
import PaceCore
import SwiftUI
import UIKit

/// Umsortieren der Widgets am Ziehgriff (Anpassen-Modus): Das Widget folgt dem Finger, die anderen weichen aus, am
/// oberen und unteren Rand scrollt die Liste selbst weiter.
///
/// Funktionsweise
/// - Jedes Widget meldet seinen Layout-Rahmen im Koordinatensystem des Scroll-Inhalts (``reportFrame(_:for:)``).
/// - Der Fingerpunkt kommt global aus der Griff-Geste. Im Inhalt liegt er bei
///   `Finger − Inhaltsoberkante beim Start + (Scroll-Versatz jetzt − Scroll-Versatz beim Start)`, deshalb bleibt das
///   Widget auch beim automatischen Scrollen unter dem stillstehenden Finger.
/// - Beim Start wird der Aufbau der Liste festgehalten (``HomeReorderLayout``: Oberkante, Abstand, Höhen). Daraus
///   ergibt sich der Platz jedes Widgets für jede Reihenfolge sofort; das gezogene Widget wird um
///   `Fingerpunkt − Griffabstand − Platz-Oberkante` verschoben. So springt es nach einem Platztausch nicht (gemessene
///   Rahmen kämen erst nach dem nächsten Layout an).
/// - Die Reihenfolge ändert sich live, gespeichert wird einmal beim Loslassen (``HomeDashboardViewModel/endDragging()``).
/// - Ende, Abbruch durch das System, Verlassen des Anpassen-Modus, der Seite oder der App beenden das Ziehen und das
///   automatische Scrollen sofort (``endDrag()``); es bleibt kein Display-Link übrig.
@MainActor
@Observable
final class HomeReorderController {
    /// Koordinatensystem des Scroll-Inhalts von Home.
    nonisolated static let contentSpace = "pace.home.content"

    private(set) var draggingID: HomeModule.ID?
    /// Fingerpunkt im Scroll-Inhalt (nur während des Ziehens).
    private(set) var fingerContentY: CGFloat = 0
    private(set) var grabOffset: CGFloat = 0

    @ObservationIgnored private var frames: [HomeModule.ID: CGRect] = [:]
    /// Aufbau der Liste während des Ziehens (beobachtet, damit die Verschiebung mit der Reihenfolge Schritt hält).
    private var layout: HomeReorderLayout<HomeModule.ID>?
    @ObservationIgnored private weak var scrollView: UIScrollView?
    /// Sichtbarer Bereich des Scrollens (global) und Oberkante des Inhalts (global).
    @ObservationIgnored private var viewportFrame: CGRect = .zero
    @ObservationIgnored private var contentMinY: CGFloat = 0
    @ObservationIgnored private var fingerGlobalY: CGFloat = 0
    @ObservationIgnored private var startContentMinY: CGFloat = 0
    @ObservationIgnored private var startScrollOffset: CGFloat = 0
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var displayLinkTarget: DisplayLinkTarget?
    @ObservationIgnored private var lastTick: CFTimeInterval?
    @ObservationIgnored private weak var dashboard: HomeDashboardViewModel?

    var isDragging: Bool { draggingID != nil }

    // MARK: Messwerte aus den Views

    func reportFrame(_ frame: CGRect, for id: HomeModule.ID) {
        frames[id] = frame
        // Wächst ein anderes Widget während des Ziehens (z. B. Daten geladen), zählt seine neue Höhe.
        if isDragging, id != draggingID, let height = layout?.heights[id], abs(height - frame.height) > 0.5 {
            layout?.heights[id] = frame.height
        }
    }

    func reportViewport(_ frame: CGRect) {
        viewportFrame = frame
    }

    func reportContentMinY(_ minY: CGFloat) {
        contentMinY = minY
    }

    /// Nur eine senkrechte Scrollansicht kommt infrage – nie die waagerechte Seitenleiste der Haupttabs.
    func attach(_ scrollView: UIScrollView) {
        guard !HomeScrollViewFinder.scrollsHorizontally(scrollView) else { return }
        self.scrollView = scrollView
    }

    // MARK: Geste

    /// Fingerbewegung am Griff (globale Koordinaten). Der erste Aufruf beginnt das Ziehen.
    func drag(_ id: HomeModule.ID, toGlobalY y: CGFloat, dashboard: HomeDashboardViewModel) {
        fingerGlobalY = y
        if draggingID == nil {
            let order = dashboard.modules.map(\.id)
            guard let frame = frames[id],
                  let layout = HomeReorderLayout(order: order, frames: frames, fallbackSpacing: PaceSpacing.s)
            else { return }
            if let scrollView, HomeScrollViewFinder.scrollsHorizontally(scrollView) {
                self.scrollView = nil
            }
            self.dashboard = dashboard
            self.layout = layout
            startContentMinY = contentMinY
            startScrollOffset = scrollView?.contentOffset.y ?? 0
            fingerContentY = currentFingerContentY
            grabOffset = fingerContentY - frame.minY
            draggingID = id
            dashboard.beginDragging(id)
            startDisplayLink()
        } else {
            fingerContentY = currentFingerContentY
        }
        reorderIfNeeded()
    }

    /// Finger losgelassen oder Geste abgebrochen: Widget rastet an seinem Platz ein, die Reihenfolge wird gespeichert.
    /// Mehrfaches Aufrufen schadet nicht.
    func endDrag() {
        stopDisplayLink()
        guard draggingID != nil else { return }
        draggingID = nil
        layout = nil
        dashboard?.endDragging()
        dashboard = nil
    }

    /// Verschiebung des Widgets gegenüber seinem Platz in der aktuellen Reihenfolge (nur das gezogene).
    func offset(for id: HomeModule.ID) -> CGFloat {
        guard id == draggingID, let layout, let dashboard,
              let slotTop = layout.slotTop(of: id, order: dashboard.modules.map(\.id))
        else { return 0 }
        return fingerContentY - grabOffset - slotTop
    }

    /// Läuft gerade automatisches Scrollen (Tests, Diagnose).
    var isAutoScrolling: Bool { displayLink != nil }

    // MARK: Intern

    private var scrollDelta: CGFloat {
        (scrollView?.contentOffset.y ?? startScrollOffset) - startScrollOffset
    }

    private var currentFingerContentY: CGFloat {
        fingerGlobalY - startContentMinY + scrollDelta
    }

    private func reorderIfNeeded() {
        guard let draggingID, let dashboard, let layout, let height = layout.heights[draggingID] else { return }
        let order = dashboard.modules.map(\.id)
        let center = fingerContentY - grabOffset + height / 2
        guard let target = HomeReorderMath.targetIndex(
            order: order, frames: layout.frames(order: order), dragging: draggingID, draggedCenterY: center
        ), target != order.firstIndex(of: draggingID)
        else { return }
        dashboard.moveDragged(toIndex: target)
    }

    private func startDisplayLink() {
        stopDisplayLink()
        let target = DisplayLinkTarget { [weak self] link in
            self?.tick(link)
        }
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        displayLinkTarget = target
        lastTick = nil
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
        lastTick = nil
    }

    /// Auto-Scroll am Rand: Versatz anpassen, Fingerpunkt im Inhalt nachführen, Reihenfolge prüfen.
    private func tick(_ link: CADisplayLink) {
        defer { lastTick = link.timestamp }
        // Sicherheitsnetz: Ohne laufendes Ziehen gibt es kein automatisches Scrollen.
        guard isDragging else {
            stopDisplayLink()
            return
        }
        guard let scrollView, let lastTick else { return }
        let elapsed = min(link.timestamp - lastTick, 1.0 / 20)
        let fingerInViewport = fingerGlobalY - viewportFrame.minY
        let velocity = HomeReorderMath.autoScrollVelocity(fingerY: fingerInViewport, viewportHeight: viewportFrame.height)
        guard velocity != 0 else { return }
        let inset = scrollView.adjustedContentInset
        let offset = HomeReorderMath.clampedOffset(
            scrollView.contentOffset.y,
            delta: velocity * elapsed,
            minimum: -inset.top,
            maximum: scrollView.contentSize.height - scrollView.bounds.height + inset.bottom
        )
        guard offset != scrollView.contentOffset.y else { return }
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: offset), animated: false)
        fingerContentY = currentFingerContentY
        reorderIfNeeded()
    }
}

/// `CADisplayLink` braucht ein Objective-C-Ziel; hält den Controller nur schwach. Der Display-Link läuft auf dem
/// Main-Run-Loop, deshalb ist das Ziel an den Main Actor gebunden.
@MainActor
private final class DisplayLinkTarget: NSObject {
    private let action: (CADisplayLink) -> Void

    init(action: @escaping (CADisplayLink) -> Void) {
        self.action = action
    }

    @objc func step(_ link: CADisplayLink) {
        action(link)
    }
}

/// Findet die `UIScrollView` hinter einer SwiftUI-`ScrollView`, damit beim Ziehen automatisch gescrollt werden kann.
/// Ohne Treffer funktioniert das Umsortieren weiter, nur ohne Auto-Scroll.
struct HomeScrollViewFinder: UIViewRepresentable {
    let onFind: (UIScrollView) -> Void

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.onFind = onFind
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: FinderView, context: Context) {
        uiView.onFind = onFind
        uiView.findScrollView()
    }

    /// Die waagerechte Seitenleiste der Haupttabs (breiter Inhalt) – darf nie automatisch gescrollt werden.
    @MainActor
    static func scrollsHorizontally(_ scrollView: UIScrollView) -> Bool {
        scrollView.contentSize.width > scrollView.bounds.width + 1
    }

    final class FinderView: UIView {
        var onFind: ((UIScrollView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            findScrollView()
        }

        /// Die nächste umgebende senkrechte Scrollansicht.
        func findScrollView() {
            var candidate = superview
            while let view = candidate {
                if let scrollView = view as? UIScrollView, !HomeScrollViewFinder.scrollsHorizontally(scrollView) {
                    onFind?(scrollView)
                    return
                }
                candidate = view.superview
            }
        }
    }
}
