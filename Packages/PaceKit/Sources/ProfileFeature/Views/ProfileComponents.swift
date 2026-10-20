import DesignSystem
import PaceCore
import SwiftUI

/// Unterseite des Profils: scrollender Inhalt ohne Systemleiste (der Inhalt beginnt mit ``PaceSubpageHeader``).
struct ProfileSubpage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .paceScreenBackground()
        .paceSubpage()
    }
}

/// Überschrift einer Gruppe von Einstellungen (wie „Top-Freunde“ oder „Chats“ im Social-Tab).
struct ProfileSectionTitle: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(.title3, weight: .semibold))
            .foregroundStyle(PaceColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, PaceSpacing.xs)
    }
}

/// Größere, abgerundete Einstellungszeile: Symbol, Titel, optionale Kurzbeschreibung, Wert und Pfeil.
struct ProfileSettingsRow: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var value: String?
    var tint: Color = PaceColor.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                ProfileRowIcon(systemImage: systemImage, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: PaceSpacing.xs)
                if let value {
                    Text(value)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PaceColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PaceSpacing.m)
            .padding(.vertical, PaceSpacing.s)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .paceCardBackground(cornerRadius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Symbol einer Einstellungszeile in einer weichen, abgerundeten Fläche.
struct ProfileRowIcon: View {
    let systemImage: String
    var tint: Color = PaceColor.accent

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Zeile mit Symbol, Bezeichnung und Wert (z. B. Gemeinde, Konto-Art).
struct ProfileInfoRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        PaceTile {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PaceSpacing.s) {
                    icon
                    Text(title)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                    Spacer(minLength: PaceSpacing.xs)
                    Text(value)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
                HStack(alignment: .top, spacing: PaceSpacing.s) {
                    icon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                        Text(value)
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, PaceSpacing.xxs)
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .foregroundStyle(PaceColor.accent)
            .frame(width: 24)
            .accessibilityHidden(true)
    }
}

/// Erklärender Hinweis mit Symbol.
struct ProfileNoteRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: PaceSpacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(PaceColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Kleiner Hinweistext unter einem Bedienelement (grau) oder als Fehler (rot).
struct ProfileFootnote: View {
    let text: String
    var isError = false

    var body: some View {
        Text(text)
            .font(PaceFont.caption)
            .foregroundStyle(isError ? PaceColor.danger : PaceColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Schalter in einer Kachel (Titel links, Schalter rechts).
struct ProfileToggleTile: View {
    let title: String
    let isOn: Bool
    let isHighlighted: Bool
    let isDisabled: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        PaceTile(isHighlighted: isHighlighted) {
            Toggle(isOn: Binding(get: { [isOn] in isOn }, set: { value in onChange(value) })) {
                Text(title)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(PaceColor.accentStrong)
            .disabled(isDisabled)
            .padding(.vertical, PaceSpacing.xxs)
        }
    }
}

/// Erklärung mit Symbol und Überschrift (Datenschutz, Rechtliches).
struct InfoSectionView: View {
    let section: InfoSection

    var body: some View {
        HStack(alignment: .top, spacing: PaceSpacing.s) {
            ProfileRowIcon(systemImage: section.systemImage)
            VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                Text(section.title)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(section.body)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Kennzeichnung von Texten, die der Betreiber noch prüfen muss.
struct DraftNoticeCard: View {
    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                Label(ProfileTexts.draftNotice, systemImage: "doc.badge.clock")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(PaceColor.accentStrong)
                    .padding(.horizontal, PaceSpacing.s)
                    .padding(.vertical, 6)
                    .background(PaceColor.accentSoft, in: Capsule())
                Text(PrivacyContent.draftExplanation)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Gefüllter Button für endgültige Aktionen (Konto löschen).
struct ProfileDangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaceFont.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, PaceSpacing.m)
            .background(
                PaceColor.danger.opacity(isEnabled ? 1 : 0.4),
                in: RoundedRectangle(cornerRadius: PaceRadius.button, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Umrandeter Button in Warnfarbe (führt zur Bestätigungsseite „Konto löschen“).
struct ProfileDangerOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaceRadius.button, style: .continuous)
        configuration.label
            .font(PaceFont.headline)
            .foregroundStyle(PaceColor.danger)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, PaceSpacing.m)
            .background(PaceColor.surface, in: shape)
            .overlay(shape.strokeBorder(PaceColor.danger.opacity(0.5), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
