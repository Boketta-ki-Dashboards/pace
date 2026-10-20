import DesignSystem
import PaceCore
import SocialFeature
import SwiftUI

/// Freunde-Ranking: du und die ausgewählten Freunde (oder alle), heute.
///
/// - Klein: Platz 1 der Auswahl.
/// - Mittel: drei Zeilen. Groß: fünf Zeilen (du bist immer dabei).
/// - Max: Diagramm der Auswahl und fünf Zeilen.
struct FriendsWidgetContent: View {
    let widget: HomeFriendsWidget
    let state: SocialViewModel.State
    let size: HomeModuleSize
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
                        name: first.entry.displayName,
                        seed: first.entry.publicUserID.uuidString,
                        size: 44,
                        isHighlighted: first.entry.isCurrentUser,
                        image: first.entry.avatar
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(first.entry.isCurrentUser ? HomeTexts.you : first.entry.displayName)
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
                    Text(verbatim: "#1")
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(PaceColor.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowLabel(first))
        } else {
            if size == .max {
                HomeBarChart(
                    bars: widget.chartRows.map { row in
                        HomeBarChart.Bar(
                            id: row.id.uuidString,
                            label: row.entry.isCurrentUser ? HomeTexts.you : row.entry.displayName,
                            level: Double(row.entry.competitionSteps) / Double(max(widget.chartRows.first?.entry.competitionSteps ?? 1, 1)),
                            valueText: row.entry.competitionSteps.paceFormatted,
                            isHighlighted: row.entry.isCurrentUser
                        )
                    },
                    height: 80
                )
                .padding(.bottom, PaceSpacing.xxs)
            }
            ForEach(widget.rows(for: size)) { row in
                Button(action: onOpenSocial) {
                    PaceRankingRow(
                        rank: row.rank,
                        name: row.entry.isCurrentUser ? HomeTexts.you : row.entry.displayName,
                        steps: row.entry.competitionSteps,
                        seed: row.entry.publicUserID.uuidString,
                        image: row.entry.avatar,
                        isCurrentUser: row.entry.isCurrentUser,
                        showsStepIcon: true,
                        showsChevron: false
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

    private func rowLabel(_ row: HomeFriendsWidget.Row) -> String {
        PaceLocalization.text(de: "Platz \(row.rank)", en: "Rank \(row.rank)", ru: "Место \(row.rank)")
            + ", " + (row.entry.isCurrentUser ? HomeTexts.you : row.entry.displayName)
            + ", " + PaceLocalization.steps(row.entry.competitionSteps)
    }
}
