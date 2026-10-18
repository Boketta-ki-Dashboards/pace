import DesignSystem
import PaceCore
import SwiftUI

/// Vier (bzw. zwei bis drei) Karten mit der eigenen Platzierung je Ebene: Stadt, Landkreis, Bundesland, Land.
///
/// Klein: eine Zeile mit allen Plätzen. Mittel: vier Karten nebeneinander. Groß: 2 × 2 Karten mit vollen Namen.
struct RegionRankCardsView: View {
    let standings: RegionalStandingsViewModel
    var size: HomeModuleSize = .medium
    let onSelect: (Region) -> Void

    var body: some View {
        switch size {
        case .small: compactRow
        case .medium: cards
        case .large: grid
        }
    }

    private var cards: some View {
        let scopes = displayedScopes
        return HStack(spacing: PaceSpacing.xs) {
            if scopes.isEmpty {
                ForEach(0..<4, id: \.self) { _ in
                    RankCard(icon: "circle.dotted", title: " ", rank: "–", name: " ")
                        .redacted(reason: .placeholder)
                }
            } else {
                ForEach(scopes) { scope in
                    Button {
                        onSelect(scope.region)
                    } label: {
                        RankCard(
                            icon: Self.icon(for: scope.region.level),
                            title: scope.levelTitle,
                            rank: isLoading ? "…" : scope.rankText,
                            name: scope.region.name
                        )
                    }
                    .buttonStyle(.pacePressable)
                    .accessibilityLabel(accessibilityLabel(for: scope))
                }
            }
        }
    }

    private var grid: some View {
        let columns = [GridItem(.flexible(), spacing: PaceSpacing.xs), GridItem(.flexible(), spacing: PaceSpacing.xs)]
        return LazyVGrid(columns: columns, spacing: PaceSpacing.xs) {
            ForEach(displayedScopes) { scope in
                Button {
                    onSelect(scope.region)
                } label: {
                    RankCard(
                        icon: Self.icon(for: scope.region.level),
                        title: scope.levelTitle,
                        rank: isLoading ? "…" : scope.rankText,
                        name: scope.region.name,
                        isLarge: true
                    )
                }
                .buttonStyle(.pacePressable)
                .accessibilityLabel(accessibilityLabel(for: scope))
            }
        }
    }

    private var compactRow: some View {
        PaceCard(padding: PaceSpacing.s) {
            HStack(spacing: 0) {
                ForEach(Array(displayedScopes.enumerated()), id: \.element.id) { index, scope in
                    if index > 0 {
                        Divider().frame(height: 28)
                    }
                    Button {
                        onSelect(scope.region)
                    } label: {
                        VStack(spacing: 0) {
                            Text(isLoading ? "…" : scope.rankText)
                                .font(.system(.headline, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(PaceColor.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(scope.levelTitle)
                                .font(PaceFont.micro)
                                .foregroundStyle(PaceColor.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pacePressable)
                    .accessibilityLabel(accessibilityLabel(for: scope))
                }
            }
        }
    }

    private func accessibilityLabel(for scope: RegionalStandings.Scope) -> String {
        "\(scope.levelTitle) \(scope.region.name), Platz \(scope.rank.map(String.init) ?? "nicht platziert")"
    }

    private var isLoading: Bool {
        standings.state == .loading || standings.state == .idle
    }

    /// Geladene Platzierungen oder – solange sie fehlen – die Ebenen ohne Platz.
    private var displayedScopes: [RegionalStandings.Scope] {
        if let loaded = standings.standings {
            return loaded.scopes
        }
        return standings.scopes.map { RegionalStandings.Scope(region: $0, rank: nil) }
    }

    static func icon(for level: RegionLevel) -> String {
        switch level {
        case .municipality: "building.2"
        case .district: "map"
        case .state: "flag"
        case .country: "globe.europe.africa"
        }
    }
}

private struct RankCard: View {
    let icon: String
    let title: String
    let rank: String
    let name: String
    var isLarge = false

    private var isSingleWord: Bool {
        !name.contains(" ") && !name.contains("-")
    }

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(PaceColor.textPrimary)
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                }
            Text(title)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(rank)
                .font(.system(isLarge ? .title2 : .headline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(PaceColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(name)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .multilineTextAlignment(.center)
                // Ein einzelnes Wort („Deutschland“) wird verkleinert statt getrennt, zusammengesetzte Namen
                // („Darmstadt-Dieburg“) dürfen zweizeilig sein.
                .lineLimit(isSingleWord && !isLarge ? 1 : 2)
                .minimumScaleFactor(isSingleWord ? 0.65 : 0.8)
                .frame(minHeight: 34, alignment: .top)
        }
        .padding(.horizontal, PaceSpacing.xs)
        .padding(.vertical, PaceSpacing.s)
        .frame(maxWidth: .infinity)
        .paceCardBackground(cornerRadius: 16)
    }
}
