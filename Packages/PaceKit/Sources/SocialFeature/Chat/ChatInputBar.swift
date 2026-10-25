import DesignSystem
import PaceCore
import SwiftUI

/// Eingabeleiste (Referenzbild 5): „+“ öffnet die Anhangsauswahl (Foto aus der Mediathek, GIF suchen, Profil teilen),
/// mehrzeiliges Textfeld „Nachricht schreiben“ und runder
/// Knopf rechts – Mikrofon bei leerem Feld, sonst Senden. Darüber bei Bedarf die Vorschau der beantworteten bzw. zu
/// bearbeitenden Nachricht. Kann nicht (mehr) geschrieben werden, steht hier stattdessen die Erklärung.
///
/// Sprachnachricht: Mikrofon gedrückt halten nimmt auf, nach oben wischen sperrt (dann Stopp, Verwerfen, Senden), nach
/// links wischen verwirft. Nach dem Loslassen erscheint eine Vorschau – gesendet wird erst nach „Senden“.
struct ChatInputBar: View {
    @Bindable var viewModel: ChatViewModel
    let recorder: ChatVoiceRecorder
    let player: ChatVoicePlayer
    let attachments: ChatAttachmentActions
    let onSend: () -> Void
    let onSendVoice: () -> Void
    let onDiscardVoice: () -> Void

    @FocusState private var isFieldFocused: Bool
    /// Der Finger liegt auf dem Mikrofon (eine Aufnahme-Geste läuft).
    @State private var isHoldingMic = false
    @GestureState private var micPressed = false
    @State private var micTranslation: CGSize = .zero

    /// So weit nach oben bzw. links, bis gesperrt bzw. verworfen wird.
    private static let lockDistance: CGFloat = 70
    private static let cancelDistance: CGFloat = 110

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(PaceColor.border)
                .frame(height: 1)
            if let message = viewModel.readOnlyMessage {
                readOnly(message)
            } else if viewModel.state == .loaded {
                if let editing = viewModel.editingMessage {
                    contextBanner(
                        systemImage: "pencil",
                        title: ChatUIText.editingMessage,
                        snippet: ChatReplySnippet.text(for: editing),
                        cancelLabel: ChatUIText.cancelEditing,
                        onCancel: { viewModel.cancelEditing() }
                    )
                    .disabled(viewModel.isSavingEdit)
                } else if let reply = viewModel.replyingTo {
                    contextBanner(
                        systemImage: "arrowshape.turn.up.left",
                        title: ChatUIText.replyingTo(viewModel.replyAuthor(of: reply)),
                        snippet: ChatReplySnippet.text(for: reply),
                        cancelLabel: ChatUIText.cancelReply,
                        onCancel: { viewModel.cancelReply() }
                    )
                }
                if let hint = recorder.hint {
                    hintRow(hint)
                }
                bar
            }
        }
        .background(PaceColor.background)
        .onChange(of: viewModel.replyingTo?.id) { _, id in
            if id != nil { isFieldFocused = true }
        }
        .onChange(of: viewModel.editingMessage?.id) { _, id in
            if id != nil { isFieldFocused = true }
        }
        // Geste vom System abgebrochen (z. B. Anruf): Aufnahme nicht festhalten lassen.
        .onChange(of: micPressed) { _, pressed in
            if !pressed, isHoldingMic {
                endMicGesture()
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.phase)
    }

    private var bar: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .bottom, spacing: PaceSpacing.xs) {
                if recorder.phase == .idle {
                    attachButton
                    textField
                } else {
                    ChatVoiceRecordingRow(
                        recorder: recorder,
                        player: player,
                        cancelProgress: min(max(-micTranslation.width / Self.cancelDistance, 0), 1),
                        onDiscard: onDiscardVoice,
                        onStop: { recorder.finish() }
                    )
                }
                trailingButton
            }
            if let remaining = viewModel.remainingCharacters, recorder.phase == .idle {
                Text(ChatUIText.remaining(remaining))
                    .font(PaceFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(remaining < 0 ? PaceColor.danger : PaceColor.textSecondary)
                    .padding(.trailing, 52)
            }
        }
        .padding(.horizontal, PaceSpacing.m)
        .padding(.vertical, PaceSpacing.xs)
    }

    /// Kompaktes Menü direkt am „+“ (natives Kontextmenü, schließt sich nach der Wahl selbst).
    private var attachButton: some View {
        Menu {
            Button(action: attachments.onPhoto) {
                Label(ChatUIText.attachPhoto, systemImage: "photo.on.rectangle")
            }
            Button(action: attachments.onGIF) {
                Label(ChatUIText.attachGIF, systemImage: "magnifyingglass")
            }
            Button(action: attachments.onProfile) {
                Label(ChatUIText.attachProfile, systemImage: "person.crop.circle")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(PaceColor.textPrimary)
                .frame(width: 44, height: 44)
                .background(PaceColor.surface, in: Circle())
                .overlay(Circle().strokeBorder(PaceColor.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .menuOrder(.fixed)
        .disabled(!viewModel.canSend || viewModel.editingMessage != nil)
        .accessibilityLabel(ChatUIText.attach)
    }

    private var textField: some View {
        TextField(
            ChatUIText.placeholder,
            text: $viewModel.draftText,
            prompt: Text(ChatUIText.placeholder).foregroundStyle(PaceColor.textSecondary),
            axis: .vertical
        )
        .focused($isFieldFocused)
        .lineLimit(1...5)
        .font(.body)
        .foregroundStyle(PaceColor.textPrimary)
        .padding(.horizontal, PaceSpacing.m)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))
    }

    // MARK: Senden bzw. Mikrofon

    /// Mikrofon statt Senden: leeres Feld, kein Bearbeiten – oder während einer festgehaltenen Aufnahme.
    private var showsMic: Bool {
        switch recorder.phase {
        case .recording(locked: false):
            return true
        case .recording(locked: true), .preview:
            return false
        case .idle:
            return viewModel.canSend && viewModel.editingMessage == nil
                && viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var sendsVoice: Bool {
        recorder.phase == .preview || recorder.phase == .recording(locked: true)
    }

    /// Senden und Mikrofon liegen übereinander, damit eine laufende Aufnahme-Geste beim Wechsel (z. B. nach dem
    /// Sperren) nicht abreißt.
    private var trailingButton: some View {
        ZStack {
            sendButton
                .opacity(showsMic ? 0 : 1)
                .allowsHitTesting(!showsMic && !isHoldingMic)
                .accessibilityHidden(showsMic)
            micButton
                .opacity(showsMic ? 1 : 0)
                .allowsHitTesting(showsMic || isHoldingMic)
                .accessibilityHidden(!showsMic)
        }
        .frame(width: 44, height: 44)
        .animation(.easeOut(duration: 0.15), value: showsMic)
    }

    private var sendButton: some View {
        let enabled = sendsVoice || (viewModel.canSubmitText && !viewModel.isSavingEdit)
        return Button {
            if sendsVoice {
                onSendVoice()
            } else {
                onSend()
            }
        } label: {
            Image(systemName: viewModel.editingMessage != nil && !sendsVoice ? "checkmark" : "paperplane")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(PaceColor.onAccent)
                .frame(width: 44, height: 44)
                .background(PaceColor.actionFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.pacePressable)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(sendsVoice ? ChatUIText.voiceSend : (viewModel.editingMessage != nil ? ChatUIText.saveEdit : ChatUIText.send))
    }

    private var micButton: some View {
        let isRecording = recorder.isRecording
        return Image(systemName: "mic.fill")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(isRecording ? Color.white : PaceColor.onAccent)
            .frame(width: 44, height: 44)
            .background(isRecording ? PaceColor.danger : PaceColor.actionFill, in: Circle())
            .scaleEffect(isRecording ? 1.25 : 1)
            .offset(y: isRecording ? min(0, micTranslation.height) / 3 : 0)
            .animation(.easeOut(duration: 0.15), value: isRecording)
            .contentShape(Circle())
            .gesture(
                // Globale Koordinaten: Schließt sich beim Start der Aufnahme die Tastatur, rutscht die Eingabeleiste unter
                // dem ruhenden Finger nach unten – lokal gemessen sähe das wie „nach oben gewischt“ aus und sperrte die
                // Aufnahme ungewollt.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($micPressed) { _, state, _ in state = true }
                    .onChanged { value in micChanged(value.translation) }
                    .onEnded { _ in endMicGesture() }
            )
            .accessibilityElement()
            .accessibilityLabel(ChatUIText.voiceRecord)
            .accessibilityHint(ChatUIText.voiceRecordHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                // VoiceOver: Aufnahme gesperrt starten; Stopp, Verwerfen und Senden erscheinen als Knöpfe.
                Task {
                    if await recorder.start() {
                        recorder.lock()
                    }
                }
            }
    }

    private func micChanged(_ translation: CGSize) {
        if !isHoldingMic {
            isHoldingMic = true
            micTranslation = .zero
            player.stop()
            Task {
                let started = await recorder.start()
                // Schon losgelassen, bevor die Aufnahme lief: sofort beenden (zu kurz → Hinweis).
                if started, !isHoldingMic, recorder.phase == .recording(locked: false) {
                    recorder.finish()
                }
            }
            return
        }
        micTranslation = translation
        guard recorder.phase == .recording(locked: false) else { return }
        if translation.height < -Self.lockDistance, abs(translation.width) < Self.cancelDistance / 2 {
            recorder.lock()
        } else if translation.width < -Self.cancelDistance {
            onDiscardVoice()
        }
    }

    private func endMicGesture() {
        guard isHoldingMic else { return }
        isHoldingMic = false
        micTranslation = .zero
        if recorder.phase == .recording(locked: false) {
            recorder.finish()
        }
    }

    // MARK: Hinweise

    private func contextBanner(
        systemImage: String,
        title: String,
        snippet: String,
        cancelLabel: String,
        onCancel: @escaping () -> Void
    ) -> some View {
        HStack(spacing: PaceSpacing.s) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(PaceColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(PaceFont.caption.weight(.semibold))
                    .foregroundStyle(PaceColor.accent)
                    .lineLimit(1)
                Text(snippet)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(PaceColor.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .accessibilityLabel(cancelLabel)
        }
        .padding(.leading, PaceSpacing.m)
        .padding(.trailing, PaceSpacing.xs)
        .padding(.top, PaceSpacing.xxs)
        .background(PaceColor.surface)
    }

    private func hintRow(_ hint: String) -> some View {
        HStack(spacing: PaceSpacing.xs) {
            Image(systemName: "mic")
                .foregroundStyle(PaceColor.textSecondary)
                .accessibilityHidden(true)
            Text(hint)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PaceSpacing.m)
        .padding(.top, PaceSpacing.xs)
        .task(id: hint) {
            try? await Task.sleep(for: .seconds(4))
            recorder.clearHint()
        }
    }

    private func readOnly(_ message: String) -> some View {
        HStack(alignment: .top, spacing: PaceSpacing.s) {
            Image(systemName: "lock")
                .foregroundStyle(PaceColor.textSecondary)
                .accessibilityHidden(true)
            Text(message)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PaceSpacing.m)
        .padding(.vertical, PaceSpacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// Aktionen der Anhangsauswahl am „+“.
struct ChatAttachmentActions {
    /// Foto oder GIF aus der Mediathek.
    let onPhoto: () -> Void
    /// GIF-Suche (z. B. GIPHY).
    let onGIF: () -> Void
    /// Eigenes Profil oder das eines Freundes in den Chat teilen.
    let onProfile: () -> Void
}
