import DesignSystem
import SwiftUI

/// „Deine Freunde“. Freundschaften kommen mit dem nächsten Update; bis dahin ein vorbereiteter, ehrlicher Leerzustand.
struct FriendsPreviewCardView: View {
    let onOpenSocial: () -> Void

    var body: some View {
        Button(action: onOpenSocial) {
            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader("Deine Freunde", actionTitle: "Alle ansehen")
                    HStack(spacing: PaceSpacing.m) {
                        PlaceholderAvatars()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Noch keine Freunde")
                                .font(PaceFont.headline)
                                .foregroundStyle(PaceColor.textPrimary)
                            Text("Bald kannst du Freunde einladen und euch jeden Tag vergleichen.")
                                .font(PaceFont.caption)
                                .foregroundStyle(PaceColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .buttonStyle(.pacePressable)
    }
}

/// „Deine Gruppen“ – Klassen-, Arbeits- und eigene Gruppen folgen mit dem nächsten Update.
struct GroupsPreviewCardView: View {
    let onOpenSocial: () -> Void

    var body: some View {
        Button(action: onOpenSocial) {
            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader("Deine Gruppen", actionTitle: "Alle ansehen")
                    HStack(spacing: PaceSpacing.m) {
                        Image(systemName: "person.3.fill")
                            .font(.title3)
                            .foregroundStyle(PaceColor.accentStrong)
                            .frame(width: 52, height: 52)
                            .background(PaceColor.accentSoft, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Klassen- und Arbeitsgruppen")
                                .font(PaceFont.headline)
                                .foregroundStyle(PaceColor.textPrimary)
                            Text("Gemeinsam Schritte sammeln – bald verfügbar.")
                                .font(PaceFont.caption)
                                .foregroundStyle(PaceColor.textSecondary)
                        }
                    }
                }
            }
        }
        .buttonStyle(.pacePressable)
    }
}

/// Drei angedeutete Profilbilder für Leerzustände.
private struct PlaceholderAvatars: View {
    var body: some View {
        HStack(spacing: -14) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(PaceColor.textSecondary.opacity(0.6))
                    .frame(width: 44, height: 44)
                    .background(PaceColor.surfaceSecondary, in: Circle())
                    .overlay(Circle().strokeBorder(PaceColor.border, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .zIndex(Double(3 - index))
            }
        }
        .accessibilityHidden(true)
    }
}
