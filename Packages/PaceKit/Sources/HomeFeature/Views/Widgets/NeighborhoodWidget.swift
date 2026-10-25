import DesignSystem
import PaceCore
import SwiftUI

/// Ranking-Umfeld einer Ebene („Pfungstadt · Dein Umfeld“): die Plätze um deinen und der Abstand zum nächsten Platz –
/// aus den echten Wettbewerbsschritten.
///
/// - Klein: dein Platz und der Abstand.
/// - Mittel: drei Zeilen. Groß: fünf Zeilen.
/// - Max: Diagramm mit bis zu sieben Plätzen.
///
/// Der Abstand zum nächsten Platz lässt sich ausblenden (``HomeWidgetDetail/rankGap``); klein steht dann die eigene
/// Schrittzahl neben dem Platz.
struct NeighborhoodWidgetContent: View {
    let standings: RegionalStandingsViewModel
    let level: RegionLevel
    let size: HomeModuleSize
    let rows: Int
    var showsGap = true
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
                        Text(!showsGap || neighborhood.footerText.isEmpty
                            ? PaceLocalization.steps(neighborhood.currentUser.competitionSteps)
                            : neighborhood.footerText)
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
                            name: entry.isCurrentUser ? HomeTexts.you : entry.shownName,
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
                    HomeBarChart(bars: bars(neighborhood), height: 110, showsValues: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chartAccessibilityLabel(neighborhood))
                footer(neighborhood)
            }
        }
    }

    private func bars(_ neighborhood: RegionalStandings.Neighborhood) -> [HomeBarChart.Bar] {
        let maximum = Double(max(neighborhood.entries.map(\.competitionSteps).max() ?? 1, 1))
        return neighborhood.entries.map { entry in
            HomeBarChart.Bar(
                id: entry.publicUserID.uuidString,
                label: entry.isCurrentUser ? HomeTexts.you : entry.shownName,
                level: Double(entry.competitionSteps) / maximum,
                valueText: entry.competitionSteps.paceFormatted,
                isHighlighted: entry.isCurrentUser
            )
        }
    }

    /// VoiceOver: alle Plätze des Diagramms, z. B. „Platz 12, DU, 8.432 Schritte; …“.
    private func chartAccessibilityLabel(_ neighborhood: RegionalStandings.Neighborhood) -> String {
        neighborhood.entries.map { entry -> String in
            let rank = entry.rank.paceFormatted
            let place = PaceLocalization.text(de: "Platz \(rank)", en: "Rank \(rank)", ru: "Место \(rank)")
            let name = entry.isCurrentUser ? HomeTexts.you : entry.shownName
            return [place, name, PaceLocalization.steps(entry.competitionSteps)].joined(separator: ", ")
        }
        .joined(separator: "; ")
    }

    @ViewBuilder
    private func footer(_ neighborhood: RegionalStandings.Neighborhood) -> some View {
        if showsGap, !neighborhood.footerText.isEmpty {
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
