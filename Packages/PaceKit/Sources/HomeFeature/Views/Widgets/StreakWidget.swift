import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

/// „Persönliche Streak“: Tage in Folge mit erreichtem Tagesziel – ohne riesige Kreisfelder.
///
/// - Klein: Flamme und aktuelle Serie.
/// - Mittel: Serie und Rekord, dazu der Status von heute.
/// - Groß: dazu die laufende Woche als übersichtliche Leiste.
/// - Max: dazu die letzten vier Wochen kompakt und erreichte Tage der letzten 30 Tage.
///
/// Ist die Serie unterbrochen, zeigen Woche und Verlauf trotzdem erreichte Tage – der Status-Text erklärt den
/// Unterschied.
struct StreakWidgetContent: View {
    let widget: HomeStreakWidget?
    let state: ActivityHistoryStore.State
    let size: HomeModuleSize

    var body: some View {
        if let widget {
            content(widget)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(widget.accessibilityLabel)
        } else {
            placeholder
        }
    }

    @ViewBuilder
    private func content(_ widget: HomeStreakWidget) -> some View {
        switch size {
        case .small:
            HStack(spacing: PaceSpacing.s) {
                PaceStreakFlame(isActive: widget.current > 0, isTodayReached: widget.isTodayReached, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(widget.currentText)
                        .font(.system(.title3, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(widget.shortStatusText)
                        .font(PaceFont.caption)
                        .foregroundStyle(widget.isTodayReached ? PaceColor.accent : PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
        case .medium:
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                summaryRow(widget)
                statusLine(widget)
            }
        case .large:
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                summaryRow(widget)
                StreakWeekStrip(days: widget.week)
                statusLine(widget)
            }
        case .max:
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                summaryRow(widget)
                StreakWeekStrip(days: widget.week)
                StreakHistoryGrid(days: widget.fourWeeks)
                HStack(spacing: PaceSpacing.xs) {
                    HomeStatTile(
                        title: PaceLocalization.text(de: "Letzte 30 Tage", en: "Last 30 days", ru: "Последние 30 дней"),
                        value: widget.reachedLast30Days.paceFormatted,
                        systemImage: "checkmark.circle"
                    )
                    HomeStatTile(
                        title: PaceLocalization.text(de: "Diese Woche", en: "This week", ru: "Эта неделя"),
                        value: widget.reachedThisWeek.paceFormatted,
                        systemImage: "calendar"
                    )
                }
                statusLine(widget)
            }
        }
    }

    /// Flamme, aktuelle Serie und Rekord nebeneinander.
    private func summaryRow(_ widget: HomeStreakWidget) -> some View {
        HStack(spacing: PaceSpacing.s) {
            PaceStreakFlame(isActive: widget.current > 0, isTodayReached: widget.isTodayReached, size: 48)
            VStack(alignment: .leading, spacing: 0) {
                Text(widget.currentNumberText)
                    .font(PaceFont.metric(size: 34))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(PaceLocalization.text(
                    de: "\(widget.unitText) in Folge",
                    en: "\(widget.unitText) in a row",
                    ru: "\(widget.unitText) подряд"
                ))
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            Spacer(minLength: PaceSpacing.xs)
            VStack(alignment: .trailing, spacing: 0) {
                Label(PaceLocalization.text(de: "Rekord", en: "Record", ru: "Рекорд"), systemImage: "trophy")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(1)
                Text(widget.recordText ?? "–")
                    .font(.system(.headline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func statusLine(_ widget: HomeStreakWidget) -> some View {
        Text(widget.statusText)
            .font(PaceFont.caption)
            .foregroundStyle(widget.isTodayReached ? PaceColor.accent : PaceColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var placeholder: some View {
        switch state {
        case .noReadAccess:
            HomeWidgetHint(
                systemImage: "hand.raised",
                text: PaceLocalization.text(
                    de: "Ohne Zugriff auf deine Schritte lässt sich keine Serie berechnen.",
                    en: "Without access to your steps no streak can be calculated.",
                    ru: "Без доступа к шагам серию не посчитать."
                )
            )
        case .failed(let message):
            HomeWidgetHint(systemImage: "arrow.clockwise", text: message)
        case .idle, .loading, .loaded:
            HStack(spacing: PaceSpacing.s) {
                PaceStreakFlame(isActive: false, isTodayReached: false, size: size == .small ? 40 : 48)
                Text(PaceLocalization.text(de: "Serie wird berechnet …", en: "Calculating streak …", ru: "Считаем серию …"))
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                Spacer(minLength: 0)
                ProgressView()
            }
        }
    }
}

/// Die laufende Woche als Leiste: erreichte Tage gefüllt, verpasste neutral, heute umrandet.
private struct StreakWeekStrip: View {
    let days: [HomeStreakWidget.Day]

    var body: some View {
        HStack(spacing: PaceSpacing.xs) {
            ForEach(days) { day in
                VStack(spacing: PaceSpacing.xxs) {
                    StreakDayMark(status: day.status, isToday: day.isToday, size: 26)
                    Text(day.letter)
                        .font(PaceFont.micro)
                        .foregroundStyle(day.isToday ? PaceColor.textPrimary : PaceColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.accessibilityLabel)
            }
        }
    }
}

/// Die letzten vier Wochen kompakt (kleine Punkte, eine Zeile je Woche).
private struct StreakHistoryGrid: View {
    let days: [HomeStreakWidget.Day]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(days) { day in
                StreakDayMark(status: day.status, isToday: day.isToday, size: 14)
            }
        }
        .padding(.horizontal, PaceSpacing.xs)
        .accessibilityHidden(true)
    }
}

private struct StreakDayMark: View {
    let status: StepStreakDayStatus
    let isToday: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            switch status {
            case .reached:
                Circle().fill(PaceColor.goalReachedFill)
                if size >= 20 {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(PaceColor.onGoalReached)
                }
            case .pending:
                Circle().strokeBorder(PaceColor.accent, lineWidth: 2)
            case .missed:
                Circle().fill(PaceColor.track)
            case .unknown, .future:
                Circle().strokeBorder(PaceColor.border, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if isToday, status == .reached {
                Circle()
                    .strokeBorder(PaceColor.textPrimary.opacity(0.6), lineWidth: 1.5)
                    .padding(-3)
            }
        }
        .accessibilityHidden(true)
    }
}
