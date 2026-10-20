import DesignSystem
import PaceCore
import SwiftUI

/// Erklärt, wofür die Region verwendet wird – und wofür nicht.
public struct RegionPrivacyNotice: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            point(
                "trophy.fill",
                PaceLocalization.text(
                    de: "Deine Region ordnet dich ausschließlich regionalen Pace-Rankings zu: Gemeinde, Kreis, Bundesland, Deutschland.",
                    en: "Your region is used only to place you in regional Pace rankings: municipality, district, state, Germany.",
                    ru: "Регион нужен только для региональных рейтингов Pace: населённый пункт, район, федеральная земля, Германия."
                )
            )
            point(
                "location.slash",
                PaceLocalization.text(
                    de: "Kein Live-GPS, keine Adresse, keine Koordinaten, keine Standortverfolgung.",
                    en: "No live GPS, no address, no coordinates, no location tracking.",
                    ru: "Без GPS в реальном времени, адреса, координат и отслеживания местоположения."
                )
            )
            point(
                "arrow.triangle.2.circlepath",
                PaceLocalization.text(
                    de: "Du kannst deine Region jederzeit im Profil ändern.",
                    en: "You can change your region in your profile at any time.",
                    ru: "Регион можно в любой момент изменить в профиле."
                )
            )
        }
        .padding(PaceSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
    }

    private func point(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: PaceSpacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(PaceColor.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    RegionPrivacyNotice()
        .padding()
}
