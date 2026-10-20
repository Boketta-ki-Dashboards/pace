import DesignSystem
import PaceCore
import SwiftUI

/// Wie ein Widget gezeigt wird.
enum HomeWidgetMode: Equatable {
    /// Normal auf Home: Inhalte sind antippbar.
    case normal
    /// Anpassen-Modus: eigener Kopf mit „Größe auswählen“ und Ziehgriff, Inhalte nicht antippbar.
    case editing
    /// Vorschau in der Widget-Galerie: sieht aus wie auf Home, ist aber nicht antippbar.
    case preview

    var isInteractive: Bool {
        self == .normal
    }
}

/// Kopfzeile eines Widgets auf Home: Titel links (darf umbrechen), rechts eine Aktion oder ein Pfeil.
struct HomeWidgetTitleRow<Trailing: View>: View {
    let title: String
    private let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaceSpacing.xs) {
            // 17 pt wie in den Referenzen (Bild 6 und 9), damit z. B. „Deine Schritte heute“ neben „Tagesziel ändern“
            // in eine Zeile passt; längere Titel (Russisch) dürfen zweizeilig werden.
            Text(title)
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(PaceColor.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: PaceSpacing.xs)
            trailing
        }
    }
}

extension HomeWidgetTitleRow where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// Pfeil rechts in einer Kopfzeile.
struct HomeChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.body.weight(.semibold))
            .foregroundStyle(PaceColor.textPrimary)
            .accessibilityHidden(true)
    }
}

/// Kleiner Pfeil am Ende einer Zeile.
struct HomeRowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(PaceColor.textSecondary)
            .accessibilityHidden(true)
    }
}

/// Ziehgriff aus sechs Punkten (zwei Spalten, drei Zeilen) – wie im Anpassen-Design.
struct HomeDragHandle: View {
    var dotSize: CGFloat = 4.5
    var color: Color = PaceColor.textSecondary

    var body: some View {
        HStack(spacing: dotSize * 0.9) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: dotSize * 0.9) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(color)
                            .frame(width: dotSize, height: dotSize)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Kennzahl mit Beschriftung, z. B. „Rekord · 12 Tage“.
struct HomeStatTile: View {
    let title: String
    let value: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: PaceSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 22)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.headline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PaceSpacing.s)
        .padding(.vertical, PaceSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaceColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Hinweis innerhalb eines Widgets (Leerzustand, fehlende Daten).
struct HomeWidgetHint: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaceSpacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(PaceColor.accent)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(PaceFont.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Ladezustand innerhalb eines Widgets.
struct HomeWidgetLoading: View {
    var minHeight: CGFloat = 60

    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .accessibilityLabel(HomeTexts.loading)
    }
}

/// Einfaches Balkendiagramm mit Beschriftung unter jedem Balken (Woche, Aktivität, Umfeld, Freunde).
struct HomeBarChart: View {
    struct Bar: Identifiable {
        let id: String
        let label: String
        /// 0…1
        let level: Double
        var valueText: String?
        var isHighlighted = false
        /// Fehlender Wert (z. B. Zukunft): gestrichelter Platzhalter.
        var isEmpty = false
    }

    let bars: [Bar]
    var height: CGFloat = 96
    var showsValues = false

    var body: some View {
        HStack(alignment: .bottom, spacing: PaceSpacing.xs) {
            ForEach(bars) { bar in
                VStack(spacing: PaceSpacing.xxs) {
                    if showsValues {
                        Text(bar.valueText ?? " ")
                            .font(PaceFont.micro)
                            .monospacedDigit()
                            .foregroundStyle(bar.isHighlighted ? PaceColor.textPrimary : PaceColor.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Group {
                        if bar.isEmpty {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(PaceColor.border, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .frame(height: 10)
                        } else {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(bar.isHighlighted ? PaceColor.accentStrong : PaceColor.chartLow)
                                .frame(height: max(6, height * min(max(bar.level, 0), 1)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Text(bar.label)
                        .font(PaceFont.caption)
                        .fontWeight(bar.isHighlighted ? .bold : .regular)
                        .foregroundStyle(bar.isHighlighted ? PaceColor.textPrimary : PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height + (showsValues ? 42 : 24), alignment: .bottom)
        .accessibilityHidden(true)
    }
}
