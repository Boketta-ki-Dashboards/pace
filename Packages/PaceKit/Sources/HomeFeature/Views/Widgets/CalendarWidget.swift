import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

/// Kalender-Widget: kompakter Wochen- bzw. Monatsausschnitt nach den Kalender-Regeln.
///
/// Nicht erreicht = Ring mit Fortschritt um die Tagesnummer auf neutraler Fläche; erreicht = volle grüne Fläche ohne
/// Ring; heute mit eigener Markierung; Zukunft neutral ohne Werte. Tippen öffnet den Kalender.
struct CalendarWidgetContent: View {
    let widget: HomeCalendarWidget
    let size: HomeModuleSize
    let isLoading: Bool

    var body: some View {
        NavigationLink(value: CalendarRoute()) {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(widget.periodTitle)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: PaceSpacing.xs)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(widget.summaryText)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                HStack(spacing: cellSpacing) {
                    ForEach(Array(widget.weekdayLetters.enumerated()), id: \.offset) { _, letter in
                        Text(letter)
                            .font(PaceFont.micro)
                            .foregroundStyle(PaceColor.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
                VStack(spacing: cellSpacing) {
                    ForEach(Array(widget.weeks.enumerated()), id: \.offset) { _, week in
                        HStack(spacing: cellSpacing) {
                            ForEach(week) { day in
                                CalendarDayCell(day: day, showsSteps: size == .max, height: cellHeight)
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .accessibilityHint(PaceLocalization.text(de: "Öffnet den Kalender", en: "Opens the calendar", ru: "Открывает календарь"))
    }

    private var cellSpacing: CGFloat {
        size >= .large ? 4 : 6
    }

    private var cellHeight: CGFloat {
        switch size {
        case .small, .medium: 42
        case .large: 36
        case .max: 50
        }
    }
}

/// Ein Tag im Kalender-Widget.
private struct CalendarDayCell: View {
    let day: HomeCalendarWidget.Day
    let showsSteps: Bool
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack {
            if day.isInPeriod {
                shape.fill(day.state == .reached ? PaceColor.goalReachedFill : PaceColor.surfaceSecondary)
                VStack(spacing: 1) {
                    ZStack {
                        if day.state == .notReached {
                            Circle()
                                .stroke(PaceColor.track, lineWidth: 2.5)
                            Circle()
                                .trim(from: 0, to: day.progress)
                                .stroke(PaceColor.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        Text(day.numberText)
                            .font(.system(.caption, weight: day.isToday ? .bold : .semibold))
                            .monospacedDigit()
                            .foregroundStyle(numberColor)
                    }
                    .frame(width: ringSize, height: ringSize)
                    if showsSteps, let steps = day.compactStepsText {
                        Text(steps)
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(day.state == .reached ? PaceColor.onGoalReached : PaceColor.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay {
            if day.isToday {
                shape.strokeBorder(PaceColor.textPrimary.opacity(0.75), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityHidden(!day.isInPeriod)
    }

    private var ringSize: CGFloat {
        min(height - (showsSteps ? 16 : 8), 30)
    }

    private var numberColor: Color {
        switch day.state {
        case .reached: PaceColor.onGoalReached
        case .future, .noData: PaceColor.textSecondary
        case .notReached: PaceColor.textPrimary
        }
    }
}
