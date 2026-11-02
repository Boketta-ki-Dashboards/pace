import PaceCore
import SwiftUI

/// Kopf eines Pace-Profils (Social-Profil 2.0): Banner, Profilbild leicht überlappend, Anzeigename, Benutzername,
/// optional Bio, Interessen, gesprochene Sprachen, Land und freigegebene Auszeichnungen. Für das eigene und fremde
/// Profile gleich – nur zeigen fremde Profile zunächst wenige Interessen (``ProfileInterestRules/compactCount``), den
/// Rest über „Alle Interessen ansehen“.
///
/// Fehlt eine Angabe, entfällt sie ohne Platzhalter (beim eigenen Profil kann ``bioPrompt`` „Bio hinzufügen“ zeigen).
/// Ohne Banner erscheint eine ruhige Fläche in Pace-Farben – kein Foto.
public struct PaceProfileShowcase<Actions: View>: View {
    private let displayName: String
    private let username: String
    private let seed: String
    private let avatar: MediaReference?
    private let details: ProfileDetails
    private let bioPrompt: (() -> Void)?
    private let showsAllInterests: Bool
    private let actions: Actions

    @State private var expandsInterests = false
    @ScaledMetric(relativeTo: .title) private var scaledAvatarSize: CGFloat = 84

    /// Mit großer Schrift wächst das Profilbild mit, aber begrenzt – daneben stehen die Aktionen.
    private var avatarSize: CGFloat { min(scaledAvatarSize, 104) }

    /// - Parameters:
    ///   - username: ohne „@“.
    ///   - bioPrompt: Beim eigenen Profil ohne Bio: „Bio hinzufügen“ öffnet die Bearbeitung.
    ///   - showsAllInterests: Eigenes Profil: alle Interessen; fremde: zunächst kompakt.
    ///   - actions: Knöpfe rechts neben dem Profilbild (z. B. „Profil bearbeiten“, Teilen).
    public init(
        displayName: String,
        username: String,
        seed: String,
        avatar: MediaReference?,
        details: ProfileDetails,
        bioPrompt: (() -> Void)? = nil,
        showsAllInterests: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) {
        self.displayName = displayName
        self.username = username
        self.seed = seed
        self.avatar = avatar
        self.details = details
        self.bioPrompt = bioPrompt
        self.showsAllInterests = showsAllInterests
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Ein gefülltes Bild meldet seine Füllgröße – erst hier auf die Bannerhöhe zuschneiden (sonst ragt es
            // auf breiten Geräten unter den Bannerrand).
            PaceProfileBanner(reference: details.banner)
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .clipped()
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack(alignment: .bottom, spacing: PaceSpacing.s) {
                    PaceAvatar(name: displayName, seed: seed, size: avatarSize, image: avatar)
                        .padding(3)
                        .background(PaceColor.surface, in: Circle())
                        .offset(y: -avatarSize / 3)
                        .padding(.bottom, -avatarSize / 3)
                    Spacer(minLength: PaceSpacing.xs)
                    actions
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(PaceFont.title)
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "@\(username)")
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if let bio = details.bio {
                    // Reiner Text (keine Links, kein Markdown) – nutzergenerierter Inhalt.
                    Text(verbatim: bio)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let bioPrompt {
                    Button(action: bioPrompt) {
                        Label(PaceLocalization.text(de: "Bio hinzufügen", en: "Add a bio", ru: "Добавить описание"), systemImage: "plus")
                            .font(PaceFont.callout.weight(.semibold))
                            .foregroundStyle(PaceColor.accent)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pacePressable)
                }
                interests
                background
                if !details.visibleAchievements.isEmpty {
                    PaceFlowLayout(spacing: PaceSpacing.xs) {
                        ForEach(details.visibleAchievements) { achievement in
                            PaceProfileChip(title: achievement.title, systemImage: achievement.systemImage, isAchievement: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(PaceLocalization.text(de: "Auszeichnungen", en: "Achievements", ru: "Награды") + ": "
                        + details.visibleAchievements.map(\.title).joined(separator: ", "))
                }
            }
            .padding(.horizontal, PaceSpacing.m)
            .padding(.bottom, PaceSpacing.m)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous)
                .strokeBorder(PaceColor.border, lineWidth: 1)
        )
    }
}

extension PaceProfileShowcase {
    /// Katalog-Interessen übersetzt, eigene so, wie sie eingegeben wurden.
    @ViewBuilder private var interests: some View {
        let all = details.allInterests
        if !all.isEmpty {
            let isCompact = !showsAllInterests && !expandsInterests && all.count > ProfileInterestRules.compactCount
            let visible = isCompact ? Array(all.prefix(ProfileInterestRules.compactCount)) : all
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                PaceFlowLayout(spacing: PaceSpacing.xs) {
                    ForEach(visible) { item in
                        PaceProfileChip(title: item.title, systemImage: item.systemImage)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(PaceLocalization.text(de: "Interessen", en: "Interests", ru: "Интересы") + ": "
                    + all.map(\.title).joined(separator: ", "))
                if isCompact {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { expandsInterests = true }
                    } label: {
                        Text(PaceLocalization.text(
                            de: "Alle Interessen ansehen (\(all.count))",
                            en: "See all interests (\(all.count))",
                            ru: "Все интересы (\(all.count))"
                        ))
                        .font(PaceFont.callout.weight(.semibold))
                        .foregroundStyle(PaceColor.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pacePressable)
                }
            }
        }
    }

    /// Gesprochene Sprachen und Land als eigene kompakte Zeilen (nicht zwischen den Interessen).
    @ViewBuilder private var background: some View {
        if !details.spokenLanguages.isEmpty || details.countryCode != nil {
            VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                if !details.spokenLanguages.isEmpty {
                    PaceProfileFactRow(
                        systemImage: "character.bubble",
                        title: PaceLocalization.text(de: "Sprachen", en: "Languages", ru: "Языки"),
                        value: details.spokenLanguages.map(SpokenLanguageCatalog.name(for:)).joined(separator: " · ")
                    )
                }
                if let code = details.countryCode {
                    PaceProfileFactRow(
                        systemImage: "globe.europe.africa",
                        title: PaceLocalization.text(de: "Verbunden mit", en: "Connected to", ru: "Близкая страна"),
                        value: "\(ProfileCountryCatalog.flag(for: code)) \(ProfileCountryCatalog.name(for: code))"
                    )
                }
            }
        }
    }
}

/// Kompakte Zeile „Sprachen: Deutsch · Russisch“ im Profilkopf.
struct PaceProfileFactRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaceSpacing.xs) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PaceColor.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(line)
                .font(PaceFont.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var line: AttributedString {
        var label = AttributedString(title + ": ")
        label.foregroundColor = PaceColor.textSecondary
        var content = AttributedString(value)
        content.foregroundColor = PaceColor.textPrimary
        return label + content
    }
}

/// Profilbanner: das hochgeladene Bild (Querformat, gefüllt) oder eine ruhige Fläche in Pace-Farben.
public struct PaceProfileBanner: View {
    private let reference: MediaReference?

    public init(reference: MediaReference?) {
        self.reference = reference
    }

    public var body: some View {
        ZStack {
            // Neutraler Hintergrund – auch während das Banner lädt.
            LinearGradient(
                colors: [PaceColor.accentSoft, PaceColor.selectionFill.opacity(0.85), PaceColor.accentSoft],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let reference {
                PaceRemoteImage(reference, contentMode: .fill)
            } else {
                Image(systemName: "figure.walk")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(PaceColor.accent.opacity(0.18))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Kompakter Tag für Interessen und Auszeichnungen.
public struct PaceProfileChip: View {
    private let title: String
    private let systemImage: String?
    private let isAchievement: Bool

    /// - Parameter systemImage: `nil` bei eigenen Interessen (nur Text).
    public init(title: String, systemImage: String?, isAchievement: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.isAchievement = isAchievement
    }

    public var body: some View {
        Label {
            // Eigene Interessen sind nutzergenerierter Text: wörtlich, ohne Markdown.
            Text(verbatim: title)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(isAchievement ? PaceColor.streak : PaceColor.accent)
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(PaceColor.textPrimary)
        .padding(.horizontal, PaceSpacing.s)
        .padding(.vertical, 6)
        .background(isAchievement ? PaceColor.fieldBackground : PaceColor.accentSoft, in: Capsule())
        .overlay(Capsule().strokeBorder(PaceColor.border, lineWidth: isAchievement ? 1 : 0))
    }
}

/// Zeilenumbrechendes Layout für Tags (füllt Zeilen von links, bricht bei Bedarf um).
public struct PaceFlowLayout: Layout {
    private let spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let usedWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? usedWidth, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                let clamped = CGSize(width: min(size.width, bounds.width), height: size.height)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(clamped))
                x += clamped.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            let needed = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            if !current.indices.isEmpty, needed > width {
                rows.append(current)
                current = Row(indices: [], y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            current.indices.append(index)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
