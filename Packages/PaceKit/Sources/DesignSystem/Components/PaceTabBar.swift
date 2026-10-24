import PaceCore
import SwiftUI

/// Eintrag der Tab-Leiste.
public struct PaceTabItem<Value: Hashable>: Identifiable {
    public let value: Value
    public let title: String
    public let systemImage: String
    public let selectedSystemImage: String
    /// Zähler am Symbol (z. B. ungelesene Nachrichten); 0 blendet ihn aus.
    public let badge: Int

    public var id: Value { value }

    public init(value: Value, title: String, systemImage: String, selectedSystemImage: String, badge: Int = 0) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
        self.selectedSystemImage = selectedSystemImage
        self.badge = badge
    }
}

/// Untere Navigation von Pace. Der aktive Tab zeigt Symbol und Beschriftung gemeinsam in einer abgerundeten
/// Mint-Fläche (Light: zartes Mint mit dunkelgrünem Inhalt, Dark: Mint mit dunklem Inhalt).
///
/// Die Fläche gleitet: Mit `position` (Tab-Index mit Nachkommastellen, z. B. 1,5 beim Wischen zwischen Rankings und
/// Social) folgt sie dem Finger. Symbol und Beschriftung erscheinen in Akzentfarbe genau dort, wo die Fläche liegt –
/// beide bleiben so immer gemeinsam in der aktiven Fläche.
public struct PaceTabBar<Value: Hashable>: View {
    private let items: [PaceTabItem<Value>]
    @Binding private var selection: Value
    private let position: Double?
    private let onReselect: ((Value) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Höhe des Bereichs am unteren Rand mit Home-Indikator (0 bei iPhones mit Home-Taste).
    @State private var homeIndicatorInset: CGFloat = 0

    private static var spacing: CGFloat { PaceSpacing.xxs }

    /// So weit reicht die Leiste in den Bereich des Home-Indikators hinein: Unter den Beschriftungen bleibt weniger
    /// Leerraum, Symbole, Texte und Fläche bleiben gleich groß, der Indikator selbst bleibt frei (er sitzt in den
    /// untersten ~13 pt).
    static func bottomCompaction(forHomeIndicatorInset inset: CGFloat) -> CGFloat {
        inset > 0 ? min(14, inset / 2) : 0
    }

    /// - Parameters:
    ///   - position: Laufende Position beim Wischen; ohne Angabe die Auswahl.
    ///   - onReselect: Antippen des schon aktiven Tabs (z. B. nach oben scrollen).
    public init(
        items: [PaceTabItem<Value>],
        selection: Binding<Value>,
        position: Double? = nil,
        onReselect: ((Value) -> Void)? = nil
    ) {
        self.items = items
        _selection = selection
        self.position = position
        self.onReselect = onReselect
    }

    public var body: some View {
        row(selectedStyle: false)
            // Fläche und Akzent-Reihe liegen über der normalen Reihe; Antippen geht an die Buttons darunter.
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    let width = itemWidth(in: geometry.size.width)
                    let offset = highlightOffset(itemWidth: width)
                    ZStack(alignment: .topLeading) {
                        highlightShape
                            .fill(PaceColor.selectionFill)
                            .frame(width: width, height: geometry.size.height)
                            .offset(x: offset)
                        row(selectedStyle: true)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .mask(alignment: .topLeading) {
                                highlightShape
                                    .frame(width: width, height: geometry.size.height)
                                    .offset(x: offset)
                            }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .animation(position == nil && !reduceMotion ? .snappy(duration: 0.3) : nil, value: selectedIndex)
        .padding(.horizontal, PaceSpacing.s)
        .padding(.top, 6)
        // Nur unten kompakter: Ein Teil des Leerraums unter den Beschriftungen liegt jetzt im Bereich des
        // Home-Indikators (die Leiste wird insgesamt niedriger, die Inhalte darüber bekommen den Platz).
        .padding(.bottom, PaceSpacing.xxs - Self.bottomCompaction(forHomeIndicatorInset: homeIndicatorInset))
        // Große Schriftgrade würden die vier Beschriftungen sprengen; der Inhalt der Screens skaliert weiter.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .background {
            PaceColor.surface
                .overlay(alignment: .top) {
                    Rectangle().fill(PaceColor.border).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.safeAreaInsets.bottom
                } action: { inset in
                    homeIndicatorInset = inset
                }
        }
    }

    // MARK: Fläche

    private var highlightShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    private var selectedIndex: Int {
        items.firstIndex { $0.value == selection } ?? 0
    }

    private func itemWidth(in rowWidth: CGFloat) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        return max(0, (rowWidth - Self.spacing * CGFloat(items.count - 1)) / CGFloat(items.count))
    }

    private func highlightOffset(itemWidth: CGFloat) -> CGFloat {
        let index = min(max(position ?? Double(selectedIndex), 0), Double(max(items.count - 1, 0)))
        return CGFloat(index) * (itemWidth + Self.spacing)
    }

    // MARK: Einträge

    /// Eine Reihe aller Einträge – unten normal (mit Buttons), oben in Akzentfarbe (nur sichtbar in der Fläche).
    private func row(selectedStyle: Bool) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(items) { item in
                if selectedStyle {
                    label(item, selectedStyle: true)
                } else {
                    let isSelected = item.value == selection
                    Button {
                        if item.value == selection {
                            onReselect?(item.value)
                        } else {
                            selection = item.value
                        }
                    } label: {
                        label(item, selectedStyle: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(item.badge > 0 ? TabBadge.accessibilityText(item.badge) : "")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
    }

    private func label(_ item: PaceTabItem<Value>, selectedStyle: Bool) -> some View {
        VStack(spacing: 1) {
            Image(systemName: selectedStyle ? item.selectedSystemImage : item.systemImage)
                .font(.system(size: 20, weight: .medium))
                .frame(height: 24)
                .overlay(alignment: .topTrailing) {
                    if item.badge > 0 {
                        TabBadge(count: item.badge)
                            .offset(x: 12, y: -4)
                    }
                }
            Text(item.title)
                .font(.system(size: 13, weight: selectedStyle ? .bold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(selectedStyle ? PaceColor.onSelection : PaceColor.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }
}

/// Kleiner Zähler am Tab-Symbol.
private struct TabBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: count > 99 ? "99+" : count.paceFormatted)
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(PaceColor.onAccent)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(PaceColor.actionFill, in: Capsule())
            .overlay(Capsule().strokeBorder(PaceColor.surface, lineWidth: 1.5))
            .fixedSize()
            .accessibilityHidden(true)
    }

    static func accessibilityText(_ count: Int) -> String {
        PaceLocalization.plural(
            count,
            de: ("\(count) ungelesen", "\(count) ungelesen"),
            en: ("\(count) unread", "\(count) unread"),
            ru: ("\(count) непрочитанное", "\(count) непрочитанных", "\(count) непрочитанных")
        )
    }
}
