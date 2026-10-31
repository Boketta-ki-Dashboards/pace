import DesignSystem
import PaceCore
import SwiftUI

/// „Willkommen bei Pace! 👋“ – die ausführliche Systemmitteilung mit den wichtigsten Funktionen und Links zu
/// vorhandenen Ansichten. Beim Öffnen gilt sie als gelesen (``HomeDashboardViewModel/open(_:)``).
struct WelcomeMessageScreen: View {
    let viewModel: HomeDashboardViewModel
    let onExploreHome: () -> Void

    var body: some View {
        ScrollView {
            WelcomeMessageContentView(viewModel: viewModel, onExploreHome: onExploreHome)
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.l)
                .paceVerticalScrollLock()
        }
        .paceScreenBackground()
        .paceSubpage()
        .onAppear { viewModel.systemMessages.markRead(.welcome) }
    }
}

struct WelcomeMessageContentView: View {
    let viewModel: HomeDashboardViewModel
    var onExploreHome: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: HomeTexts.notifications, title: SystemMessage(kind: .welcome, createdAt: .now).title, titleSize: .medium)

            HStack(spacing: PaceSpacing.s) {
                PaceAvatar(name: "Pace", seed: "pace-team", size: 40, isHighlighted: true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(SystemMessage(kind: .welcome, createdAt: .now).sender)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                    if let date = viewModel.systemMessages.message(.welcome)?.createdAt {
                        // Datum in der App-Sprache (nicht der iPhone-Sprache), wie in der Mitteilungsliste.
                        Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(PaceLocalization.shared.locale)))
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                }
            }

            Text(WelcomeMessageContent.intro)
                .font(PaceFont.body)
                .foregroundStyle(PaceColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.m) {
                    ForEach(WelcomeMessageContent.sections) { section in
                        HStack(alignment: .top, spacing: PaceSpacing.s) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(section.id == "flame" ? PaceColor.streak : PaceColor.accent)
                                .frame(width: 32, height: 32)
                                .background(PaceColor.accentSoft, in: Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                    .font(PaceFont.headline)
                                    .foregroundStyle(PaceColor.textPrimary)
                                Text(section.text)
                                    .font(PaceFont.callout)
                                    .foregroundStyle(PaceColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            VStack(spacing: PaceSpacing.xs) {
                Button(WelcomeMessageContent.exploreHome, action: onExploreHome)
                    .buttonStyle(.pacePrimary)
                Button(WelcomeMessageContent.openRankings) { viewModel.openRankings(nil) }
                    .buttonStyle(.paceSecondary)
                if let onOpenAddFriend = viewModel.onOpenAddFriend {
                    Button(WelcomeMessageContent.addFriends) { onOpenAddFriend() }
                        .buttonStyle(.paceSecondary)
                }
                if let onOpenHelpBot = viewModel.onOpenHelpBot {
                    Button(WelcomeMessageContent.openHelpBot) { onOpenHelpBot() }
                        .buttonStyle(.paceSecondary)
                }
            }
        }
    }
}
