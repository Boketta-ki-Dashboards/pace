import DesignSystem
import SwiftUI

/// „Deine Schritte heute“: große Schrittzahl, Tagesziel mit Balken und Ring, Distanz und aktive Kalorien.
struct StepsTodayCardView<Details: View>: View {
    let state: HomeViewModel.State
    let summary: StepsTodaySummary?
    let onEditGoal: () -> Void
    let onRetry: () -> Void
    @ViewBuilder let details: () -> Details

    @ScaledMetric(relativeTo: .largeTitle) private var metricSize: CGFloat = 64
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 96

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Deine Schritte heute")
                        .font(PaceFont.cardTitle)
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: PaceSpacing.xs)
                    Button(action: onEditGoal) {
                        Label("Tagesziel ändern", systemImage: "scope")
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .buttonStyle(.pacePressable)
                }

                switch state {
                case .loading:
                    HStack(spacing: PaceSpacing.s) {
                        ProgressView()
                        Text("Schritte werden geladen …")
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)

                case .loaded:
                    if let summary {
                        loadedContent(summary)
                    }

                case .noReadAccess:
                    message(
                        systemImage: "hand.raised.fill",
                        title: "Keine Schrittdaten lesbar",
                        text: "Öffne die Health-App, tippe auf dein Profilbild und aktiviere unter „Datenschutz“ → "
                            + "„Apps“ → „Pace“ den Zugriff auf „Schritte“. Hast du den Zugriff bereits erlaubt? Dann "
                            + "prüfe unter Einstellungen → Datenschutz & Sicherheit → Bewegung & Fitness, ob "
                            + "„Fitness-Tracking“ aktiviert ist."
                    )

                case .failed(let text):
                    message(systemImage: "exclamationmark.triangle.fill", title: "Schritte nicht verfügbar", text: text)
                }
            }
        }
    }

    @ViewBuilder
    private func loadedContent(_ summary: StepsTodaySummary) -> some View {
        HStack(alignment: .center, spacing: PaceSpacing.m) {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                Text(summary.stepsText)
                    .font(PaceFont.metric(size: metricSize))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: Double(summary.steps)))
                    .animation(.snappy, value: summary.steps)
                Text(summary.goalText)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(PaceColor.textPrimary)
                PaceProgressBar(progress: summary.progress)
                    .padding(.top, PaceSpacing.xxs)
                Text(summary.remainingText)
                    .font(.subheadline)
                    .foregroundStyle(summary.isGoalReached ? PaceColor.accent : PaceColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            PaceProgressRing(progress: summary.progress, label: summary.percentText)
                .frame(width: ringSize, height: ringSize)
        }
        .accessibilityElement(children: .combine)

        if let note = summary.manualStepsNote {
            Label(note, systemImage: "info.circle")
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
        }

        if summary.distanceText != nil || summary.energyText != nil {
            PaceTile {
                HStack(spacing: 0) {
                    if let distance = summary.distanceText {
                        NavigationLink(destination: details) {
                            MetricLink(systemImage: "shoeprints.fill", value: distance, caption: nil)
                        }
                        .buttonStyle(.pacePressable)
                    }
                    if summary.distanceText != nil, summary.energyText != nil {
                        Divider()
                            .frame(height: 32)
                            .padding(.horizontal, PaceSpacing.xs)
                    }
                    if let energy = summary.energyText {
                        NavigationLink(destination: details) {
                            MetricLink(systemImage: "flame", value: energy, caption: "Aktive Kalorien")
                        }
                        .buttonStyle(.pacePressable)
                    }
                }
                .padding(.vertical, PaceSpacing.xxs)
            }
        } else {
            NavigationLink(destination: details) {
                PaceTile {
                    MetricLink(systemImage: "chart.bar", value: "Statistiken", caption: nil)
                        .padding(.vertical, PaceSpacing.xxs)
                }
            }
            .buttonStyle(.pacePressable)
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
            Button("Erneut versuchen", action: onRetry)
                .buttonStyle(.paceSecondary)
                .padding(.top, PaceSpacing.xxs)
        }
    }
}

/// Eine Hälfte der Distanz-/Kalorien-Leiste.
private struct MetricLink: View {
    let systemImage: String
    let value: String
    let caption: String?

    var body: some View {
        HStack(spacing: PaceSpacing.xs) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(PaceColor.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let caption {
                    Text(caption)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: PaceSpacing.xxs)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PaceColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
