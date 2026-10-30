import AVFoundation
import DesignSystem
import PaceCore
import PhotosUI
import SwiftUI
import UIKit

/// Chatliste mit Filter Alle/Freunde/Gruppen auf der Social-Hauptseite (Referenzbild 9). Die Überschrift „Chats“
/// zeichnet die Hauptseite selbst.
///
/// Aktuell gehalten wird die Liste app-weit (`ChatListViewModel.observe()` in der Tab-Ansicht), damit auch das
/// Ungelesen-Badge am Social-Tab live stimmt, während ein anderer Tab offen ist.
public struct ChatListSection: View {
    private let viewModel: ChatListViewModel
    private let onOpen: (ChatTarget) -> Void

    public init(viewModel: ChatListViewModel, onOpen: @escaping (ChatTarget) -> Void) {
        self.viewModel = viewModel
        self.onOpen = onOpen
    }

    public var body: some View {
        ChatListContent(viewModel: viewModel, onOpen: onOpen)
    }
}

/// Ein Chat (Referenzbild 5) – Gruppenchat oder, im gleichen Design, Privatchat.
///
/// Aufbau von oben nach unten: fester Kopf (Zurück oben links, Wortmarke, Name, Info/Einstellungen), scrollbarer
/// Verlauf (Gruppen- bzw. Profilkopf, Nachrichten) und die Eingabeleiste. Die Eingabeleiste steht unter dem Verlauf
/// und damit immer sichtbar über der Tab-Leiste bzw. – bei offener Tastatur – direkt über der Tastatur.
///
/// Navigation in Social-Seiten (Gruppendetails, Gruppeneinstellungen, Mitglieder) läuft über `onOpenRoute`, Profile
/// über `onOpenProfile` – im Social-Tab beide über den ``SocialNavigator``.
public struct ChatView: View {
    private let viewModel: ChatViewModel
    private let backTitle: String?
    private let onOpenRoute: (SocialRoute) -> Void
    private let onOpenProfile: (SocialProfile) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.paceTabIsActive) private var isTabActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsPhotoPicker = false
    @State private var showsGIFPicker = false
    @State private var showsProfileShare = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var viewerItem: ChatViewerItem?
    @State private var dialog: ChatDialog?
    @State private var showsDialog = false
    @State private var scroll = ChatScrollTracker()
    @State private var recorder = ChatVoiceRecorder()
    @State private var voicePlayer = ChatVoicePlayer()
    @State private var showsFavorites = false

    private nonisolated static let scrollSpace = "pace.chat.scroll"
    private nonisolated static let bottomAnchor = "pace.chat.bottom"

    /// - Parameters:
    ///   - backTitle: Ziel des Zurück-Links; ohne Angabe „Social“.
    ///   - onOpenRoute: Öffnet eine Social-Seite (Gruppe, Mitglieder, Einstellungen).
    ///   - onOpenProfile: Öffnet ein Profil (Gegenüber, Absender, geteiltes Profil).
    public init(
        viewModel: ChatViewModel,
        backTitle: String? = nil,
        onOpenRoute: @escaping (SocialRoute) -> Void = { _ in },
        onOpenProfile: @escaping (SocialProfile) -> Void
    ) {
        self.viewModel = viewModel
        self.backTitle = backTitle
        self.onOpenRoute = onOpenRoute
        self.onOpenProfile = onOpenProfile
    }

    public var body: some View {
        VStack(spacing: 0) {
            ChatTitleBar(viewModel: viewModel, backTitle: backTitle ?? SocialText.social, actions: actions(proxy: nil))
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.xs)
            // Gruppen: feste Leiste mit Mitgliedern und Flamme (scrollt nicht mit).
            ChatGroupBar(viewModel: viewModel, actions: actions(proxy: nil))
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.xxs)
            if let pin = viewModel.shownPin, let preview = viewModel.shownPinPreview {
                ChatPinBanner(
                    preview: preview,
                    onTap: { [viewModel] in
                        Task { await viewModel.openShownPin() }
                    },
                    onUnpin: viewModel.canPin ? { [viewModel] in
                        Task { await viewModel.unpin(pin) }
                    } : nil
                )
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.xs)
            }
            timeline
                .environment(voicePlayer)
            ChatInputBar(
                viewModel: viewModel,
                recorder: recorder,
                player: voicePlayer,
                attachments: ChatAttachmentActions(
                    onPhoto: { showsPhotoPicker = true },
                    onGIF: { showsGIFPicker = true },
                    onProfile: { showsProfileShare = true }
                ),
                onSend: { [viewModel] in
                    Task { await viewModel.sendText() }
                },
                onSendVoice: sendVoice,
                onDiscardVoice: discardVoice
            )
        }
        .paceScreenBackground()
        .paceSubpage()
        // Sichtbar heißt: App aktiv und der Social-Tab gewählt (andere Tabs lassen den Chat im Pager stehen) – nur dann
        // gilt er als gelesen und unterdrückt Hinweise auf neue Nachrichten.
        .task(id: scenePhase == .active && isTabActive) { [viewModel, scenePhase, isTabActive] in
            guard scenePhase == .active, isTabActive else { return }
            await viewModel.observe()
        }
        .onChange(of: isTabActive) { _, isActive in
            if !isActive {
                recorder.interrupt()
                voicePlayer.pause()
            }
        }
        // Während einer Aufnahme keine Wiedergabe (der Wechsel der Audio-Sitzung würde die Aufnahme beenden).
        .onChange(of: recorder.isRecording) { _, isRecording in
            voicePlayer.isBlocked = isRecording
        }
        // Nicht mehr schreibberechtigt (z. B. blockiert, aus der Gruppe entfernt): laufende Aufnahme verwerfen.
        .onChange(of: viewModel.canSend) { _, canSend in
            if !canSend {
                discardVoice()
            }
        }
        // Hintergrund oder Unterbrechung (Anruf): Aufnahme als Vorschau behalten, Wiedergabe pausieren. Kurzes
        // „inaktiv“ (Kontrollzentrum, Mitteilungsbanner) unterbricht nicht.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                recorder.interrupt()
                voicePlayer.pause()
            }
        }
        // Nur der Beginn einer Unterbrechung zählt; das Ende (oder Hinweise anderer Apps) beendet keine Aufnahme.
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began
            else { return }
            recorder.interrupt()
            voicePlayer.pause()
        }
        // Chat verlassen: nichts nimmt weiter auf, nichts spielt weiter, keine Datei bleibt liegen.
        .onDisappear {
            recorder.cancel()
            voicePlayer.stop()
        }
        .sheet(isPresented: $showsFavorites) {
            ChatFavoritesSheet(viewModel: viewModel) { [viewModel] messageID in
                showsFavorites = false
                Task { await viewModel.jump(to: messageID) }
            }
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickerItem, matching: .images, preferredItemEncoding: .current)
        // GIF suchen: Die Datei wird wie ein GIF aus der Mediathek in den geschützten Chat-Speicher hochgeladen.
        .sheet(isPresented: $showsGIFPicker) {
            GIFPickerSheet(search: viewModel.gifSearch) { [viewModel] data in
                Task { await viewModel.sendMedia(data, contentType: ChatMediaSupport.gifContentType) }
            }
        }
        .sheet(isPresented: $showsProfileShare) {
            ChatProfileShareSheet(profiles: viewModel.shareableProfiles, ownPublicID: viewModel.ownPublicID) { [viewModel] profile in
                Task { await viewModel.shareProfile(profile) }
            }
        }
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

    // MARK: Verlauf

    /// Scrollbarer Verlauf. Der Inhalt ist mindestens so hoch wie der sichtbare Bereich und oben ausgerichtet – kurze
    /// Chats beginnen also oben unter dem Kopf, lange öffnen am Ende.
    private var timeline: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ChatBody(viewModel: viewModel, actions: actions(proxy: proxy))
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchor)
                    }
                    .padding(.horizontal, PaceSpacing.m)
                    .padding(.top, PaceSpacing.xxs)
                    .padding(.bottom, PaceSpacing.s)
                    .paceVerticalScrollLock()
                    .onGeometryChange(for: CGRect.self) { content in
                        content.frame(in: .named(Self.scrollSpace))
                    } action: { frame in
                        let shouldStick = scroll.update(
                            contentBottom: frame.maxY,
                            contentHeight: frame.height,
                            viewportHeight: geometry.size.height
                        )
                        if shouldStick {
                            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                }
                .coordinateSpace(.named(Self.scrollSpace))
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.lastEntryID) { oldValue, newValue in
                    guard newValue != nil else { return }
                    let follow = scroll.newLastEntry(isOwn: viewModel.lastEntryIsOwn, isFirstEntry: oldValue == nil)
                    guard follow else { return }
                    withAnimation(reduceMotion || oldValue == nil ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                    }
                }
                // Tastatur ein/aus: Wer unten war, bleibt unten.
                .onChange(of: geometry.size.height) {
                    if scroll.isPinnedToBottom {
                        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                    }
                }
                .overlay(alignment: .bottom) {
                    if scroll.hasUnseenMessages {
                        ChatNewMessagesButton {
                            scroll.scrolledToBottom()
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                            }
                        }
                        .padding(.bottom, PaceSpacing.s)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: scroll.hasUnseenMessages)
                // Sprung zu einer Nachricht (Antwort-Verweis, Pin, Favorit): hinscrollen, kurz hervorheben.
                .onChange(of: viewModel.jumpRequest) { _, request in
                    guard let request else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                        proxy.scrollTo("message-\(request.messageID.uuidString)", anchor: .center)
                    }
                    Task { [viewModel] in
                        try? await Task.sleep(for: .seconds(1.6))
                        viewModel.finishJump(request)
                    }
                }
            }
        }
    }

    // MARK: Sprachnachrichten

    private func sendVoice() {
        voicePlayer.stop()
        guard let recording = recorder.takeRecording() else { return }
        Task { [viewModel] in
            await viewModel.sendVoice(recording.data, duration: recording.duration)
        }
    }

    private func discardVoice() {
        voicePlayer.stop()
        recorder.cancel()
    }

    // MARK: Aktionen

    private func actions(proxy: ScrollViewProxy?) -> ChatActions {
        ChatActions(
            openRoute: onOpenRoute,
            openProfile: onOpenProfile,
            openMedia: { item in viewerItem = item },
            loadOlder: { [viewModel] in
                let anchor = viewModel.timeline.first { item in
                    if case .entry = item { return true }
                    return false
                }?.id
                Task { @MainActor in
                    await viewModel.loadOlder()
                    if let anchor {
                        proxy?.scrollTo(anchor, anchor: .top)
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
            },
            messageAction: { [viewModel] action, message in
                switch action {
                case .reply:
                    viewModel.startReply(to: message)
                case .copy:
                    UIPasteboard.general.string = message.text
                case .edit:
                    viewModel.startEditing(message)
                case .favorite, .unfavorite:
                    Task { await viewModel.toggleFavorite(message) }
                case .pin, .unpin:
                    Task { await viewModel.togglePin(message) }
                }
            },
            jumpTo: { [viewModel] messageID in
                Task { await viewModel.jump(to: messageID) }
            },
            openFavorites: {
                showsFavorites = true
            }
        )
    }

    /// Ausgewähltes Foto bzw. GIF vorbereiten und senden.
    private func send(_ item: PhotosPickerItem) {
        viewModel.beginPreparingMedia()
        Task { [viewModel] in
            defer { viewModel.endPreparingMedia() }
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
        case .block(let profile): SocialText.blockTitle(profile.shownName)
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

/// Hinweis „Neue Nachrichten“, wenn neue Nachrichten eintreffen, während ältere gelesen werden. Antippen springt ans
/// Ende des Verlaufs.
struct ChatNewMessagesButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.footnote.weight(.bold))
                Text(ChatUIText.newMessages)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(PaceColor.onAccent)
            .padding(.horizontal, PaceSpacing.m)
            .frame(minHeight: 40)
            .background(PaceColor.actionFill, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.pacePressable)
        .accessibilityHint(ChatUIText.newMessagesHint)
    }
}
