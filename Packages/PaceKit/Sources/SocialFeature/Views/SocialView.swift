import DesignSystem
import SwiftUI

/// Social-Tab: zentraler Ort für Freunde, Anfragen, Gruppen und Einladungen.
public struct SocialView: View {
    private let viewModel: SocialViewModel

    public init(viewModel: SocialViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                SocialContent(viewModel: viewModel)
                    .padding(.horizontal, PaceSpacing.m)
                    .padding(.bottom, PaceSpacing.l)
            }
            .paceScreenBackground()
            .navigationTitle("Social")
        }
    }
}

/// Inhalt des Social-Tabs (ohne Navigation und Scrollen).
struct SocialContent: View {
    let viewModel: SocialViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            intro
            ForEach(viewModel.sections) { section in
                SocialSectionCard(section: section)
            }
        }
    }

    private var intro: some View {
        PaceCard {
            HStack(alignment: .top, spacing: PaceSpacing.m) {
                Image(systemName: "figure.walk.motion")
                    .font(.title2)
                    .foregroundStyle(PaceColor.onAccent)
                    .frame(width: 52, height: 52)
                    .background(PaceColor.accentStrong, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                    Text("Gemeinsam mehr bewegen")
                        .font(PaceFont.cardTitle)
                        .foregroundStyle(PaceColor.textPrimary)
                    Text("Freunde, Gruppen und Einladungen kommen mit dem nächsten Update. Deine regionalen Rankings "
                        + "laufen schon jetzt.")
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct SocialSectionCard: View {
    let section: SocialViewModel.Section

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack(alignment: .center, spacing: PaceSpacing.s) {
                    Image(systemName: section.systemImage)
                        .font(.headline)
                        .foregroundStyle(PaceColor.accentStrong)
                        .frame(width: 36, height: 36)
                        .background(PaceColor.accentSoft, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(section.title)
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                        Text(section.subtitle)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    Spacer(minLength: PaceSpacing.xs)
                    if section.availability == .comingSoon {
                        Text("Bald")
                            .font(PaceFont.micro.weight(.semibold))
                            .foregroundStyle(PaceColor.accentStrong)
                            .padding(.horizontal, PaceSpacing.xs)
                            .padding(.vertical, 3)
                            .background(PaceColor.accentSoft, in: Capsule())
                    }
                }
                PaceTile {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.emptyTitle)
                            .font(PaceFont.callout.weight(.semibold))
                            .foregroundStyle(PaceColor.textPrimary)
                        Text(section.emptyMessage)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, PaceSpacing.xxs)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
