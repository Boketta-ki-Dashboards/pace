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
/// - Während des Ziehens bleibt die Reihenfolge im Layout unverändert: Das gezogene Widget wird gegenüber seinem
///   ursprünglichen Platz verschoben, die Widgets zwischen Ausgangs- und Zielplatz rücken nur sichtbar um seine Höhe
///   auf bzw. ab (``HomeReorderMath/displacement(index:source:target:step:)``). Kein Neuaufbau des Layouts pro Tausch,
///   keine Animation, die mit der Fingerposition konkurriert – das Widget springt nicht.
/// - Beim Loslassen wird die neue Reihenfolge einmal übernommen und gespeichert (ohne Animation; sichtbar ändert sich
///   dabei nichts), danach rastet das Widget an seinem neuen Platz ein.
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
    /// Platz, an dem das gezogene Widget beim Loslassen landet (Index in der Reihenfolge beim Start).
    private(set) var targetIndex: Int?
    /// Das gerade abgelegte Widget, solange es an seinen neuen Platz gleitet.
    private(set) var settlingID: HomeModule.ID?
    private var settleOffset: CGFloat = 0

    @ObservationIgnored private var frames: [HomeModule.ID: CGRect] = [:]
    /// Aufbau und Reihenfolge der Liste beim Start des Ziehens.
    private var layout: HomeReorderLayout<HomeModule.ID>?
    private var dragOrder: [HomeModule.ID] = []
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
            settlingID = nil
            settleOffset = 0
            self.dashboard = dashboard
            self.layout = layout
            dragOrder = order
            targetIndex = order.firstIndex(of: id)
            startContentMinY = contentMinY
            startScrollOffset = scrollView?.contentOffset.y ?? 0
            fingerContentY = currentFingerContentY
            grabOffset = fingerContentY - frame.minY
            draggingID = id
            dashboard.beginDragging(id)
            startDisplayLink()
        } else {
            guard draggingID == id else { return }
            fingerContentY = currentFingerContentY
        }
        updateTarget()
    }

    /// Finger losgelassen oder Geste abgebrochen: neue Reihenfolge übernehmen und speichern, Widget rastet ein.
    /// Mehrfaches Aufrufen schadet nicht.
    func endDrag(animated: Bool = true) {
        stopDisplayLink()
        guard let draggingID else { return }
        let dashboard = dashboard
        let source = dragOrder.firstIndex(of: draggingID)
        let target = targetIndex ?? source
        var order = dragOrder
        if let source, let target, source != target {
            order.remove(at: source)
            order.insert(draggingID, at: min(target, order.count))
        }
        let landing = layout?.slotTop(of: draggingID, order: order)
        let visibleTop = fingerContentY - grabOffset

        // Ohne Animation: Reihenfolge übernehmen, Ausweich-Verschiebungen fallen weg – sichtbar ändert sich nichts.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let target, target != source {
                dashboard?.moveDragged(toIndex: target)
            }
            settlingID = animated ? draggingID : nil
            settleOffset = animated ? landing.map { visibleTop - $0 } ?? 0 : 0
            self.draggingID = nil
            targetIndex = nil
            layout = nil
            dragOrder = []
            dashboard?.endDragging()
            self.dashboard = nil
        }
        guard animated, settleOffset != 0 else {
            settlingID = nil
            return
        }
        // Erst nach dem Zeichnen an der Fingerposition an den neuen Platz gleiten.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.settlingID == draggingID else { return }
            withAnimation(.snappy(duration: 0.28)) {
                self.settleOffset = 0
            } completion: { [weak self] in
                if self?.settlingID == draggingID { self?.settlingID = nil }
            }
        }
    }

    /// Verschiebung eines Widgets gegenüber seinem Platz im Layout: das gezogene folgt dem Finger, die anderen weichen
    /// aus; das abgelegte gleitet an seinen Platz.
    func offset(for id: HomeModule.ID) -> CGFloat {
        if id == settlingID { return settleOffset }
        guard let draggingID, let layout,
              let source = dragOrder.firstIndex(of: draggingID),
              let index = dragOrder.firstIndex(of: id)
        else { return 0 }
        if id == draggingID {
            guard let slotTop = layout.slotTop(of: id, order: dragOrder) else { return 0 }
            return fingerContentY - grabOffset - slotTop
        }
        let step = (layout.heights[draggingID] ?? 0) + layout.spacing
        return HomeReorderMath.displacement(index: index, source: source, target: targetIndex ?? source, step: step)
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

    /// Zielplatz aus der Mitte des gezogenen Widgets und den Plätzen der anderen beim Start.
    private func updateTarget() {
        guard let draggingID, let layout, let height = layout.heights[draggingID] else { return }
        let center = fingerContentY - grabOffset + height / 2
        guard let target = HomeReorderMath.targetIndex(
            order: dragOrder, frames: layout.frames(order: dragOrder), dragging: draggingID, draggedCenterY: center
        ), target != targetIndex
        else { return }
        targetIndex = target
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
        updateTarget()
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
