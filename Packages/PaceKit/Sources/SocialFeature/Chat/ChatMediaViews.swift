import DesignSystem
import PaceCore
import SwiftUI
import UIKit

/// Foto bzw. GIF im Verlauf: abgerundete Vorschau, GIFs mit „GIF“-Kennzeichnung und animiert – bei „Bewegung
/// reduzieren“ erst nach Antippen. Antippen öffnet das Bild im Vollbild.
struct ChatMediaBubble: View {
    let reference: MediaReference?
    /// Daten auf dem Gerät (gerade ausgewählt bzw. hochgeladen) – keine zweite Übertragung nötig.
    let localData: Data?
    let isGIF: Bool
    let accessibilityText: String
    let isUploading: Bool
    let onOpen: ((MediaReference) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playsGIF = false

    init(
        reference: MediaReference?,
        localData: Data?,
        isGIF: Bool,
        accessibilityText: String,
        isUploading: Bool = false,
        onOpen: ((MediaReference) -> Void)? = nil
    ) {
        self.reference = reference
        self.localData = localData
        self.isGIF = isGIF
        self.accessibilityText = accessibilityText
        self.isUploading = isUploading
        self.onOpen = onOpen
    }

    private var size: CGSize {
        isGIF ? CGSize(width: 156, height: 104) : CGSize(width: 212, height: 120)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: tap) {
            ChatMediaImage(reference: reference, localData: localData, animates: isGIF && (!reduceMotion || playsGIF))
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                .overlay(alignment: .bottomLeading) {
                    if isGIF {
                        gifBadge
                    }
                }
                .overlay {
                    if isUploading {
                        ProgressView()
                            .padding(PaceSpacing.s)
                            .background(PaceColor.surface.opacity(0.85), in: Circle())
                    } else if isGIF && reduceMotion && !playsGIF {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PaceColor.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(PaceColor.surface.opacity(0.85), in: Circle())
                    }
                }
                .overlay(shape.strokeBorder(PaceColor.border, lineWidth: 1))
        }
        .buttonStyle(.pacePressable)
        .disabled(reference == nil)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isGIF && reduceMotion && !playsGIF ? ChatUIText.tapToPlay : "")
    }

    private var gifBadge: some View {
        Text(ChatUIText.gifBadge)
            .font(.system(.caption, weight: .bold))
            .foregroundStyle(PaceColor.surface)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(PaceColor.textPrimary.opacity(0.75), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(PaceSpacing.xs)
            .accessibilityHidden(true)
    }

    private func tap() {
        if isGIF && reduceMotion && !playsGIF {
            playsGIF = true
            return
        }
        if let reference {
            onOpen?(reference)
        }
    }
}

/// Lädt ein Chatbild über den gemeinsamen Bildlader (Cache) bzw. zeigt Daten vom Gerät.
struct ChatMediaImage: View {
    let reference: MediaReference?
    let localData: Data?
    let animates: Bool
    let contentMode: ContentMode

    @Environment(\.paceImageLoader) private var loader
    @State private var image: UIImage?
    @State private var failed = false

    init(reference: MediaReference?, localData: Data?, animates: Bool, contentMode: ContentMode = .fill) {
        self.reference = reference
        self.localData = localData
        self.animates = animates
        self.contentMode = contentMode
    }

    var body: some View {
        let shown = image ?? reference.flatMap { loader?.cachedImage(for: $0) }
        ZStack {
            if let shown {
                if animates, shown.images != nil {
                    ChatAnimatedImage(image: shown, contentMode: contentMode)
                } else {
                    Image(uiImage: shown.images?.first ?? shown)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            } else {
                PaceColor.fieldBackground
                if failed {
                    VStack(spacing: PaceSpacing.xxs) {
                        Image(systemName: "photo")
                            .font(.title3)
                        Text(ChatUIText.imageUnavailable)
                            .font(PaceFont.micro)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(PaceColor.textSecondary)
                    .padding(PaceSpacing.xs)
                } else {
                    ProgressView()
                }
            }
        }
        .clipped()
        .task(id: reference) {
            await load()
        }
    }

    private func load() async {
        if let reference, let loader {
            if let localData, loader.cachedImage(for: reference) == nil {
                loader.store(localData, for: reference)
            }
            if let cached = loader.cachedImage(for: reference) {
                image = cached
                return
            }
            let loaded = await loader.image(for: reference)
            image = loaded
            failed = loaded == nil
        } else if let localData {
            image = UIImage(data: localData)
            failed = image == nil
        } else {
            failed = true
        }
    }
}

/// `UIImageView` für animierte GIFs (SwiftUI-`Image` zeigt nur das erste Bild).
struct ChatAnimatedImage: UIViewRepresentable {
    let image: UIImage
    let contentMode: ContentMode

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.clipsToBounds = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
        if view.image !== image {
            view.image = image
        }
        if !view.isAnimating {
            view.startAnimating()
        }
    }
}

/// Bild im Vollbild: Zoomen mit zwei Fingern oder Doppeltippen, Verschieben im Zoom, Schließen.
struct ChatImageViewer: View {
    let item: ChatViewerItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    init(item: ChatViewerItem) {
        self.item = item
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PaceColor.background
                .ignoresSafeArea()
            ChatMediaImage(reference: item.reference, localData: nil, animates: item.isGIF && !reduceMotion, contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(zoom)
                .simultaneousGesture(pan)
                .onTapGesture(count: 2) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        if scale > 1 {
                            reset()
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(.isImage)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(PaceNeutralIconButtonStyle(size: 44))
            .padding(PaceSpacing.m)
            .accessibilityLabel(ChatUIText.close)
        }
        .accessibilityAction(.escape) {
            dismiss()
        }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        reset()
                    }
                }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

/// Bereitet ein Bild aus der Mediathek zum Senden vor: GIFs unverändert (`image/gif`), Fotos verkleinert und als JPEG
/// komprimiert, bis sie unter die Grenze des Servers passen.
///
/// Ob es ein GIF ist, entscheidet die Dateisignatur der geladenen Daten: Die Mediathek liefert Einträge vom Typ
/// `com.compuserve.gif` dank `preferredItemEncoding: .current` unverändert; ein umgewandeltes Bild wäre kein GIF mehr
/// und wird dann wie ein Foto behandelt.
enum ChatMediaProcessing {
    struct Prepared {
        let data: Data
        let contentType: String
    }

    /// `nil`, wenn die Daten kein lesbares Bild sind oder sich nicht klein genug komprimieren lassen.
    static func prepare(_ data: Data, maximumBytes: Int = ChatMediaSupport.maximumBytes) -> Prepared? {
        if ChatMediaSupport.isGIF(data) {
            // Unverändert hochladen, damit die Animation erhalten bleibt; die Größe prüft das ViewModel.
            return Prepared(data: data, contentType: ChatMediaSupport.gifContentType)
        }
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let target = ChatMediaSupport.scaledSize(width: Double(image.size.width), height: Double(image.size.height))
        let size = CGSize(width: target.width, height: target.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in ChatMediaSupport.jpegQualities {
            if let jpeg = resized.jpegData(compressionQuality: CGFloat(quality)), jpeg.count <= maximumBytes {
                return Prepared(data: jpeg, contentType: ChatMediaSupport.jpegContentType)
            }
        }
        return nil
    }
}
