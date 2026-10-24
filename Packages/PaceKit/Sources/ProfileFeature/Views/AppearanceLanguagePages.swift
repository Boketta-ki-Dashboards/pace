import DesignSystem
import PaceCore
import SwiftUI

// MARK: - Darstellung

/// Darstellung & Sprache: Automatisch/Hell/Dunkel, App-Icon und der Weg zur Sprache.
struct AppearancePage: View {
    let viewModel: ProfileViewModel
    let backTitle: String

    var body: some View {
        ProfileSubpage {
            AppearancePageContent(viewModel: viewModel, backTitle: backTitle) { viewModel.open($0) }
        }
    }
}

struct AppearancePageContent: View {
    let viewModel: ProfileViewModel
    let backTitle: String
    var onOpen: (ProfileRoute) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.appearance.title)
                .padding(.bottom, PaceSpacing.xs)

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader(PaceLocalization.text(de: "Farbschema", en: "Color scheme", ru: "Цветовая схема"))
                    HStack(spacing: PaceSpacing.xs) {
                        ForEach(AppearancePreference.allCases) { appearance in
                            AppearanceOption(appearance: appearance, isSelected: viewModel.appearance == appearance) {
                                viewModel.setAppearance(appearance)
                            }
                        }
                    }
                    ProfileFootnote(text: PaceLocalization.text(
                        de: "„Automatisch“ folgt der Einstellung deines iPhones. Deine Wahl gilt sofort und bleibt gespeichert. Die Bildschirmhelligkeit deines iPhones ändert Pace nicht.",
                        en: "“Automatic” follows your iPhone's setting. Your choice applies immediately and is saved. Pace never changes your iPhone's screen brightness.",
                        ru: "«Автоматически» следует настройке iPhone. Выбор применяется сразу и сохраняется. Яркость экрана iPhone Pace не меняет."
                    ))
                }
            }

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader(PaceLocalization.text(de: "App-Icon", en: "App icon", ru: "Значок приложения"))
                    HStack(alignment: .top, spacing: PaceSpacing.s) {
                        ForEach(AppIconChoice.allCases) { choice in
                            AppIconOption(
                                choice: choice,
                                isSelected: viewModel.appIcon == choice,
                                isEnabled: viewModel.supportsAppIconChange && !viewModel.isChangingAppIcon
                            ) {
                                Task { await viewModel.selectAppIcon(choice) }
                            }
                        }
                    }
                    if let error = viewModel.appIconError {
                        ProfileFootnote(text: error, isError: true)
                    }
                    ProfileFootnote(text: viewModel.supportsAppIconChange
                        ? PaceLocalization.text(
                            de: "„Automatisch“ folgt der Darstellung deines Home-Bildschirms (hell, dunkel oder getönt, ab iOS 18). iOS bestätigt den Wechsel mit einem kurzen Hinweis.",
                            en: "“Automatic” follows your Home Screen appearance (light, dark or tinted, from iOS 18). iOS confirms the change with a short notice.",
                            ru: "«Автоматически» следует оформлению экрана «Домой» (светлое, тёмное или тонированное, с iOS 18). iOS подтвердит смену коротким уведомлением."
                        )
                        : PaceLocalization.text(
                            de: "Auf diesem Gerät lässt sich das App-Icon nicht ändern. iOS erlaubt hier keine alternativen App-Icons.",
                            en: "The app icon can't be changed on this device. iOS doesn't allow alternative app icons here.",
                            ru: "На этом устройстве значок приложения изменить нельзя: iOS не поддерживает здесь альтернативные значки."
                        ))
                }
            }

            // Sprache gehört zur Kategorie „Darstellung & Sprache“ – dieselbe Seite wie bisher.
            ProfileSettingsRow(
                systemImage: "globe",
                title: ProfileRoute.language.title,
                value: viewModel.languageSummary
            ) { onOpen(.language) }
        }
    }
}

/// Auswahlkachel für Automatisch/Hell/Dunkel.
private struct AppearanceOption: View {
    let appearance: AppearancePreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: PaceSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(height: 28)
                    .accessibilityHidden(true)
                Text(appearance.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isSelected ? PaceColor.onSelection : PaceColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                isSelected ? PaceColor.selectionFill : PaceColor.fieldBackground,
                in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                    .strokeBorder(isSelected ? PaceColor.accent : PaceColor.border, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
        }
        .buttonStyle(.pacePressable)
        .accessibilityLabel(appearance.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var systemImage: String {
        switch appearance {
        case .automatic: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

/// Eine Icon-Variante zur Auswahl: Vorschau, Name, Auswahlmarkierung.
private struct AppIconOption: View {
    let choice: AppIconChoice
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: PaceSpacing.xs) {
                PaceAppIconPreview(variant, size: 60)
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(isSelected ? PaceColor.accentStrong : .clear, lineWidth: 2.5)
                    )
                HStack(spacing: PaceSpacing.xxs) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(PaceColor.accentStrong)
                            .accessibilityHidden(true)
                    }
                    Text(choice.title)
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(PaceFont.callout)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pacePressable)
        .disabled(!isEnabled)
        .opacity(isEnabled || isSelected ? 1 : 0.5)
        .accessibilityLabel(PaceLocalization.text(
            de: "App-Icon \(choice.title)",
            en: "App icon \(choice.title)",
            ru: "Значок: \(choice.title)"
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var variant: PaceAppIconPreview.Variant {
        switch choice {
        case .automatic: .automatic
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Sprache

/// Sprache: Wie iPhone, Deutsch, English, Русский – wirkt sofort und bleibt gespeichert.
struct LanguagePage: View {
    let viewModel: ProfileViewModel
    let backTitle: String

    var body: some View {
        ProfileSubpage {
            LanguagePageContent(viewModel: viewModel, backTitle: backTitle)
        }
    }
}

struct LanguagePageContent: View {
    let viewModel: ProfileViewModel
    let backTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.language.title)
                .padding(.bottom, PaceSpacing.xs)

            PaceCard {
                VStack(spacing: PaceSpacing.xs) {
                    ForEach(viewModel.languageChoices) { choice in
                        LanguageRow(choice: choice, isSelected: viewModel.language == choice.preference) {
                            Task { await viewModel.setLanguage(choice.preference) }
                        }
                    }
                }
            }

            ProfileNoteRow(systemImage: "textformat", text: PaceLocalization.text(
                de: "Die Sprache wechselt sofort in der ganzen App. Zahlen und Datumsangaben folgen der gewählten Sprache. Namen von Personen und Gruppen werden nicht übersetzt.",
                en: "The language changes immediately throughout the app. Numbers and dates follow the chosen language. Names of people and groups are not translated.",
                ru: "Язык сразу меняется во всём приложении. Числа и даты отображаются в формате выбранного языка. Имена людей и названия групп не переводятся."
            ))
            .padding(.horizontal, PaceSpacing.xxs)
            ProfileNoteRow(systemImage: "iphone", text: PaceLocalization.text(
                de: "„Wie iPhone“ verwendet die Sprache deines iPhones bzw. die Sprache, die du in den iOS-Einstellungen für Pace gewählt hast. Wird sie nicht unterstützt, erscheint Pace auf Deutsch.",
                en: "“Same as iPhone” uses your iPhone's language or the language you chose for Pace in iOS Settings. If it isn't supported, Pace appears in German.",
                ru: "«Как на iPhone» использует язык iPhone или язык, выбранный для Pace в настройках iOS. Если он не поддерживается, Pace отображается на немецком."
            ))
            .padding(.horizontal, PaceSpacing.xxs)
        }
    }
}

/// Zeile einer Sprache mit Häkchen.
private struct LanguageRow: View {
    let choice: LanguageChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PaceTile(isHighlighted: isSelected) {
                HStack(spacing: PaceSpacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(choice.title)
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                        if let subtitle = choice.subtitle {
                            Text(subtitle)
                                .font(PaceFont.caption)
                                .foregroundStyle(PaceColor.textSecondary)
                        }
                    }
                    Spacer(minLength: PaceSpacing.xs)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? PaceColor.accentStrong : PaceColor.textSecondary.opacity(0.5))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, PaceSpacing.xxs)
                .frame(minHeight: 44)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
