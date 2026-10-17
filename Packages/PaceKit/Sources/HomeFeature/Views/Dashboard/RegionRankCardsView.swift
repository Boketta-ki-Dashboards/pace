import DesignSystem
import PaceCore
import SwiftUI

/// Vier (bzw. zwei bis drei) Karten mit der eigenen Platzierung je Ebene: Stadt, Landkreis, Bundesland, Land.
struct RegionRankCardsView: View {
    let standings: RegionalStandingsViewModel
    let onSelect: (Region) -> Void

    var body: some View {
        let scopes = displayedScopes
        HStack(spacing: PaceSpacing.xs) {
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
                    .accessibilityLabel("\(scope.levelTitle) \(scope.region.name), Platz \(scope.rank.map(String.init) ?? "nicht platziert")")
                }
            }
        }
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
                .font(.system(.headline, weight: .bold))
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
                .lineLimit(isSingleWord ? 1 : 2)
                .minimumScaleFactor(isSingleWord ? 0.65 : 0.8)
                .frame(minHeight: 34, alignment: .top)
        }
        .padding(.horizontal, PaceSpacing.xs)
        .padding(.vertical, PaceSpacing.s)
        .frame(maxWidth: .infinity)
        .paceCardBackground(cornerRadius: 16)
    }
}
