import DesignSystem
import PaceCore
import SwiftUI
import UIKit

// MARK: - GIF suchen

/// GIF-Auswahl: Suchfeld, Raster mit kleinen Standbildern (echte Treffer des Anbieters), animierte Vorschau des
/// gewählten GIFs, Senden oder Abbrechen. Ladezustand, keine Treffer, keine Verbindung und „nicht eingerichtet“ haben
/// jeweils einen eigenen Hinweis.
struct GIFPickerSheet: View {
    @State private var picker: GIFPickerViewModel
    let onSend: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    init(search: (any GIFSearching)?, onSend: @escaping (Data) -> Void) {
        _picker = State(initialValue: GIFPickerViewModel(search: search))
        self.onSend = onSend
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        NavigationStack {
            VStack(spacing: PaceSpacing.s) {
                if picker.isAvailable {
                    PaceSearchField(ChatUIText.gifSearchPlaceholder, text: $picker.query)
                        .padding(.horizontal, PaceSpacing.m)
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .padding(.top, PaceSpacing.s)
            .paceScreenBackground()
            .navigationTitle(ChatUIText.attachGIF)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SocialText.cancel) { dismiss() }
                }
            }
            .overlay {
                if let selection = picker.selection {
                    preview(selection)
                }
            }
        }
        // Erst suchen, wenn kurz nichts mehr getippt wurde (spart Anfragen und Kontingent).
        .task(id: picker.query) {
            if GIFRules.query(picker.query) != nil {
                try? await Task.sleep(for: .milliseconds(350))
            }
            guard !Task.isCancelled else { return }
            await picker.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch picker.phase {
        case .loading:
            ProgressView(ChatUIText.gifLoading)
        case .empty:
            PaceStatusView(systemImage: "magnifyingglass", title: ChatUIText.gifNoResultsTitle, message: ChatUIText.gifNoResultsMessage) {
                EmptyView()
            }
            .padding(.horizontal, PaceSpacing.m)
        case .failed(let error):
            PaceStatusView(
                systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
                title: title(for: error),
                message: GIFPickerViewModel.message(for: error)
            ) {
                if error != .notConfigured {
                    Button(SocialText.retry) {
                        Task { await picker.load() }
                    }
                    .buttonStyle(.paceSecondary)
                }
            }
            .padding(.horizontal, PaceSpacing.m)
        case .loaded:
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(picker.results) { result in
                        Button {
                            Task { await picker.select(result) }
                        } label: {
                            GIFStillCell(url: result.stillURL)
                        }
                        .buttonStyle(.pacePressable)
                        .accessibilityLabel(ChatUIText.gifCell(result.title))
                        .task {
                            await picker.loadMoreIfNeeded(after: result)
                        }
                    }
                }
                .padding(.horizontal, PaceSpacing.m)
                if picker.isLoadingMore {
                    ProgressView()
                        .padding(.vertical, PaceSpacing.s)
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    /// Pflichtangabe der Quelle und Datenschutzhinweis.
    @ViewBuilder
    private var footer: some View {
        if let attribution = picker.attribution {
            VStack(spacing: 2) {
                Text(verbatim: attribution)
                    .font(PaceFont.caption.weight(.semibold))
                    .foregroundStyle(PaceColor.textPrimary)
                if let note = picker.privacyNote {
                    Text(note)
                        .font(PaceFont.micro)
                        .foregroundStyle(PaceColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, PaceSpacing.m)
            .padding(.bottom, PaceSpacing.xs)
        }
    }

    private func title(for error: GIFSearchError) -> String {
        switch error {
        case .notConfigured: ChatUIText.gifUnavailableTitle
        case .offline: ChatUIText.gifOfflineTitle
        case .rateLimited, .unsuitableFile, .failed: ChatUIText.gifFailedTitle
        }
    }

    /// Großes, animiertes GIF mit „Senden“ und „Anderes wählen“.
    private func preview(_ selection: GIFPickerViewModel.Selection) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { picker.clearSelection() }
                .accessibilityHidden(true)
            VStack(spacing: PaceSpacing.s) {
                GIFPreviewImage(
                    data: selection.data,
                    id: "\(selection.result.id)-\(selection.data?.count ?? 0)",
                    aspectRatio: selection.result.aspectRatio
                )
                .frame(maxHeight: 280)
                if let error = selection.error {
                    Text(GIFPickerViewModel.message(for: error))
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: PaceSpacing.s) {
                    Button(ChatUIText.gifChooseAnother) { picker.clearSelection() }
                        .buttonStyle(.paceSecondary)
                    Button(ChatUIText.send) {
                        guard let data = picker.dataToSend else { return }
                        onSend(data)
                        dismiss()
                    }
                    .buttonStyle(.pacePrimary)
                    .disabled(picker.dataToSend == nil)
                }
            }
            .padding(PaceSpacing.m)
            .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
            .padding(PaceSpacing.m)
        }
        .transition(.opacity)
    }
}

/// Kleines Standbild im Raster (quadratisch zugeschnitten); kein animiertes GIF, damit viele Treffer wenig Speicher
/// brauchen.
private struct GIFStillCell: View {
    let url: URL

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(PaceColor.textSecondary)
                    case .empty:
                        PaceColor.fieldBackground
                    @unknown default:
                        PaceColor.fieldBackground
                    }
                }
            }
            .background(PaceColor.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// Das gewählte GIF animiert – dekodiert in Blasengröße außerhalb des Main Threads.
private struct GIFPreviewImage: View {
    let data: Data?
    let id: String
    let aspectRatio: Double

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                ChatAnimatedImage(image: image, contentMode: .fit)
            } else {
                PaceColor.fieldBackground
                ProgressView()
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(ChatUIText.gifPreview)
        .task(id: id) {
            guard let data else {
                image = nil
                return
            }
            image = await PaceImageLoader.decoded(data, size: .bubble)
        }
    }
}

// MARK: - Profil teilen

/// Ein Profil in diesen Chat teilen: das eigene oder das eines Freundes. Es erscheint als antippbare Profilkarte –
/// derselbe Weg wie „Profil teilen“ auf einer Profilseite.
struct ChatProfileShareSheet: View {
    let profiles: [SocialProfile]
    let ownPublicID: UUID?
    let onShare: (SocialProfile) -> Void

    @State private var filter = ""
    @Environment(\.dismiss) private var dismiss

    private var shown: [SocialProfile] {
        let text = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return profiles }
        return profiles.filter { profile in
            profile.shownName.localizedCaseInsensitiveContains(text) || profile.username.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceSearchField(ChatUIText.shareProfileSearch, text: $filter)
                    Text(ChatUIText.shareProfileHint)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if shown.isEmpty {
                        Text(ChatUIText.shareProfileEmpty)
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    ForEach(shown) { profile in
                        Button {
                            onShare(profile)
                            dismiss()
                        } label: {
                            row(profile)
                        }
                        .buttonStyle(.pacePressable)
                    }
                }
                .padding(PaceSpacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .paceScreenBackground()
            .navigationTitle(ChatUIText.shareProfileTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SocialText.cancel) { dismiss() }
                }
            }
        }
    }

    private func row(_ profile: SocialProfile) -> some View {
        HStack(spacing: PaceSpacing.s) {
            PaceAvatar(name: profile.shownName, seed: profile.publicID.uuidString, size: 40, image: profile.avatar)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.publicID == ownPublicID ? ChatUIText.myProfile : profile.shownName)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                Text(verbatim: "@\(profile.username)")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: PaceSpacing.xs)
            Image(systemName: "paperplane")
                .foregroundStyle(PaceColor.accent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, PaceSpacing.s)
        .frame(minHeight: 56)
        .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
