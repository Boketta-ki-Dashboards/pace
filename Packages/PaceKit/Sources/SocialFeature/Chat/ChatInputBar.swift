import DesignSystem
import PaceCore
import SwiftUI

/// Eingabeleiste (Referenzbild 5): „+“ für Foto oder GIF, mehrzeiliges Textfeld „Nachricht schreiben“ und runder
/// Senden-Knopf. Kann nicht (mehr) geschrieben werden, steht hier stattdessen die Erklärung.
struct ChatInputBar: View {
    @Bindable var viewModel: ChatViewModel
    let onPickMedia: () -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(PaceColor.border)
                .frame(height: 1)
            if let message = viewModel.readOnlyMessage {
                readOnly(message)
            } else if viewModel.state == .loaded {
                bar
            }
        }
        .background(PaceColor.background)
    }

    private var bar: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .bottom, spacing: PaceSpacing.xs) {
                Button(action: onPickMedia) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(PaceColor.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(PaceColor.surface, in: Circle())
                        .overlay(Circle().strokeBorder(PaceColor.border, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.pacePressable)
                .disabled(!viewModel.canSend)
                .accessibilityLabel(ChatUIText.attach)

                TextField(
                    ChatUIText.placeholder,
                    text: $viewModel.draftText,
                    prompt: Text(ChatUIText.placeholder).foregroundStyle(PaceColor.textSecondary),
                    axis: .vertical
                )
                .lineLimit(1...5)
                .font(.body)
                .foregroundStyle(PaceColor.textPrimary)
                .padding(.horizontal, PaceSpacing.m)
                .padding(.vertical, 11)
                .frame(minHeight: 44)
                .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))

                Button(action: onSend) {
                    Image(systemName: "paperplane")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(PaceColor.onAccent)
                        .frame(width: 44, height: 44)
                        .background(PaceColor.actionFill, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.pacePressable)
                .disabled(!viewModel.canSubmitText)
                .opacity(viewModel.canSubmitText ? 1 : 0.45)
                .accessibilityLabel(ChatUIText.send)
            }
            if let remaining = viewModel.remainingCharacters {
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
