import DesignSystem
import PaceCore
import SocialFeature
import SwiftUI

/// Freunde-Ranking: du und die ausgewählten Freunde (oder alle), heute.
///
/// - Klein: Platz 1 der Auswahl.
/// - Mittel: drei Zeilen. Groß: fünf Zeilen (du bist immer dabei).
/// - Max: Diagramm der Auswahl und fünf Zeilen.
///
/// Wählbar (``HomeWidgetDetail``): Abstand zum Platz davor je Zeile, Diagramm ab „Groß“ (Standard: nur bei Max).
struct FriendsWidgetContent: View {
    let widget: HomeFriendsWidget
    let state: SocialViewModel.State
    let size: HomeModuleSize
    var details: [HomeWidgetDetail] = []
    let onOpenSocial: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            switch state {
            case .unavailable(let message):
                HomeWidgetHint(systemImage: "person.2", text: message)
            case .failed(let message) where widget.allRows.isEmpty:
                HomeWidgetHint(systemImage: "arrow.clockwise", text: message)
            case .idle:
                HomeWidgetLoading(minHeight: size == .small ? 44 : 60)
            case .loading where widget.allRows.isEmpty:
                HomeWidgetLoading(minHeight: size == .small ? 44 : 60)
            default:
                if widget.hasFriends {
                    rows
                } else {
                    emptyState
                }
            }
            if let missing = widget.missingText {
                Label(missing, systemImage: "person.crop.circle.badge.questionmark")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        if size == .small, let first = widget.rows(for: .small).first {
            Button(action: onOpenSocial) {
                HStack(spacing: PaceSpacing.s) {
                    PaceAvatar(
                        name: first.entry.shownName,
                        seed: first.entry.publicUserID.uuidString,
                        size: 44,
                        isHighlighted: first.entry.isCurrentUser,
                        image: first.entry.avatar
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(first.entry.isCurrentUser ? HomeTexts.you : first.entry.shownName)
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Label(first.entry.competitionSteps.paceFormatted, systemImage: "shoeprints.fill")
                            .font(.system(.subheadline, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(verbatim: "#\(first.rank.paceFormatted)")
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(PaceColor.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowLabel(first))
        } else {
            if details.contains(.friendChart) {
                HomeBarChart(bars: chartBars, height: 80)
                    .padding(.bottom, PaceSpacing.xxs)
            }
            ForEach(widget.rows(for: size)) { row in
                Button(action: onOpenSocial) {
                    PaceRankingRow(
                        rank: row.rank,
                        name: row.entry.isCurrentUser ? HomeTexts.you : row.entry.shownName,
                        steps: row.entry.competitionSteps,
                        seed: row.entry.publicUserID.uuidString,
                        image: row.entry.avatar,
                        isCurrentUser: row.entry.isCurrentUser,
                        showsStepIcon: true,
                        showsChevron: false,
                        detail: details.contains(.friendGap) ? widget.gapText(for: row) : nil
                    )
                }
                .buttonStyle(.pacePressable)
            }
        }
    }

    private var emptyState: some View {
        Button(action: onOpenSocial) {
            HStack(spacing: PaceSpacing.m) {
                Image(systemName: "person.2")
                    .font(.title3)
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 48, height: 48)
                    .background(PaceColor.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(widget.isAllFriends
                        ? PaceLocalization.text(de: "Noch keine Freunde", en: "No friends yet", ru: "Пока нет друзей")
                        : PaceLocalization.text(de: "Niemand ausgewählt", en: "Nobody selected", ru: "Никто не выбран"))
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                    Text(PaceLocalization.text(
                        de: "Füge im Social-Tab Freunde hinzu und vergleicht euch jeden Tag.",
                        en: "Add friends in the Social tab and compare yourselves every day.",
                        ru: "Добавь друзей во вкладке «Друзья» и сравнивайте шаги каждый день."
                    ))
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
    }

    private var chartBars: [HomeBarChart.Bar] {
        let rows = widget.chartRows
        let maximum = Double(max(rows.map(\.entry.competitionSteps).max() ?? 1, 1))
        return rows.map { row in
            HomeBarChart.Bar(
                id: row.id.uuidString,
                label: row.entry.isCurrentUser ? HomeTexts.you : row.entry.shownName,
                level: Double(row.entry.competitionSteps) / maximum,
                valueText: row.entry.competitionSteps.paceFormatted,
                isHighlighted: row.entry.isCurrentUser
            )
        }
    }

    private func rowLabel(_ row: HomeFriendsWidget.Row) -> String {
        let rank = row.rank.paceFormatted
        let place = PaceLocalization.text(de: "Platz \(rank)", en: "Rank \(rank)", ru: "Место \(rank)")
        let name = row.entry.isCurrentUser ? HomeTexts.you : row.entry.shownName
        return [place, name, PaceLocalization.steps(row.entry.competitionSteps)].joined(separator: ", ")
    }
}
