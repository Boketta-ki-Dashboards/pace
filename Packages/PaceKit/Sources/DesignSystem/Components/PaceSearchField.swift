import PaceCore
import SwiftUI

/// Suchfeld im Pace-Stil: abgerundete graue Fläche, Lupe links, Löschen-Button rechts.
public struct PaceSearchField: View {
    private let prompt: String
    @Binding private var text: String
    private let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    public init(_ prompt: String, text: Binding<String>, onSubmit: @escaping () -> Void = {}) {
        self.prompt = prompt
        _text = text
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: PaceSpacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(PaceColor.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .font(.system(.body))
                .foregroundStyle(PaceColor.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(PaceColor.textSecondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PaceLocalization.text(de: "Suche löschen", en: "Clear search", ru: "Очистить поиск"))
            }
        }
        .padding(.horizontal, PaceSpacing.m)
        .frame(minHeight: 50)
        .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
