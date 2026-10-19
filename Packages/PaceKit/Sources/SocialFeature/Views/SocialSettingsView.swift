import DesignSystem
import PaceCore
import SwiftUI

/// Social-Einstellungen: Anfragen und Gruppeneinladungen, Sichtbarkeit in der Suche (im Profil), blockierte Nutzer.
struct SocialSettingsView: View {
    @State private var model: SocialSettingsViewModel
    private let social: SocialViewModel
    private let onOpen: (SocialRoute) -> Void

    init(model: SocialSettingsViewModel, social: SocialViewModel, onOpen: @escaping (SocialRoute) -> Void) {
        _model = State(initialValue: model)
        self.social = social
        self.onOpen = onOpen
    }

    var body: some View {
        SocialSettingsContent(model: model, social: social, onOpen: onOpen)
            .socialSubpageScroll()
            .refreshable { [model] in await model.load() }
            .task { [model] in await model.load() }
    }
}

/// Inhalt der Social-Einstellungen mit Kopfzeile (ohne Scrollen) – auch für Snapshot-Tests.
struct SocialSettingsContent: View {
    let model: SocialSettingsViewModel
    let social: SocialViewModel
    var onOpen: (SocialRoute) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: SocialText.social, title: SocialText.socialSettings)
            if let notice = social.notice {
                NoticeBanner(notice: notice) { social.dismissNotice() }
            }
            SocialNavigationRow(
                systemImage: "person.badge.plus",
                title: SocialText.friendRequests,
                count: model.incomingRequestCount,
                action: { onOpen(.requests) }
            )
            SocialNavigationRow(
                systemImage: "envelope",
                title: SocialText.groupInvitations,
                count: model.invitationCount,
                action: { onOpen(.groups) }
            )

            SocialSectionTitle(SocialText.searchVisibility)
            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    Text(SocialText.searchVisibilityText)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.canOpenPrivacySettings {
                        Button {
                            model.openPrivacySettings()
                        } label: {
                            Label(SocialText.openProfileSettings, systemImage: "person.crop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.paceSecondary)
                    }
                }
            }

            SocialSectionTitle(SocialText.blockedUsers)
            blockedUsers
            Text(SocialText.blockedUsersHint)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PaceSpacing.xxs)

            SocialSectionTitle(SocialText.notifications)
            Text(SocialText.pushNotReady)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PaceSpacing.xxs)
        }
    }

    @ViewBuilder
    private var blockedUsers: some View {
        switch model.blocked {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 60)
        case .unavailable(let message):
            PaceCard {
                Text(message)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failed(let message):
            SocialFailedCard(message: message) {
                Task { await model.load() }
            }
        case .loaded(let users):
            if users.isEmpty {
                PaceCard {
                    Text(SocialText.noBlockedUsers)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                }
            } else {
                ForEach(users) { user in
                    SocialPersonCard(profile: user) {
                        Button {
                            Task { await model.unblock(user) }
                        } label: {
                            Text(SocialText.unblock)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .buttonStyle(.paceOutline)
                        .disabled(model.isBusy(user))
                    }
                }
            }
        }
    }
}
