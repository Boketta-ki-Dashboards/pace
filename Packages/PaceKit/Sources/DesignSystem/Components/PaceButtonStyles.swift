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
                PaceColor.accentStrong.opacity(isEnabled ? 1 : 0.45),
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
            .foregroundStyle(PaceColor.accentStrong)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, PaceSpacing.m)
            .background(
                PaceColor.accentSoft,
                in: RoundedRectangle(cornerRadius: PaceRadius.button, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Kompakter gefüllter Button, z. B. „Anpassen“ im Home-Header.
public struct PaceCompactButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaceFont.headline)
            .foregroundStyle(PaceColor.onAccent)
            .padding(.horizontal, PaceSpacing.m)
            .padding(.vertical, PaceSpacing.xs + 2)
            .background(PaceColor.accentStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Weiche Aktionsfläche, z. B. „Freund hinzufügen“ oder der Einstellungen-Button im Social-Kopf:
/// Light zartes Mint mit dunkelgrünem Inhalt, Dark dunkles Grün mit Mint-Rand und hellem Inhalt.
public struct PaceSoftButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaceRadius.button, style: .continuous)
        configuration.label
            .foregroundStyle(colorScheme == .dark ? PaceColor.textPrimary : PaceColor.onSelection)
            .padding(.horizontal, PaceSpacing.s)
            .padding(.vertical, PaceSpacing.xs)
            .background(colorScheme == .dark ? PaceColor.accentSoft : PaceColor.selectionFill, in: shape)
            .overlay(shape.strokeBorder(PaceColor.accent.opacity(colorScheme == .dark ? 0.35 : 0), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Kompakter gefüllter Button in Zeilen („Hinzufügen“, „Annehmen“).
public struct PaceActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(PaceColor.onAccent)
            .padding(.horizontal, PaceSpacing.s)
            .frame(minHeight: 40)
            .background(
                PaceColor.actionFill.opacity(isEnabled ? 1 : 0.45),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Umrandeter Button für Neben-Aktionen in Zeilen („Ablehnen“, „Zurückziehen“).
public struct PaceOutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .font(.system(.subheadline, weight: .medium))
            .foregroundStyle(PaceColor.textPrimary)
            .padding(.horizontal, PaceSpacing.s)
            .frame(minHeight: 40)
            .background(PaceColor.surface, in: shape)
            .overlay(shape.strokeBorder(PaceColor.textSecondary.opacity(0.45), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Quadratischer Symbol-Button (z. B. Einstellungen, Info, „…“-Menü) in der Optik von ``PaceSoftButtonStyle``.
/// Das Label ist nur das Symbol: `Button { … } label: { Image(systemName: "gearshape") }.buttonStyle(.paceIcon)`.
public struct PaceIconButtonStyle: ButtonStyle {
    private let size: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    public init(size: CGFloat = 44) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? PaceColor.accent : PaceColor.onSelection)
            .frame(width: size, height: size)
            .background(colorScheme == .dark ? PaceColor.accentSoft : PaceColor.selectionFill, in: shape)
            .overlay(shape.strokeBorder(PaceColor.accent.opacity(colorScheme == .dark ? 0.3 : 0), lineWidth: 1))
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Neutraler quadratischer Symbol-Button (grau, z. B. „…“ in Ergebniszeilen).
public struct PaceNeutralIconButtonStyle: ButtonStyle {
    private let size: CGFloat

    public init(size: CGFloat = 40) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(PaceColor.textSecondary)
            .frame(width: size, height: size)
            .background(PaceColor.fieldBackground, in: shape)
            .overlay(shape.strokeBorder(PaceColor.border, lineWidth: 1))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Karte oder Zeile als Button: ohne eigene Optik, mit leichtem Feedback beim Drücken.
public struct PacePressableStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PaceCompactButtonStyle {
    static var paceCompact: PaceCompactButtonStyle { PaceCompactButtonStyle() }
}

public extension ButtonStyle where Self == PacePressableStyle {
    static var pacePressable: PacePressableStyle { PacePressableStyle() }
}

public extension ButtonStyle where Self == PaceSoftButtonStyle {
    static var paceSoft: PaceSoftButtonStyle { PaceSoftButtonStyle() }
}

public extension ButtonStyle where Self == PaceActionButtonStyle {
    static var paceAction: PaceActionButtonStyle { PaceActionButtonStyle() }
}

public extension ButtonStyle where Self == PaceOutlineButtonStyle {
    static var paceOutline: PaceOutlineButtonStyle { PaceOutlineButtonStyle() }
}

public extension ButtonStyle where Self == PaceIconButtonStyle {
    static var paceIcon: PaceIconButtonStyle { PaceIconButtonStyle() }
}

public extension ButtonStyle where Self == PaceNeutralIconButtonStyle {
    static var paceNeutralIcon: PaceNeutralIconButtonStyle { PaceNeutralIconButtonStyle() }
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
