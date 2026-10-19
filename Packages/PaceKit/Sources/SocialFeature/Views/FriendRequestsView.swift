import DesignSystem
import PaceCore
import SwiftUI

/// Freundschaftsanfragen (Referenzbild 2): eingegangene mit „Annehmen“/„Ablehnen“, gesendete mit „Ausstehend“ und
/// „Zurückziehen“. Jede Aktion geht an den Server; danach sind Liste, Zähler und Hauptseite auf dem neuen Stand.
struct FriendRequestsView: View {
    let viewModel: SocialViewModel
    let onOpen: (SocialRoute) -> Void

    var body: some View {
        FriendRequestsContent(viewModel: viewModel, onOpenProfile: { onOpen(.profile($0)) })
            .socialSubpageScroll()
            .refreshable { [viewModel] in await viewModel.load() }
            .task { [viewModel] in await viewModel.loadIfNeeded() }
    }
}

/// Inhalt der Anfragen mit Kopfzeile (ohne Scrollen) – auch für Snapshot-Tests.
struct FriendRequestsContent: View {
    let viewModel: SocialViewModel
    var onOpenProfile: (SocialProfile) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: SocialText.social, title: SocialText.friendRequests)
            if let notice = viewModel.notice {
                NoticeBanner(notice: notice) { viewModel.dismissNotice() }
            }
            switch viewModel.state {
            case .unavailable(let message):
                SocialUnavailableCard(message: message)
            case .failed(let message):
                SocialFailedCard(message: message) {
                    Task { await viewModel.load() }
                }
            case .idle, .loading:
                SocialLoadingCard(message: SocialText.loading)
            case .loaded:
                if viewModel.requests.isEmpty {
                    SocialEmptyCard(systemImage: "person.2", title: SocialText.noRequestsTitle, message: SocialText.noRequestsMessage)
                } else {
                    incoming
                    outgoing
                }
            }
        }
    }

    @ViewBuilder
    private var incoming: some View {
        let requests = viewModel.incomingRequests
        SocialSectionTitle(SocialText.sectionCount(SocialText.incoming, requests.count))
        if requests.isEmpty {
            Text(SocialText.noIncomingRequests)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
                .padding(.horizontal, PaceSpacing.xxs)
        }
        ForEach(requests) { request in
            SocialPersonCard(profile: request.profile, onOpenProfile: { onOpenProfile(request.profile) }) {
                SocialStackedActions {
                    Button {
                        Task { await viewModel.respond(to: request, accept: true) }
                    } label: {
                        Label(SocialText.accept, systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.paceAction)
                    .accessibilityLabel(SocialText.acceptRequest(from: request.profile.displayName))
                    Button {
                        Task { await viewModel.respond(to: request, accept: false) }
                    } label: {
                        Label(SocialText.decline, systemImage: "person.badge.minus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.paceOutline)
                    .accessibilityLabel(SocialText.declineRequest(from: request.profile.displayName))
                }
                .disabled(viewModel.busyIDs.contains(request.id))
            }
        }
    }

    @ViewBuilder
    private var outgoing: some View {
        let requests = viewModel.outgoingRequests
        if !requests.isEmpty {
            SocialSectionTitle(SocialText.sectionCount(SocialText.sent, requests.count))
                .padding(.top, PaceSpacing.s)
            ForEach(requests) { request in
                SocialPersonCard(profile: request.profile, onOpenProfile: { onOpenProfile(request.profile) }) {
                    SocialStackedActions {
                        SocialStatusLabel(text: SocialText.pending, systemImage: "clock", style: .plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            Task { await viewModel.cancel(request) }
                        } label: {
                            Label(SocialText.withdraw, systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.paceOutline)
                        .accessibilityLabel(SocialText.withdrawRequest(to: request.profile.displayName))
                    }
                    .disabled(viewModel.busyIDs.contains(request.id))
                }
            }
        }
    }
}

/// Zwei übereinanderliegende, gleich breite Aktionen rechts in einer Karte (Referenzbild 2).
struct SocialStackedActions<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: PaceSpacing.xs) {
            content()
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
