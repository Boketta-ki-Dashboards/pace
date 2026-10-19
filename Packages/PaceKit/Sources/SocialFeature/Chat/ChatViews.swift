import DesignSystem
import PaceCore
import PhotosUI
import SwiftUI

/// Chatliste mit Filter Alle/Freunde/Gruppen auf der Social-Hauptseite (Referenzbild 9). Die Überschrift „Chats“
/// zeichnet die Hauptseite selbst.
///
/// Solange die Liste sichtbar ist und die App im Vordergrund läuft, hält sie sich per Echtzeit und regelmäßigem
/// Abfragen aktuell.
public struct ChatListSection: View {
    @Bindable private var viewModel: ChatListViewModel
    private let onOpen: (ChatTarget) -> Void

    @Environment(\.scenePhase) private var scenePhase

    public init(viewModel: ChatListViewModel, onOpen: @escaping (ChatTarget) -> Void) {
        self.viewModel = viewModel
        self.onOpen = onOpen
    }

    public var body: some View {
        ChatListContent(viewModel: viewModel, onOpen: onOpen)
            .task(id: scenePhase == .active) { [viewModel, scenePhase] in
                guard scenePhase == .active else { return }
                await viewModel.observe()
            }
    }
}

/// Ein Chat (Referenzbild 5) – Gruppenchat oder, im gleichen Design, Privatchat.
///
/// Navigation in Social-Seiten (Gruppendetails, Gruppeneinstellungen, Mitglieder) läuft über `onOpenRoute`; ohne
/// Angabe über `NavigationLink(value: SocialRoute…)`, die der Social-Tab registriert. Profile öffnet `onOpenProfile`.
public struct ChatView: View {
    @Bindable private var viewModel: ChatViewModel
    private let backTitle: String?
    private let onOpenRoute: ((SocialRoute) -> Void)?
    private let onOpenProfile: (SocialProfile) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsPhotoPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var viewerItem: ChatViewerItem?
    @State private var dialog: ChatDialog?
    @State private var showsDialog = false

    /// - Parameters:
    ///   - backTitle: Ziel des Zurück-Links; ohne Angabe „Social“.
    ///   - onOpenRoute: Öffnet eine Social-Seite; ohne Angabe per `NavigationLink(value:)`.
    ///   - onOpenProfile: Öffnet ein Profil (Gegenüber, Absender, geteiltes Profil).
    public init(
        viewModel: ChatViewModel,
        backTitle: String? = nil,
        onOpenRoute: ((SocialRoute) -> Void)? = nil,
        onOpenProfile: @escaping (SocialProfile) -> Void
    ) {
        self.viewModel = viewModel
        self.backTitle = backTitle
        self.onOpenRoute = onOpenRoute
        self.onOpenProfile = onOpenProfile
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    ChatContent(
                        viewModel: viewModel,
                        backTitle: backTitle ?? SocialText.social,
                        actions: actions(proxy: proxy)
                    )
                    .padding(.horizontal, PaceSpacing.m)
                    .padding(.bottom, PaceSpacing.s)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.lastEntryID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .bottom)
                    }
                }
            }
            ChatInputBar(
                viewModel: viewModel,
                onPickMedia: { showsPhotoPicker = true },
                onSend: { [viewModel] in
                    Task { await viewModel.sendText() }
                }
            )
        }
        .paceScreenBackground()
        .paceSubpage()
        .task(id: scenePhase == .active) { [viewModel, scenePhase] in
            guard scenePhase == .active else { return }
            await viewModel.observe()
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickerItem, matching: .images, preferredItemEncoding: .current)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            send(item)
        }
        .fullScreenCover(item: $viewerItem) { item in
            ChatImageViewer(item: item)
        }
        .confirmationDialog(
            dialogTitle,
            isPresented: $showsDialog,
            titleVisibility: .visible,
            presenting: dialog
        ) { dialog in
            dialogActions(dialog)
        } message: { dialog in
            dialogMessage(dialog)
        }
    }

    // MARK: Aktionen

    private func actions(proxy: ScrollViewProxy) -> ChatActions {
        ChatActions(
            openRoute: onOpenRoute,
            openProfile: onOpenProfile,
            openMedia: { item in viewerItem = item },
            loadOlder: { [viewModel] in
                let anchor = viewModel.timeline.first { item in
                    if case .entry = item { return true }
                    return false
                }?.id
                Task {
                    await viewModel.loadOlder()
                    if let anchor {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                }
            },
            retryLoad: { [viewModel] in
                Task { await viewModel.load() }
            },
            refresh: { [viewModel] in
                Task { await viewModel.refresh() }
            },
            retry: { [viewModel] clientID in
                Task { await viewModel.retry(clientID) }
            },
            discard: { [viewModel] clientID in
                viewModel.discard(clientID)
            },
            reveal: { [viewModel] messageID in
                viewModel.reveal(messageID)
            },
            dismissNotice: { [viewModel] in
                viewModel.dismissNotice()
            },
            confirm: { dialog in
                self.dialog = dialog
                showsDialog = true
            }
        )
    }

    /// Ausgewähltes Foto bzw. GIF vorbereiten und senden.
    private func send(_ item: PhotosPickerItem) {
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            pickerItem = nil
            guard let data, let prepared = ChatMediaProcessing.prepare(data) else {
                viewModel.reportMediaSelectionFailed()
                return
            }
            await viewModel.sendMedia(prepared.data, contentType: prepared.contentType)
        }
    }

    // MARK: Dialoge

    private var dialogTitle: String {
        switch dialog {
        case .delete: ChatUIText.deleteTitle
        case .block(let profile): SocialText.blockTitle(profile.displayName)
        case .report: SocialText.reportReasonPrompt
        case nil: ""
        }
    }

    @ViewBuilder
    private func dialogActions(_ dialog: ChatDialog) -> some View {
        switch dialog {
        case .delete(let message):
            Button(ChatUIText.delete, role: .destructive) { [viewModel] in
                Task { await viewModel.delete(message) }
            }
        case .block(let profile):
            Button(SocialText.blockUser, role: .destructive) { [viewModel] in
                Task { await viewModel.block(profile) }
            }
        case .report(let subject):
            ForEach(ReportReason.allCases) { reason in
                Button(reason.title) { [viewModel] in
                    Task {
                        switch subject {
                        case .message(let message): await viewModel.report(message, reason: reason)
                        case .conversation: await viewModel.reportConversation(reason: reason)
                        }
                    }
                }
            }
        }
        Button(SocialText.cancel, role: .cancel) {}
    }

    @ViewBuilder
    private func dialogMessage(_ dialog: ChatDialog) -> some View {
        switch dialog {
        case .delete: Text(ChatUIText.deleteMessage)
        case .block: Text(SocialText.blockMessage)
        case .report: Text(SocialText.reportInfo)
        }
    }
}
