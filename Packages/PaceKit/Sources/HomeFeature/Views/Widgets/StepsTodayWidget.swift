import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

/// „Deine Schritte heute“ – der visuelle Mittelpunkt von Home: große Schrittzahl, Tagesziel mit Balken und Ring,
/// Distanz und aktive Kalorien. Die Aktion „Tagesziel ändern“ ändert nur das Ziel, nie gemessene Schritte.
///
/// - Mittel: wie im Home-Design.
/// - Groß: zusätzlich Stockwerke und Trainingsminuten.
/// - Max: zusätzlich gestern und der Durchschnitt der letzten 7 Tage.
struct StepsTodayWidgetContent: View {
    let state: HomeViewModel.State
    let summary: StepsTodaySummary?
    let size: HomeModuleSize
    let onRetry: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var metricSize: CGFloat = 62
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
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            NavigationLink(value: StatisticsRoute(period: .day, metric: .steps)) {
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

            metricsTile(summary)

            if size >= .large {
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
                            caption: PaceLocalization.text(de: "Trainingsminuten", en: "Exercise minutes", ru: "Минуты тренировки")
                        )
                    }
                    .padding(.vertical, PaceSpacing.xxs)
                }
            }

            if size == .max {
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
        }
    }

    /// Distanz und aktive Kalorien. Kalorien erscheinen immer – ohne Werte aus Apple Health als „Nicht verfügbar“
    /// (Antippen öffnet die Kalorienstatistik mit Erklärung), nie als falsche 0.
    private func metricsTile(_ summary: StepsTodaySummary) -> some View {
        PaceTile {
            HStack(spacing: 0) {
                if let distance = summary.distanceText {
                    NavigationLink(value: StatisticsRoute(period: .week, metric: .distance)) {
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
                NavigationLink(value: StatisticsRoute(period: .week, metric: .activeEnergy)) {
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
