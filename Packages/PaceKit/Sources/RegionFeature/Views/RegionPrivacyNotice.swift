import DesignSystem
import SwiftUI

/// Erklärt, wofür die Region verwendet wird – und wofür nicht.
public struct RegionPrivacyNotice: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            point(
                "trophy.fill",
                "Deine Region ordnet dich ausschließlich regionalen Pace-Rankings zu: Gemeinde, Kreis, Bundesland, Deutschland."
            )
            point("location.slash", "Kein Live-GPS, keine Adresse, keine Koordinaten, keine Standortverfolgung.")
            point("arrow.triangle.2.circlepath", "Du kannst deine Region jederzeit im Profil ändern.")
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
