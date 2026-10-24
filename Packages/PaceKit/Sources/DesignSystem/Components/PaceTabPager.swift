import PaceCore
import SwiftUI

/// Koordinatensystem der Seitenleiste (außerhalb des generischen Typs, damit die Messung ohne Typbezug auskommt).
private let paceTabPagerSpace = "pace.tab.pager"

/// Haupttabs nebeneinander, interaktiv per Wischen wechselbar (wie die Seiten-Navigation in Spielen): Die Seiten
/// folgen dem Finger, Zwischenzustände (z. B. halb Rankings, halb Social) sind möglich, beim Loslassen entscheidet die
/// native Paging-Logik nach Anteil und Geschwindigkeit; Zurückziehen bricht den Wechsel ab. An Home und Profil endet
/// die Reihe (Gummiband, keine Schleife). Richtung siehe ``PaceTabPaging``.
///
/// - Vertikales Scrollen in den Seiten bleibt unberührt (UIKit unterscheidet die Richtungen verschachtelter
///   Scrollansichten selbst).
/// - `isPagingEnabled == false` (Unterseite offen, Anpassen-Modus, Tastatur): kein Wischen – die native Zurück-Geste
///   der Unterseiten bleibt frei.
/// - Seiten bleiben erhalten (kein Lazy-Stack), damit Navigation, Scrollposition und ViewModels nicht verloren gehen.
public struct PaceTabPager<Tab: Hashable, Page: View>: View {
    private let tabs: [Tab]
    @Binding private var selection: Tab
    private let isPagingEnabled: Bool
    private let onPositionChange: (Double) -> Void
    private let page: (Tab) -> Page

    @State private var scrolledID: Tab?
    @State private var pageWidth: CGFloat = 0
    /// Ziel eines Tabs, der über die Tab-Leiste gewählt wurde, solange die Seite noch dorthin gleitet (mit Zeitpunkt,
    /// damit ein unterbrochenes Gleiten die Auswahl nicht dauerhaft festhält).
    @State private var pendingTarget: (tab: Tab, since: Date)?
    @State private var lastPosition: Double?
    /// Startpunkt beim ersten Anzeigen: die Seite des anfangs gewählten Tabs (nicht immer Home).
    private let initialAnchor: UnitPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - onPositionChange: Laufende Position als Tab-Index mit Nachkommastellen (für die Tab-Leiste).
    public init(
        tabs: [Tab],
        selection: Binding<Tab>,
        isPagingEnabled: Bool,
        onPositionChange: @escaping (Double) -> Void,
        @ViewBuilder page: @escaping (Tab) -> Page
    ) {
        self.tabs = tabs
        _selection = selection
        self.isPagingEnabled = isPagingEnabled
        self.onPositionChange = onPositionChange
        self.page = page
        _scrolledID = State(initialValue: selection.wrappedValue)
        let index = tabs.firstIndex(of: selection.wrappedValue) ?? 0
        initialAnchor = UnitPoint(x: PaceTabPaging.initialAnchorX(index: index, count: tabs.count), y: 0.5)
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(PaceTabPaging.visualOrder(tabs), id: \.self) { tab in
                    page(tab)
                        .containerRelativeFrame(.horizontal)
                        .id(tab)
                }
            }
            .scrollTargetLayout()
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(paceTabPagerSpace)).minX
            } action: { minX in
                positionChanged(offset: -minX)
            }
        }
        .coordinateSpace(.named(paceTabPagerSpace))
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledID)
        .defaultScrollAnchor(initialAnchor)
        .scrollIndicators(.hidden)
        .scrollDisabled(!isPagingEnabled)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            pageWidth = width
        }
        .onChange(of: selection) { _, tab in
            let isAlreadyThere = lastPosition.flatMap { PaceTabPaging.settledIndex($0) } == tabs.firstIndex(of: tab)
            guard scrolledID != tab || !isAlreadyThere else { return }
            pendingTarget = isAlreadyThere ? nil : (tab, Date())
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) {
                scrolledID = tab
            }
        }
    }

    /// Meldet die Position und übernimmt einen per Wischen erreichten Tab, sobald die Seite ruht.
    private func positionChanged(offset: CGFloat) {
        guard let position = PaceTabPaging.position(offset: offset, pageWidth: pageWidth, count: tabs.count) else { return }
        lastPosition = position
        onPositionChange(position)
        guard let index = PaceTabPaging.settledIndex(position), tabs.indices.contains(index) else { return }
        let tab = tabs[index]
        if let pendingTarget {
            // Beim Gleiten über mehrere Seiten nicht an einer Zwischenseite hängen bleiben.
            if tab != pendingTarget.tab, Date().timeIntervalSince(pendingTarget.since) < 1 { return }
            self.pendingTarget = nil
        }
        if tab != selection {
            selection = tab
        }
    }
}
