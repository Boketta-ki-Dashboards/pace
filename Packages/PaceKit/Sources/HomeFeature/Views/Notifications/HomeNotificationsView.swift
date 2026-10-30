import DesignSystem
import PaceCore
import SwiftUI

/// „Mitteilungen“ als Unterseite von Home („‹ Home“ → pace → „Mitteilungen“): eingehende Freundschaftsanfragen,
/// Gruppeneinladungen und ungelesene Chats – ausschließlich echte Einträge. Tippen führt in den Social-Tab.
struct HomeNotificationsScreen: View {
    let viewModel: HomeDashboardViewModel
    let onOpen: (HomeNotificationItem) -> Void

    var body: some View {
        ScrollView {
            HomeNotificationsContent(viewModel: viewModel, onOpen: onOpen)
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.l)
                .paceVerticalScrollLock()
        }
        .refreshable { [viewModel] in
            await viewModel.social.load()
            await viewModel.social.chats.load()
        }
        .paceScreenBackground()
        .paceSubpage()
        .task { [viewModel] in
            await viewModel.loadNotificationsIfNeeded()
        }
    }
}

/// Inhalt der Mitteilungen ohne Scrollen (auch für Snapshot-Tests).
struct HomeNotificationsContent: View {
    let viewModel: HomeDashboardViewModel
    var onOpen: (HomeNotificationItem) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: HomeTexts.home, title: HomeTexts.notifications)

            let items = viewModel.notifications
            if !viewModel.areNotificationsAvailable {
                emptyState(systemImage: "bell.slash", title: HomeTexts.notifications, message: HomeNotifications.unavailableMessage)
            } else if items.isEmpty {
                if viewModel.social.state == .loading || viewModel.social.state == .idle {
                    HomeWidgetLoading(minHeight: 120)
                } else {
                    emptyState(systemImage: "bell", title: HomeNotifications.emptyTitle, message: HomeNotifications.emptyMessage)
                }
            } else {
                VStack(spacing: PaceSpacing.xs) {
                    ForEach(items) { item in
                        Button {
                            onOpen(item)
                        } label: {
                            HomeNotificationRow(item: item)
                        }
                        .buttonStyle(.pacePressable)
                        .accessibilityHint(PaceLocalization.text(
                            de: "Öffnet Social", en: "Opens Social", ru: "Открывает вкладку «Друзья»"
                        ))
                    }
                }
            }
        }
    }

    private func emptyState(systemImage: String, title: String, message: String) -> some View {
        PaceStatusView(systemImage: systemImage, title: title, message: message)
            .paceCardBackground()
            .padding(.top, PaceSpacing.s)
    }
}

/// Eine Mitteilung: Bild bzw. Initialen, Titel, Text, Zeit.
private struct HomeNotificationRow: View {
    let item: HomeNotificationItem

    var body: some View {
        HStack(alignment: .top, spacing: PaceSpacing.s) {
            PaceAvatar(name: item.avatarName, seed: item.avatarSeed, size: 44, image: item.avatar)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PaceColor.onAccent)
                        .frame(width: 20, height: 20)
                        .background(PaceColor.actionFill, in: Circle())
                        .overlay(Circle().strokeBorder(PaceColor.surface, lineWidth: 1.5))
                        .offset(x: 3, y: 3)
                        .accessibilityHidden(true)
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: PaceSpacing.xs)
                    Text(item.date.formatted(.relative(presentation: .named).locale(PaceLocalization.shared.locale)))
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                }
                Text(item.message)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HomeRowChevron()
                .padding(.top, PaceSpacing.xxs)
        }
        .padding(PaceSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paceCardBackground(cornerRadius: PaceRadius.tile)
        .accessibilityElement(children: .combine)
    }
}
