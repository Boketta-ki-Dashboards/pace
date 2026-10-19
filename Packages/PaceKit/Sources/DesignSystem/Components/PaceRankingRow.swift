import PaceCore
import SwiftUI

/// Ranking-Zeile, gleich auf Home („Dein Umfeld“), in Rankings, Freundes- und Gruppenranglisten:
/// Platz, Profilbild, Name, Schritte, optional Pfeil. Die eigene Zeile ist dezent grün hervorgehoben.
public struct PaceRankingRow: View {
    private let rank: Int
    private let name: String
    private let steps: Int
    private let seed: String
    private let image: MediaReference?
    private let isCurrentUser: Bool
    private let showsStepIcon: Bool
    private let showsChevron: Bool
    private let detail: String?

    /// - Parameters:
    ///   - name: Anzeigename; für die eigene Zeile z. B. „DU“ übergeben, wenn die Referenz das so zeigt.
    ///   - showsStepIcon: Schuh-Symbol vor der Schrittzahl (Gruppen- und Freundeslisten).
    ///   - detail: Optionale zweite Zeile (z. B. „Ziel erreicht“).
    public init(
        rank: Int,
        name: String,
        steps: Int,
        seed: String,
        image: MediaReference? = nil,
        isCurrentUser: Bool,
        showsStepIcon: Bool = false,
        showsChevron: Bool = true,
        detail: String? = nil
    ) {
        self.rank = rank
        self.name = name
        self.steps = steps
        self.seed = seed
        self.image = image
        self.isCurrentUser = isCurrentUser
        self.showsStepIcon = showsStepIcon
        self.showsChevron = showsChevron
        self.detail = detail
    }

    public var body: some View {
        HStack(spacing: PaceSpacing.s) {
            Text("#\(rank.paceFormatted)")
                .font(.system(.headline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isCurrentUser ? PaceColor.accent : PaceColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 40, alignment: .leading)
            PaceAvatar(name: name, seed: seed, size: 36, image: image)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(PaceFont.headline)
                    .foregroundStyle(isCurrentUser ? PaceColor.accent : PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(detail)
                        .font(PaceFont.micro)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: PaceSpacing.xs)
            if showsStepIcon {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(isCurrentUser ? PaceColor.accent : PaceColor.textSecondary)
                    .accessibilityHidden(true)
            }
            Text(steps.paceFormatted)
                .font(.system(.headline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isCurrentUser ? PaceColor.accent : PaceColor.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PaceColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, PaceSpacing.s)
        .padding(.vertical, PaceSpacing.xs)
        .frame(minHeight: 52)
        .background(
            isCurrentUser ? PaceColor.accentSoft : PaceColor.surfaceSecondary,
            in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                .strokeBorder(isCurrentUser ? PaceColor.accent.opacity(0.45) : PaceColor.border, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PaceLocalization.text(
            de: "Platz \(rank.paceFormatted), \(name)", en: "Rank \(rank.paceFormatted), \(name)", ru: "Место \(rank.paceFormatted), \(name)"
        ) + ", " + PaceLocalization.steps(steps))
    }
}

/// Zähler für ungelesene Nachrichten oder offene Anfragen (nur bei mehr als 0 anzeigen).
public struct PaceCountBadge: View {
    private let count: Int

    public init(_ count: Int) {
        self.count = count
    }

    public var body: some View {
        Text(count > 99 ? "99+" : count.paceFormatted)
            .font(.system(.footnote, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(PaceColor.onAccent)
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 26)
            .background(PaceColor.actionFill, in: Capsule())
            .accessibilityLabel(PaceLocalization.plural(
                count,
                de: ("\(count) neu", "\(count) neu"),
                en: ("\(count) new", "\(count) new"),
                ru: ("\(count) новое", "\(count) новых", "\(count) новых")
            ))
    }
}

