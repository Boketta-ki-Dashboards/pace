import DesignSystem
import PaceCore
import SwiftUI

/// „Deine Positionen in der Region“: die regionalen Karten – in jeder Größe in einer Reihe (nie 2 × 2).
///
/// - Klein: eine schmale Leiste mit Platz und Ebene.
/// - Mittel: die vier Karten wie im Home-Design (Symbol, Ebene, Platz, Gebiet).
/// - Groß: die Karten mit Abstand zum nächsten Platz.
/// - Max: zusätzlich je Ebene der ausführliche Aufstiegshinweis.
struct RegionRanksWidgetContent: View {
    let cards: [HomeRegionCard]
    let size: HomeModuleSize
    let isLoading: Bool
    let isInteractive: Bool
    let onSelect: (Region?) -> Void

    var body: some View {
        switch size {
        case .small:
            compactStrip
        case .medium:
            cardRow(showsGap: false)
        case .large:
            cardRow(showsGap: true)
        case .max:
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                cardRow(showsGap: true)
                hintList
            }
        }
    }

    private func cardRow(showsGap: Bool) -> some View {
        HStack(alignment: .top, spacing: PaceSpacing.xs) {
            ForEach(cards) { card in
                Button {
                    onSelect(card.rankingRegion)
                } label: {
                    RegionRankCard(card: card, isLoading: isLoading, showsGap: showsGap, showsChevron: isInteractive)
                }
                .buttonStyle(.pacePressable)
                .accessibilityLabel(card.accessibilityLabel)
                .accessibilityHint(PaceLocalization.text(
                    de: "Öffnet das Ranking", en: "Opens the ranking", ru: "Открывает рейтинг"
                ))
            }
        }
    }

    private var compactStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                if index > 0 {
                    Divider().frame(height: 30)
                }
                Button {
                    onSelect(card.rankingRegion)
                } label: {
                    VStack(spacing: 1) {
                        Text(isLoading ? "…" : card.rankText)
                            .font(.system(.headline, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(card.title)
                            .font(PaceFont.micro)
                            .foregroundStyle(PaceColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                .accessibilityLabel(card.accessibilityLabel)
            }
        }
        .padding(.vertical, PaceSpacing.xs)
        .padding(.horizontal, PaceSpacing.xxs)
        .frame(maxWidth: .infinity)
        .paceCardBackground(cornerRadius: 16)
    }

    private var hintList: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            ForEach(cards) { card in
                HStack(alignment: .firstTextBaseline, spacing: PaceSpacing.xs) {
                    Image(systemName: RegionRankCard.icon(for: card.level))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PaceColor.accent)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(card.name.isEmpty ? card.title : card.name)
                        .font(PaceFont.callout.weight(.semibold))
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: PaceSpacing.xs)
                    Text(card.nextPlaceText ?? card.rankText)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(PaceSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paceCardBackground(cornerRadius: 16)
    }
}

/// Eine regionale Karte: Symbol mit Pfeil, Ebene, Platz, Gebiet – lange Namen brechen um statt abgeschnitten zu werden.
struct RegionRankCard: View {
    let card: HomeRegionCard
    var isLoading = false
    var showsGap = false
    var showsChevron = true

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: Self.icon(for: card.level))
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(PaceColor.textSecondary)
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                }
            // Ebenen sind einzelne Wörter („Bundesland“, „Landkreis“): verkleinern statt mitten im Wort trennen.
            Text(card.title)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(card.title.contains(" ") ? 2 : 1)
                .minimumScaleFactor(0.65)
            Text(isLoading ? "…" : card.rankText)
                .font(.system(.headline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(PaceColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(card.name)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .multilineTextAlignment(.center)
                // Zusammengesetzte Namen („Darmstadt-Dieburg“) dürfen zweizeilig werden, ein einzelnes langes Wort
                // („Deutschland“) wird leicht verkleinert statt getrennt.
                .lineLimit(isSingleWord ? 1 : 2)
                .minimumScaleFactor(isSingleWord ? 0.65 : 0.85)
                .frame(minHeight: 34, alignment: .top)
            if showsGap {
                Text(card.nextPlaceShortText ?? " ")
                    .font(PaceFont.micro)
                    .foregroundStyle(PaceColor.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, PaceSpacing.xs)
        .padding(.vertical, PaceSpacing.s)
        .frame(maxWidth: .infinity)
        .paceCardBackground(cornerRadius: 16)
    }

    private var isSingleWord: Bool {
        !card.name.contains(" ") && !card.name.contains("-")
    }

    static func icon(for level: RegionLevel) -> String {
        switch level {
        case .municipality: "building.2"
        case .district: "map"
        case .state: "shield"
        case .country: "globe"
        }
    }
}

/// Neutrale Karten ohne Werte – Grundlage für „Ranking ausgeschaltet“ (keine echten Plätze, keine Namen).
struct RegionRanksPlaceholder: View {
    let levels: [RegionLevel]

    var body: some View {
        HStack(alignment: .top, spacing: PaceSpacing.xs) {
            ForEach(levels, id: \.self) { level in
                VStack(spacing: 6) {
                    Image(systemName: RegionRankCard.icon(for: level))
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(PaceColor.textSecondary)
                        .frame(height: 30)
                    PacePlaceholderBar(width: 44, height: 9)
                    PacePlaceholderBar(width: 36, height: 14)
                    PacePlaceholderBar(width: 54, height: 9)
                }
                .padding(.vertical, PaceSpacing.s)
                .frame(maxWidth: .infinity)
                .paceCardBackground(cornerRadius: 16)
            }
        }
        .accessibilityHidden(true)
    }
}
