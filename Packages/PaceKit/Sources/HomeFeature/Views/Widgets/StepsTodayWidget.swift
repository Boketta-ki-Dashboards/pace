import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

/// „Deine Schritte heute“ – der visuelle Mittelpunkt von Home: große Schrittzahl, Tagesziel mit Balken und Ring,
/// Distanz und aktive Kalorien. Die Aktion „Tagesziel ändern“ ändert nur das Ziel, nie gemessene Schritte.
///
/// Größen (Zusatzinhalte nach Auswahl im Bearbeitungsmodus, ``HomeWidgetDetail``; ohne eigene Auswahl der Standard):
/// - Klein: Schrittzahl, Prozent und Fortschrittsbalken unter der Überschrift.
/// - Mittel: große Schrittzahl, Ziel, Balken, „Noch … bis zu deinem Ziel“, Ring mit Prozent, Distanz und Kalorien.
/// - Groß: zusätzlich Stockwerke und Training.
/// - Max: Groß plus Analyse – Mini-Diagramm der letzten 7 Tage mit Ziellinie und der Vergleich mit gestern und dem
///   Durchschnitt der letzten 7 Tage.
/// Wählbar außerdem der persönliche Tagesbestwert. Geschätzte Kalorien sind gekennzeichnet („≈“, „Geschätzte …“).
struct StepsTodayWidgetContent: View {
    let state: HomeViewModel.State
    let summary: StepsTodaySummary?
    let size: HomeModuleSize
    var details: [HomeWidgetDetail] = HomeModuleKind.stepsToday.defaultDetails(for: .medium)
    var dayBest: HomeDayBest?
    let onRetry: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var metricSize: CGFloat = 62
    @ScaledMetric(relativeTo: .largeTitle) private var compactMetricSize: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 104
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch state {
        case .loading:
            HStack(spacing: PaceSpacing.s) {
                ProgressView()
                Text(PaceLocalization.text(de: "Schritte werden geladen …", en: "Loading steps …", ru: "Загружаем шаги …"))
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 140)

        case .loaded:
            if let summary {
                loaded(summary)
            }

        case .noReadAccess:
            message(
                systemImage: "hand.raised",
                title: PaceLocalization.text(de: "Keine Schrittdaten lesbar", en: "No step data readable", ru: "Нет доступа к шагам"),
                text: PaceLocalization.text(
                    de: "Öffne die Health-App, tippe auf dein Profilbild und erlaube unter „Datenschutz“ → „Apps“ → „Pace“ "
                        + "den Zugriff auf „Schritte“. Prüfe außerdem unter Einstellungen → Datenschutz & Sicherheit → "
                        + "Bewegung & Fitness, ob „Fitness-Tracking“ aktiviert ist.",
                    en: "Open the Health app, tap your profile picture and allow access to “Steps” under “Privacy” → "
                        + "“Apps” → “Pace”. Also check that “Fitness Tracking” is on under Settings → Privacy & Security → "
                        + "Motion & Fitness.",
                    ru: "Открой приложение «Здоровье», нажми на фото профиля и разреши доступ к «Шагам» в разделе "
                        + "«Конфиденциальность» → «Приложения» → «Pace». Также проверь, что «Отслеживание фитнеса» включено "
                        + "в Настройки → Конфиденциальность и безопасность → Движение и фитнес."
                )
            )

        case .failed(let text):
            message(
                systemImage: "arrow.clockwise",
                title: PaceLocalization.text(de: "Schritte nicht verfügbar", en: "Steps unavailable", ru: "Шаги недоступны"),
                text: text
            )
        }
    }

    @ViewBuilder
    private func loaded(_ summary: StepsTodaySummary) -> some View {
        if size == .small {
            compact(summary)
        } else {
            full(summary)
        }
    }

    /// Klein: Schrittzahl und Prozent in einer Zeile, darunter der Balken.
    private func compact(_ summary: StepsTodaySummary) -> some View {
        NavigationLink(value: HomeRoute.statistics(StatisticsRoute(period: .day, metric: .steps))) {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: PaceSpacing.xs) {
                    Text(summary.stepsText)
                        .font(PaceFont.metric(size: compactMetricSize))
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText(value: Double(summary.steps)))
                        .animation(.snappy, value: summary.steps)
                    Text(summary.goalText)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: PaceSpacing.xxs)
                    Text(summary.percentText)
                        .font(.system(.headline, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(summary.isGoalReached ? PaceColor.accent : PaceColor.textPrimary)
                }
                PaceProgressBar(progress: summary.progress)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: summary.progress)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint(PaceLocalization.text(
            de: "Öffnet die Aktivitätsdetails von heute", en: "Opens today's activity details", ru: "Открывает подробности за сегодня"
        ))
    }

    @ViewBuilder
    private func full(_ summary: StepsTodaySummary) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            NavigationLink(value: HomeRoute.statistics(StatisticsRoute(period: .day, metric: .steps))) {
                HStack(alignment: .center, spacing: PaceSpacing.m) {
                    VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                        Text(summary.stepsText)
                            .font(PaceFont.metric(size: metricSize))
                            .monospacedDigit()
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText(value: Double(summary.steps)))
                            .animation(.snappy, value: summary.steps)
                        Text(summary.goalText)
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        PaceProgressBar(progress: summary.progress)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: summary.progress)
                            .padding(.top, PaceSpacing.xs)
                        Text(summary.remainingText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(summary.isGoalReached ? PaceColor.accent : PaceColor.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .padding(.top, PaceSpacing.xxs)
                    }
                    PaceProgressRing(progress: summary.progress, label: summary.percentText)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: summary.progress)
                        .frame(width: ringSize, height: ringSize)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .accessibilityElement(children: .combine)
            .accessibilityHint(PaceLocalization.text(
                de: "Öffnet die Aktivitätsdetails von heute", en: "Opens today's activity details", ru: "Открывает подробности за сегодня"
            ))

            if let note = summary.manualStepsNote {
                Label(note, systemImage: "info.circle")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
            }

            if details.contains(.distanceEnergy) {
                metricsTile(summary)
            }

            if details.contains(.floorsExercise) {
                PaceTile {
                    HStack(spacing: 0) {
                        StepsMetricCell(
                            systemImage: "figure.stairs",
                            value: summary.flightsText ?? "–",
                            caption: PaceLocalization.text(de: "Stockwerke", en: "Floors", ru: "Этажи")
                        )
                        Divider().frame(height: 32).padding(.horizontal, PaceSpacing.xs)
                        StepsMetricCell(
                            systemImage: "stopwatch",
                            value: summary.exerciseText ?? "–",
                            // Kurz, damit nichts mitten im Wort umbricht („Train-ingsminuten“); der Wert sagt „Min.“.
                            caption: PaceLocalization.text(de: "Training", en: "Exercise", ru: "Тренировка")
                        )
                    }
                    .padding(.vertical, PaceSpacing.xxs)
                }
            }

            if details.contains(.weekChart), !summary.sevenDays.isEmpty {
                NavigationLink(value: HomeRoute.statistics(StatisticsRoute(period: .week, metric: .steps))) {
                    StepsSevenDayChart(summary: summary)
                }
                .buttonStyle(.pacePressable)
                .accessibilityHint(PaceLocalization.text(
                    de: "Öffnet die Wochenstatistik", en: "Opens the weekly statistics", ru: "Открывает статистику за неделю"
                ))
            }

            if details.contains(.comparison) {
                HStack(spacing: PaceSpacing.xs) {
                    HomeStatTile(
                        title: PaceLocalization.text(de: "Gestern", en: "Yesterday", ru: "Вчера"),
                        value: summary.yesterdayText ?? "–",
                        systemImage: "clock.arrow.circlepath"
                    )
                    HomeStatTile(
                        title: PaceLocalization.text(de: "Ø letzte 7 Tage", en: "Avg. last 7 days", ru: "В среднем за 7 дней"),
                        value: summary.sevenDayAverageText ?? "–",
                        systemImage: "chart.bar"
                    )
                }
            }

            if details.contains(.dayBest) {
                HomeStatTile(
                    title: dayBest?.title ?? PaceLocalization.text(de: "Tagesbestwert", en: "Best day", ru: "Рекорд дня"),
                    value: dayBest?.valueText ?? "–",
                    systemImage: "trophy"
                )
            }
        }
    }

    /// Distanz und aktive Kalorien. Kalorien erscheinen immer – ohne Werte aus Apple Health als „Nicht verfügbar“
    /// (Antippen öffnet die Kalorienstatistik mit Erklärung), nie als falsche 0.
    private func metricsTile(_ summary: StepsTodaySummary) -> some View {
        PaceTile {
            HStack(spacing: 0) {
                if let distance = summary.distanceText {
                    NavigationLink(value: HomeRoute.statistics(StatisticsRoute(period: .week, metric: .distance))) {
                        StepsMetricCell(systemImage: "shoeprints.fill", value: distance, caption: nil, showsChevron: true)
                    }
                    .buttonStyle(.pacePressable)
                    .accessibilityLabel(PaceLocalization.text(de: "Distanz", en: "Distance", ru: "Расстояние") + ", " + distance)
                    .accessibilityHint(PaceLocalization.text(
                        de: "Öffnet die Distanzstatistik", en: "Opens the distance statistics", ru: "Открывает статистику расстояния"
                    ))
                }
                if summary.distanceText != nil {
                    Divider().frame(height: 32).padding(.horizontal, PaceSpacing.xs)
                }
                NavigationLink(value: HomeRoute.statistics(StatisticsRoute(period: .week, metric: .activeEnergy))) {
                    StepsMetricCell(
                        systemImage: "flame",
                        value: summary.energyText,
                        caption: summary.energyCaption,
                        showsChevron: true,
                        isMuted: !summary.isEnergyAvailable
                    )
                }
                .buttonStyle(.pacePressable)
                .accessibilityHint(PaceLocalization.text(
                    de: "Öffnet die Kalorienstatistik", en: "Opens the calorie statistics", ru: "Открывает статистику калорий"
                ))
            }
            .padding(.vertical, PaceSpacing.xxs)
        }
    }

    private func message(systemImage: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            Label(title, systemImage: systemImage)
                .font(PaceFont.headline)
                .foregroundStyle(PaceColor.textPrimary)
            Text(text)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(HomeTexts.retry, action: onRetry)
                .buttonStyle(.paceSecondary)
                .padding(.top, PaceSpacing.xxs)
        }
    }
}

/// Eine Hälfte der Distanz-/Kalorien-Leiste.
private struct StepsMetricCell: View {
    let systemImage: String
    let value: String
    let caption: String?
    var showsChevron = false
    /// Gedämpft für „Nicht verfügbar“.
    var isMuted = false

    var body: some View {
        HStack(spacing: PaceSpacing.xs) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(PaceColor.textPrimary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(.headline, weight: isMuted ? .semibold : .bold))
                    .monospacedDigit()
                    .foregroundStyle(isMuted ? PaceColor.textSecondary : PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let caption {
                    Text(caption)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: PaceSpacing.xxs)
            if showsChevron {
                HomeRowChevron()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Mini-Diagramm „Letzte 7 Tage“: ein Balken pro Tag (heute dunkel, erreichte Tage kräftig), gestrichelte Ziellinie,
/// darunter wie oft das Ziel erreicht wurde. Keine Werte, die es nicht gibt: Tage ohne Schritte haben einen leeren Balken.
struct StepsSevenDayChart: View {
    let summary: StepsTodaySummary

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 64

    var body: some View {
        PaceTile {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(HomeTexts.lastSevenDays)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                    Spacer(minLength: PaceSpacing.xs)
                    if let average = summary.sevenDayAverageText {
                        Text("Ø \(average)")
                            .font(PaceFont.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    HomeRowChevron()
                }
                HStack(alignment: .bottom, spacing: PaceSpacing.xs) {
                    ForEach(summary.sevenDays) { day in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(color(for: day))
                                .frame(height: max(4, chartHeight * level(day.steps)))
                                .frame(height: chartHeight, alignment: .bottom)
                            Text(day.letter)
                                .font(PaceFont.micro.weight(day.isToday ? .bold : .regular))
                                .foregroundStyle(day.isToday ? PaceColor.textPrimary : PaceColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(day.accessibilityLabel)
                    }
                }
                .overlay(alignment: .top) {
                    // Ziellinie in Höhe des heutigen Ziels.
                    GeometryReader { proxy in
                        Path { path in
                            let y = chartHeight * (1 - level(summary.goal))
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        }
                        .stroke(PaceColor.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    .frame(height: chartHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                if let goalText = summary.sevenDayGoalText {
                    Text(goalText)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, PaceSpacing.xxs)
        }
        .accessibilityElement(children: .contain)
    }

    private func level(_ steps: Int) -> CGFloat {
        min(CGFloat(steps) / CGFloat(max(summary.sevenDayScale, 1)), 1)
    }

    private func color(for day: StepsTodaySummary.DayBar) -> Color {
        if day.isToday { return PaceColor.actionFill }
        return day.reachedGoal ? PaceColor.accent.opacity(0.75) : PaceColor.accent.opacity(0.28)
    }
}
