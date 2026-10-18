import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

/// „Deine Serie“: Tage in Folge mit erreichtem Tagesziel, mit Flamme.
///
/// Klein: Flamme und Zahl. Mittel: dazu Status, Rekord und die letzten 7 Tage. Groß: die letzten 4 Wochen.
struct StreakCardView: View {
    let summary: StreakSummary?
    let state: ActivityHistoryStore.State
    var size: HomeModuleSize = .medium

    var body: some View {
        NavigationLink(value: StatisticsRoute(period: .month, metric: .steps)) {
            PaceCard(padding: size == .small ? PaceSpacing.s : PaceSpacing.m) {
                if let summary {
                    content(summary)
                } else {
                    placeholder
                }
            }
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary?.accessibilityLabel ?? "Deine Serie")
        .accessibilityHint("Öffnet die Monatsstatistik")
    }

    @ViewBuilder
    private func content(_ summary: StreakSummary) -> some View {
        switch size {
        case .small:
            HStack(spacing: PaceSpacing.s) {
                PaceStreakFlame(isActive: summary.currentDays > 0, isTodayReached: summary.isTodayReached, size: 30)
                Text(summary.currentText)
                    .font(.system(.title3, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                Text("Serie")
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                Spacer(minLength: PaceSpacing.xs)
                if let record = summary.recordText {
                    Text(record)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PaceColor.textSecondary)
            }
        case .medium, .large:
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Deine Serie", showsChevron: true)
                HStack(spacing: PaceSpacing.m) {
                    PaceStreakFlame(isActive: summary.currentDays > 0, isTodayReached: summary.isTodayReached, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.currentText)
                            .font(PaceFont.metric(size: 34))
                            .monospacedDigit()
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(summary.statusText)
                            .font(PaceFont.caption)
                            .foregroundStyle(summary.isTodayReached ? PaceColor.accent : PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                if size == .large {
                    StreakCalendar(days: summary.lastFourWeeks)
                } else {
                    StreakWeek(days: summary.lastWeek)
                }
                if let record = summary.recordText {
                    Label(record, systemImage: "trophy")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        HStack(spacing: PaceSpacing.s) {
            PaceStreakFlame(isActive: false, isTodayReached: false, size: size == .small ? 30 : 44)
            switch state {
            case .noReadAccess:
                Text("Ohne Zugriff auf deine Schritte lässt sich keine Serie berechnen.")
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                Text(message)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .idle, .loading, .loaded:
                Text("Serie wird berechnet …")
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                Spacer(minLength: 0)
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Die letzten 7 Tage als Punkte mit Wochentag.
private struct StreakWeek: View {
    let days: [StreakSummary.Day]

    var body: some View {
        HStack(spacing: PaceSpacing.xs) {
            ForEach(days) { day in
                VStack(spacing: PaceSpacing.xxs) {
                    StreakDot(status: day.status, size: 26)
                    Text(day.letter)
                        .font(PaceFont.micro)
                        .foregroundStyle(day.status == .pending ? PaceColor.textPrimary : PaceColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Die letzten 4 Wochen als Raster (7 Spalten).
private struct StreakCalendar: View {
    let days: [StreakSummary.Day]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PaceSpacing.xs), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: PaceSpacing.xs) {
            ForEach(days) { day in
                StreakDot(status: day.status, size: 22)
            }
        }
    }
}

private struct StreakDot: View {
    let status: StepStreakDayStatus
    let size: CGFloat

    var body: some View {
        ZStack {
            switch status {
            case .reached:
                Circle().fill(PaceColor.accentStrong)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(PaceColor.onAccent)
            case .pending:
                Circle().strokeBorder(PaceColor.accentStrong, lineWidth: 2)
            case .missed:
                Circle().fill(PaceColor.track)
            case .unknown, .future:
                Circle().strokeBorder(PaceColor.border, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
