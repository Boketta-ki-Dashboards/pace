import PaceCore
import SwiftUI

/// Karte, deren Inhalt bewusst verborgen ist (z. B. „Ranking ausgeschaltet“): Die Grundform der Karte bleibt erkennbar,
/// darüber liegt eine dezente Unschärfe mit Symbol, Überschrift und kurzer Erklärung.
///
/// Der Platzhalter darf keine echten Daten enthalten – er zeigt nur die Struktur (z. B. graue Balken statt Namen).
/// Für VoiceOver ist er ausgeblendet; vorgelesen werden nur Überschrift, Erklärung und Aktion.
public struct PaceLockedCard<Placeholder: View>: View {
    private let systemImage: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let placeholder: Placeholder

    public init(
        systemImage: String = "eye.slash",
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.placeholder = placeholder()
    }

    public var body: some View {
        ZStack {
            placeholder
                .blur(radius: 5)
                .opacity(0.55)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: PaceSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(PaceColor.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.system(.subheadline, weight: .semibold))
                        .buttonStyle(.paceSoft)
                        .padding(.top, PaceSpacing.xxs)
                }
            }
            .padding(.horizontal, PaceSpacing.m)
            .padding(.vertical, PaceSpacing.s)
            .background(
                PaceColor.surface.opacity(0.78),
                in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
            )
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Neutraler grauer Balken als Platzhalter für verborgene Inhalte.
public struct PacePlaceholderBar: View {
    private let width: CGFloat?
    private let height: CGFloat

    public init(width: CGFloat? = nil, height: CGFloat = 12) {
        self.width = width
        self.height = height
    }

    public var body: some View {
        Capsule()
            .fill(PaceColor.track)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}
