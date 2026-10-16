import SwiftUI

/// Gefüllter Button für die wichtigste Aktion eines Screens.
public struct PacePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaceFont.headline)
            .foregroundStyle(PaceColor.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, PaceSpacing.m)
            .background(
                PaceColor.accent.opacity(isEnabled ? 1 : 0.45),
                in: RoundedRectangle(cornerRadius: PaceRadius.button, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Dezenter Button für Neben-Aktionen.
public struct PaceSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaceFont.headline)
            .foregroundStyle(PaceColor.accent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, PaceSpacing.m)
            .background(
                PaceColor.accent.opacity(0.12),
                in: RoundedRectangle(cornerRadius: PaceRadius.button, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PacePrimaryButtonStyle {
    static var pacePrimary: PacePrimaryButtonStyle { PacePrimaryButtonStyle() }
}

public extension ButtonStyle where Self == PaceSecondaryButtonStyle {
    static var paceSecondary: PaceSecondaryButtonStyle { PaceSecondaryButtonStyle() }
}

#Preview {
    VStack(spacing: PaceSpacing.s) {
        Button("Primär") {}.buttonStyle(.pacePrimary)
        Button("Primär deaktiviert") {}.buttonStyle(.pacePrimary).disabled(true)
        Button("Sekundär") {}.buttonStyle(.paceSecondary)
    }
    .padding()
}
