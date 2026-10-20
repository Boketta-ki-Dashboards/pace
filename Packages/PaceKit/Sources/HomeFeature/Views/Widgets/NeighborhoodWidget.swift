import DesignSystem
import PaceCore
import SwiftUI

/// Ranking-Umfeld einer Ebene („Pfungstadt · Dein Umfeld“): die Plätze um deinen und der Abstand zum nächsten Platz –
/// aus den echten Wettbewerbsschritten.
///
/// - Klein: dein Platz und der Abstand.
/// - Mittel: drei Zeilen. Groß: fünf Zeilen.
/// - Max: Diagramm mit bis zu sieben Plätzen.
struct NeighborhoodWidgetContent: View {
    let standings: RegionalStandingsViewModel
    let level: RegionLevel
    let size: HomeModuleSize
    let rows: Int
    let onOpenRankings: (Region?) -> Void

    var body: some View {
        switch standings.state {
        case .idle, .loading:
            if let neighborhood = standings.standings?.neighborhood(for: shownLevel, rows: rows) {
                loaded(neighborhood)
            } else {
                HomeWidgetLoading(minHeight: size == .small ? 44 : 80)
            }
        case .failed(let message):
            HomeWidgetHint(systemImage: "arrow.clockwise", text: message)
        case .loaded(let loaded):
            if let neighborhood = loaded.neighborhood(for: shownLevel, rows: rows) {
                self.loaded(neighborhood)
            } else {
                HomeWidgetHint(
                    systemImage: "figure.walk",
                    text: PaceLocalization.text(
                        de: "Sobald deine heutigen Schritte synchronisiert sind, siehst du hier, wer vor und hinter dir liegt.",
                        en: "Once today's steps are synced, you'll see who is right ahead of and behind you.",
                        ru: "Когда сегодняшние шаги синхронизируются, здесь появится, кто впереди и позади тебя."
                    )
                )
            }
        }
    }

    /// Gibt es die gewählte Ebene für die Region nicht (z. B. Kreis bei einer kreisfreien Stadt), die nächst kleinere.
    private var shownLevel: RegionLevel {
        standings.effectiveLevel(for: level)
    }

    @ViewBuilder
    private func loaded(_ neighborhood: RegionalStandings.Neighborhood) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            switch size {
            case .small:
                Button {
                    onOpenRankings(neighborhood.region)
                } label: {
                    HStack(spacing: PaceSpacing.s) {
                        Text(verbatim: "#\(neighborhood.currentUser.rank.paceFormatted)")
                            .font(.system(.title2, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(PaceColor.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(neighborhood.footerText.isEmpty ? PaceLocalization.steps(neighborhood.currentUser.competitionSteps) : neighborhood.footerText)
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        HomeRowChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
            case .medium, .large:
                ForEach(neighborhood.entries) { entry in
                    Button {
                        onOpenRankings(neighborhood.region)
                    } label: {
                        PaceRankingRow(
                            rank: entry.rank,
                            name: entry.isCurrentUser ? HomeTexts.you : entry.displayName,
                            steps: entry.competitionSteps,
                            seed: entry.publicUserID.uuidString,
                            image: entry.avatar,
                            isCurrentUser: entry.isCurrentUser
                        )
                    }
                    .buttonStyle(.pacePressable)
                }
                footer(neighborhood)
            case .max:
                Button {
                    onOpenRankings(neighborhood.region)
                } label: {
                    HomeBarChart(
                        bars: neighborhood.entries.map { entry in
                            HomeBarChart.Bar(
                                id: entry.publicUserID.uuidString,
                                label: entry.isCurrentUser ? HomeTexts.you : entry.displayName,
                                level: Double(entry.competitionSteps) / Double(max(neighborhood.entries.map(\.competitionSteps).max() ?? 1, 1)),
                                valueText: entry.competitionSteps.paceFormatted,
                                isHighlighted: entry.isCurrentUser
                            )
                        },
                        height: 110,
                        showsValues: true
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(neighborhood.entries.map { entry in
                    PaceLocalization.text(
                        de: "Platz \(entry.rank.paceFormatted)", en: "Rank \(entry.rank.paceFormatted)", ru: "Место \(entry.rank.paceFormatted)"
                    ) + ", " + (entry.isCurrentUser ? HomeTexts.you : entry.displayName) + ", " + PaceLocalization.steps(entry.competitionSteps)
                }.joined(separator: "; "))
                footer(neighborhood)
            }
        }
    }

    @ViewBuilder
    private func footer(_ neighborhood: RegionalStandings.Neighborhood) -> some View {
        if !neighborhood.footerText.isEmpty {
            Text(neighborhood.footerText)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, PaceSpacing.xxs)
        }
    }
}

/// Neutrale Zeilen ohne Namen und Werte – Grundlage für „Ranking ausgeschaltet“.
struct NeighborhoodPlaceholder: View {
    var rows = 3

    var body: some View {
        VStack(spacing: PaceSpacing.xs) {
            ForEach(0..<rows, id: \.self) { index in
                HStack(spacing: PaceSpacing.s) {
                    PacePlaceholderBar(width: 34, height: 14)
                    Circle()
                        .fill(PaceColor.track)
                        .frame(width: 36, height: 36)
                    PacePlaceholderBar(width: index == 1 ? 60 : 90, height: 12)
                    Spacer(minLength: PaceSpacing.xs)
                    PacePlaceholderBar(width: 54, height: 12)
                }
                .padding(.horizontal, PaceSpacing.s)
                .frame(minHeight: 52)
                .background(
                    index == 1 ? PaceColor.accentSoft : PaceColor.surfaceSecondary,
                    in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                        .strokeBorder(PaceColor.border, lineWidth: 1)
                )
            }
        }
        .accessibilityHidden(true)
    }
}
