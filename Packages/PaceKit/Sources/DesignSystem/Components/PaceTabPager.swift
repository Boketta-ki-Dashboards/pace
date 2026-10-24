import PaceCore
import SwiftUI

/// Koordinatensystem der Seitenleiste (außerhalb des generischen Typs, damit die Messung ohne Typbezug auskommt).
private let paceTabPagerSpace = "pace.tab.pager"

/// Haupttabs nebeneinander in Tab-Reihenfolge, interaktiv per Wischen wechselbar (normales Paging): Die Seiten folgen
/// dem Finger – nach links wischen zeigt den nächsten Tab rechts, nach rechts den vorherigen. Zwischenzustände (z. B.
/// halb Rankings, halb Social) sind möglich, beim Loslassen entscheidet die native Paging-Logik nach Anteil und
/// Geschwindigkeit; Zurückziehen bricht den Wechsel ab. An Home und Profil endet die Reihe (Gummiband, keine Schleife).
/// Rechenregeln siehe ``PaceTabPaging``.
///
/// - Vertikales Scrollen in den Seiten bleibt unberührt (UIKit unterscheidet die Richtungen verschachtelter
///   Scrollansichten selbst).
/// - `isPagingEnabled == false` (Unterseite offen, Anpassen-Modus, Tastatur): kein Wischen – die native Zurück-Geste
///   der Unterseiten bleibt frei.
/// - Seiten bleiben erhalten (kein Lazy-Stack), damit Navigation, Scrollposition und ViewModels nicht verloren gehen.
/// - Tastatur: Eine Scrollansicht verbraucht die Tastatur als eigenen Scroll-Abstand und gibt sie nicht an ihre Inhalte
///   weiter – bei der waagerechten Seitenleiste blieben Eingabefelder (z. B. die Chat-Eingabe) dadurch unter der
///   Tastatur. Die Leiste ignoriert die Tastatur deshalb selbst und gibt deren Höhe (aus der Safe Area gemessen, ohne
///   feste Werte) jeder Seite als untere Safe Area weiter: Inhalte enden direkt über der Tastatur.
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
    /// Wie weit die Tastatur die Seitenleiste von unten überdeckt (0 ohne Tastatur).
    @State private var keyboardOverlap: CGFloat = 0
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
                ForEach(tabs, id: \.self) { tab in
                    page(tab)
                        .safeAreaPadding(.bottom, keyboardOverlap)
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
        .ignoresSafeArea(.keyboard)
        .background {
            PaceKeyboardOverlapReader { overlap in
                guard abs(overlap - keyboardOverlap) > 0.5 else { return }
                // Ein- und Ausblenden gleitet mit; Zwischenstände (z. B. Vorschlagsleiste) folgen direkt.
                let animates = (overlap == 0 || keyboardOverlap == 0) && !reduceMotion
                withAnimation(animates ? .easeOut(duration: 0.25) : nil) {
                    keyboardOverlap = overlap
                }
            }
        }
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

/// Misst, wie weit die Tastatur einen Bereich von unten überdeckt: untere Safe Area mit Tastatur minus untere Safe
/// Area ohne Tastatur (so zählen Home-Indikator und Ähnliches nicht mit).
struct PaceKeyboardOverlapReader: View {
    let onChange: (CGFloat) -> Void

    @State private var withKeyboard: CGFloat = 0
    @State private var withoutKeyboard: CGFloat = 0

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.bottom
            } action: { inset in
                withKeyboard = inset
                onChange(max(inset - withoutKeyboard, 0))
            }
            .background {
                Color.clear
                    .ignoresSafeArea(.keyboard)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.safeAreaInsets.bottom
                    } action: { inset in
                        withoutKeyboard = inset
                        onChange(max(withKeyboard - inset, 0))
                    }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
