import DesignSystem
import PaceCore
import SwiftUI

/// Kombinierte Gruppenkarte: links oben „x von n Mitgliedern haben das Tagesziel erreicht“, rechts nur Flamme und
/// Zahl, darunter der Fortschrittsbalken (mit Markierung der Flammen-Schwelle) und der Hinweis nach der ⌈n/3⌉-Regel.
///
/// Die ganze Karte öffnet den Gruppenkalender – ohne Pfeil und ohne eigenen „Gruppenkalender“-Text.
public struct GroupDayProgressCard: View {
    private let progress: GroupDayProgress
    private let action: (() -> Void)?

    /// - Parameter action: Öffnet den Gruppenkalender; `nil` zeigt die Karte ohne Tippfläche (z. B. Vorschau).
    public init(progress: GroupDayProgress, action: (() -> Void)?) {
        self.progress = progress
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) {
                card
            }
            .buttonStyle(.pacePressable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(progress.accessibilityLabel)
            .accessibilityHint(PaceLocalization.text(
                de: "Öffnet den Gruppenkalender", en: "Opens the group calendar", ru: "Открывает календарь группы"
            ))
            .accessibilityAddTraits(.isButton)
        } else {
            card
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(progress.accessibilityLabel)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            HStack(alignment: .top, spacing: PaceSpacing.s) {
                Text(progress.reachedText)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: PaceSpacing.xs)
                GroupFlameCount(progress: progress)
            }
            GroupDayProgressBar(progress: progress)
            if let hint = progress.hint {
                Text(hint)
                    .font(PaceFont.callout)
                    .foregroundStyle(progress.isSecured ? PaceColor.accent : PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(PaceSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paceCardBackground()
        .contentShape(Rectangle())
    }
}

/// Nur Flamme und Zahl (z. B. „🔥 12“) – brennend bei laufender Serie, sonst gedämpft.
public struct GroupFlameCount: View {
    private let progress: GroupDayProgress

    public init(progress: GroupDayProgress) {
        self.progress = progress
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: progress.isFlameLit ? "flame.fill" : "flame")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(progress.isFlameLit ? PaceColor.streak : PaceColor.textSecondary)
            Text(progress.streakText)
                .font(.system(.title3, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(PaceColor.textPrimary)
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// Balken: erreichte Mitglieder von allen, mit einem Strich an der Flammen-Schwelle (⌈n/3⌉).
public struct GroupDayProgressBar: View {
    private let progress: GroupDayProgress
    private let height: CGFloat

    public init(progress: GroupDayProgress, height: CGFloat = 12) {
        self.progress = progress
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PaceColor.track)
                Capsule()
                    .fill(progress.isSecured ? PaceColor.goalReachedFill : PaceColor.accent)
                    .frame(width: proxy.size.width * progress.progress)
                if let threshold = progress.thresholdFraction {
                    Rectangle()
                        .fill(PaceColor.textPrimary.opacity(0.55))
                        .frame(width: 2, height: height + 6)
                        .offset(x: proxy.size.width * threshold - 1)
                }
            }
        }
        .frame(height: height)
        .padding(.vertical, 3)
        .accessibilityHidden(true)
    }
}
