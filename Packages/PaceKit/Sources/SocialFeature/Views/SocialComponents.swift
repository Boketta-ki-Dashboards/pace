import DesignSystem
import PaceCore
import SwiftUI

// MARK: - Seitenrahmen

extension View {
    /// Rahmen einer Social-Unterseite: scrollbar, Seitenabstand, Hintergrund, ohne Systemleiste (eigener Kopf).
    func socialSubpageScroll() -> some View {
        ScrollView {
            self
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.l)
                .paceVerticalScrollLock()
        }
        .scrollDismissesKeyboard(.interactively)
        .paceScreenBackground()
        .paceSubpage()
    }
}

/// Kopf einer Social-Unterseite ohne eigenen Seitentitel (Gruppendetails, Referenzbild 4): „‹ Social“ und die
/// Pace-Wortmarke – gleiche Schrift, Farbe und Größe wie ``PaceSubpageHeader``; darunter folgt der Kopf der Gruppe.
struct SocialBackHeader: View {
    let backTitle: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(.body, weight: .semibold))
                    Text(backTitle)
                        .font(.body)
                        .lineLimit(1)
                }
                .foregroundStyle(PaceColor.accent)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PaceLocalization.text(
                de: "Zurück zu \(backTitle)", en: "Back to \(backTitle)", ru: "Назад: \(backTitle)"
            ))
            PaceWordmark(height: 33)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Abschnittstitel wie „Suchergebnisse“, „Top-Freunde“ oder „Eingegangen · 3“.
struct SocialSectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaceSpacing.xs) {
            Text(title)
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(PaceColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: PaceSpacing.xs)
            trailing()
        }
        .padding(.top, PaceSpacing.xs)
    }
}

extension SocialSectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - Hinweise und Zustände

/// Rückmeldung der letzten Aktion, z. B. „Anfrage gesendet“.
struct NoticeBanner: View {
    let notice: SocialViewModel.Notice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: PaceSpacing.s) {
            Image(systemName: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? PaceColor.danger : PaceColor.accent)
                .accessibilityHidden(true)
            Text(notice.text)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PaceColor.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -12)
            .padding(.trailing, -10)
            .accessibilityLabel(SocialText.closeNotice)
        }
        .padding(PaceSpacing.s)
        .background(
            notice.isError ? PaceColor.danger.opacity(0.1) : PaceColor.accentSoft,
            in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Gestalteter Hinweis, wenn Social auf dem Server (noch) nicht eingerichtet ist.
struct SocialUnavailableCard: View {
    let message: String

    var body: some View {
        PaceCard {
            HStack(alignment: .top, spacing: PaceSpacing.m) {
                Image(systemName: "person.2")
                    .font(.title2)
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 52, height: 52)
                    .background(PaceColor.accentSoft, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                    Text(SocialText.friendsAndGroups)
                        .font(PaceFont.cardTitle)
                        .foregroundStyle(PaceColor.textPrimary)
                    Text(message)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(SocialText.regionalRankingsIndependent)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Ladefehler mit „Erneut versuchen“.
struct SocialFailedCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                Label {
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "wifi.exclamationmark")
                }
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
                Button(SocialText.retry, action: onRetry)
                    .buttonStyle(.paceSecondary)
            }
        }
    }
}

/// Ladezustand in einer Karte.
struct SocialLoadingCard: View {
    let message: String

    var body: some View {
        PaceCard {
            HStack(spacing: PaceSpacing.s) {
                ProgressView()
                Text(message)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        }
    }
}

/// Leerer Zustand in einer Karte (Symbol, Titel, Erklärung).
struct SocialEmptyCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        PaceCard {
            VStack(spacing: PaceSpacing.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 60, height: 60)
                    .background(PaceColor.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                Text(message)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Personen

/// Ergebnis- bzw. Anfragekarte (Referenzbilder 1 und 2): Profilbild, Anzeigename, @Benutzername und rechts die
/// Aktionen. Profilbild und Name öffnen das Profil – unabhängig von den Aktionen rechts.
struct SocialPersonCard<Actions: View>: View {
    let profile: SocialProfile
    var detail: String?
    var onOpenProfile: (() -> Void)?
    /// Kompakte Zeile wie die Suchergebnisse in Referenzbild 1 (kleineres Bild und kleinere Schrift).
    var compact = false
    @ViewBuilder let actions: () -> Actions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var avatarSize: CGFloat { compact ? 52 : 56 }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Sehr große Schrift: Aktionen unter den Namen, damit nichts abgeschnitten wird.
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    profileButton
                    HStack(spacing: PaceSpacing.xs) {
                        actions()
                    }
                }
            } else {
                // Wie Referenzbild 1 in einer Zeile; bleibt für den Namen zu wenig Platz (schmale iPhones, lange
                // Status wie „Bereits befreundet“), stehen die Aktionen darunter – ohne abgeschnittene Texte.
                InlineOrStackedLayout(minimumLeadingWidth: avatarSize + PaceSpacing.s + 70) {
                    profileButton
                    HStack(spacing: PaceSpacing.xxs) {
                        actions()
                    }
                    .fixedSize()
                }
            }
        }
        .padding(.leading, PaceSpacing.s)
        .padding(.trailing, PaceSpacing.xs)
        .padding(.vertical, PaceSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paceCardBackground(cornerRadius: PaceRadius.card)
    }

    @ViewBuilder
    private var profileButton: some View {
        if let onOpenProfile {
            Button(action: onOpenProfile) {
                identity
            }
            .buttonStyle(.pacePressable)
            .accessibilityHint(SocialText.openProfileHint)
        } else {
            identity
        }
    }

    private var identity: some View {
        HStack(spacing: PaceSpacing.s) {
            PaceAvatar(name: profile.shownName, seed: profile.publicID.uuidString, size: avatarSize, image: profile.avatar)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.shownName)
                    .font(.system(compact ? Font.TextStyle.subheadline : Font.TextStyle.headline, weight: .semibold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail ?? "@\(profile.username)")
                    .font(compact ? Font.footnote : PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Status statt Aktion, z. B. „Bereits befreundet“ mit Haken (Referenzbild 1) oder „Ausstehend“ mit Uhr.
struct SocialStatusLabel: View {
    enum Style {
        /// Mint gefüllt mit Haken („Bereits befreundet“).
        case filled
        /// Nur Symbol und Text („Ausstehend“, „Anfrage gesendet“).
        case plain
    }

    let text: String
    let systemImage: String
    var style: Style = .filled

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.subheadline, weight: style == .filled ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(style == .filled ? PaceColor.onSelection : PaceColor.textSecondary)
        .padding(.horizontal, style == .filled ? PaceSpacing.s : 0)
        .frame(minHeight: 40)
        .background {
            if style == .filled {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PaceColor.selectionFill)
            }
        }
    }
}

/// „…“-Knopf in Ergebniszeilen (grau, wie Referenzbild 1) – als Beschriftung eines `Menu`.
struct SocialMoreLabel: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(PaceColor.textSecondary)
            .frame(width: 36, height: 38)
            .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - Gruppen

/// Gruppenbild oder – solange keins gesetzt ist – ein ruhiger Platzhalter mit dem Symbol der Gruppenart.
public struct GroupAvatar: View {
    let name: String
    let kind: GroupKind
    let image: MediaReference?
    var size: CGFloat = 56

    public init(name: String, kind: GroupKind, image: MediaReference?, size: CGFloat = 56) {
        self.name = name
        self.kind = kind
        self.image = image
        self.size = size
    }

    public var body: some View {
        if let image {
            PaceAvatar(name: name, seed: name, size: size, image: image)
        } else {
            Image(systemName: kind.systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                // Im Dunkelmodus wären selectionFill und accentStrong fast gleich hell – daher accentSoft/accent.
                .foregroundStyle(PaceColor.accent)
                .frame(width: size, height: size)
                .background(PaceColor.accentSoft, in: Circle())
                .accessibilityHidden(true)
        }
    }
}

/// Zeile einer Gruppe mit Flamme, Serie und heutigem Stand (auch für das Gruppen-Modul auf Home).
public struct GroupStreakRow: View {
    private let group: GroupSummary
    private let showsChevron: Bool

    public init(group: GroupSummary, showsChevron: Bool = false) {
        self.group = group
        self.showsChevron = showsChevron
    }

    public var body: some View {
        PaceTile(isHighlighted: group.todayComplete) {
            HStack(spacing: PaceSpacing.s) {
                GroupAvatar(name: group.name, kind: group.kind, image: group.image, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(SocialText.groupRowDetail(reached: group.todayReachedCount, required: group.todayRequiredCount, memberCount: group.memberCount))
                        .font(PaceFont.caption)
                        .foregroundStyle(group.todayComplete ? PaceColor.accent : PaceColor.textSecondary)
                        // Darf umbrechen: auf schmalen iPhones passt die Zeile neben Flamme und Serie nicht immer.
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: PaceSpacing.xs)
                HStack(spacing: 4) {
                    Image(systemName: group.currentStreak > 0 ? "flame.fill" : "flame")
                        .foregroundStyle(group.currentStreak > 0 ? PaceColor.streak : PaceColor.textSecondary)
                        .accessibilityHidden(true)
                    Text(group.currentStreak.paceFormatted)
                        .font(PaceFont.headline)
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SocialText.groupRowAccessibility(
            name: group.name, streak: group.currentStreak, reached: group.todayReachedCount, required: group.todayRequiredCount
        ))
    }
}

/// Zeile mit Symbol, Titel, optionalem Zähler und Pfeil (z. B. „Freundschaftsanfragen 2 ›“, Referenzbild 9).
struct SocialNavigationRow: View {
    let systemImage: String
    let title: String
    var detail: String?
    var count = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: PaceSpacing.xs)
                if count > 0 {
                    PaceCountBadge(count)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PaceColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PaceSpacing.m)
            .padding(.vertical, PaceSpacing.s)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .paceCardBackground(cornerRadius: PaceRadius.tile)
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Auswahlzeile mit Haken (Empfänger, Mitglieder einladen, Privatsphäre).
struct SocialSelectableRow<Leading: View>: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                leading()
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
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? PaceColor.accent : PaceColor.textSecondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PaceSpacing.s)
            .padding(.vertical, PaceSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                isSelected ? PaceColor.accentSoft : PaceColor.surface,
                in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                    .strokeBorder(isSelected ? PaceColor.accent.opacity(0.45) : PaceColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// Zwei Bausteine: links der Name, rechts die Aktionen – in einer Zeile, solange links mindestens
/// `minimumLeadingWidth` bleibt, sonst die Aktionen rechtsbündig in einer zweiten Zeile. Die Aktionen behalten immer
/// ihre volle Breite (keine gekürzten Knopftexte).
struct InlineOrStackedLayout: Layout {
    var spacing: CGFloat = PaceSpacing.xs
    var minimumLeadingWidth: CGFloat = 96

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let trailing = subviews[1].sizeThatFits(.unspecified)
        guard let width = proposal.width else {
            let leading = subviews[0].sizeThatFits(.unspecified)
            return CGSize(width: leading.width + spacing + trailing.width, height: max(leading.height, trailing.height))
        }
        if isInline(width: width, trailing: trailing) {
            let leading = subviews[0].sizeThatFits(ProposedViewSize(width: width - trailing.width - spacing, height: nil))
            return CGSize(width: width, height: max(leading.height, trailing.height))
        }
        let leading = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: leading.height + spacing + trailing.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let trailing = subviews[1].sizeThatFits(.unspecified)
        if isInline(width: bounds.width, trailing: trailing) {
            let leadingWidth = bounds.width - trailing.width - spacing
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: leadingWidth, height: nil)
            )
            subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(trailing))
        } else {
            let leading = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.maxX, y: bounds.minY + leading.height + spacing),
                anchor: .topTrailing,
                proposal: ProposedViewSize(trailing)
            )
        }
    }

    private func isInline(width: CGFloat, trailing: CGSize) -> Bool {
        width - trailing.width - spacing >= minimumLeadingWidth
    }
}
