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
/// - Das gezogene Widget wird um `Fingerpunkt − Griffabstand − Layout-Oberkante` verschoben; nach jedem Platztausch
///   gleicht der neue Layout-Rahmen den Sprung aus.
/// - Die Reihenfolge wird bei jedem Platztausch sofort gespeichert (``HomeDashboardViewModel/moveDragged(toIndex:)``).
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
    }

    func reportViewport(_ frame: CGRect) {
        viewportFrame = frame
    }

    func reportContentMinY(_ minY: CGFloat) {
        contentMinY = minY
    }

    func attach(_ scrollView: UIScrollView) {
        self.scrollView = scrollView
    }

    // MARK: Geste

    /// Fingerbewegung am Griff (globale Koordinaten). Der erste Aufruf beginnt das Ziehen.
    func drag(_ id: HomeModule.ID, toGlobalY y: CGFloat, dashboard: HomeDashboardViewModel) {
        fingerGlobalY = y
        if draggingID == nil {
            guard let frame = frames[id] else { return }
            self.dashboard = dashboard
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

    /// Finger losgelassen oder Geste abgebrochen: Widget rastet an seinem Platz ein.
    func endDrag() {
        stopDisplayLink()
        guard draggingID != nil else { return }
        draggingID = nil
        dashboard?.endDragging()
        dashboard = nil
    }

    /// Verschiebung des Widgets gegenüber seinem Platz im Layout (nur das gezogene).
    func offset(for id: HomeModule.ID) -> CGFloat {
        guard id == draggingID, let frame = frames[id] else { return 0 }
        return fingerContentY - grabOffset - frame.minY
    }

    // MARK: Intern

    private var scrollDelta: CGFloat {
        (scrollView?.contentOffset.y ?? startScrollOffset) - startScrollOffset
    }

    private var currentFingerContentY: CGFloat {
        fingerGlobalY - startContentMinY + scrollDelta
    }

    private func reorderIfNeeded() {
        guard let draggingID, let dashboard, let frame = frames[draggingID] else { return }
        let order = dashboard.modules.map(\.id)
        let center = fingerContentY - grabOffset + frame.height / 2
        guard let target = HomeReorderMath.targetIndex(order: order, frames: frames, dragging: draggingID, draggedCenterY: center),
              target != order.firstIndex(of: draggingID)
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
        guard isDragging, let scrollView, let lastTick else { return }
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

/// `CADisplayLink` braucht ein Objective-C-Ziel; hält den Controller nur schwach.
private final class DisplayLinkTarget: NSObject {
    private let action: @MainActor (CADisplayLink) -> Void

    init(action: @escaping @MainActor (CADisplayLink) -> Void) {
        self.action = action
    }

    @objc func step(_ link: CADisplayLink) {
        MainActor.assumeIsolated {
            action(link)
        }
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

    final class FinderView: UIView {
        var onFind: ((UIScrollView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            findScrollView()
        }

        func findScrollView() {
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
