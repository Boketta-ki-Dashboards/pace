import ImageIO
import PaceCore
import SwiftUI
import UIKit

/// Lädt Bilder aus den privaten Storage-Buckets (Profil-, Gruppen- und Chatbilder) und hält sie im Speicher vor.
/// Animierte GIFs werden als animiertes `UIImage` geliefert.
public final class PaceImageLoader: @unchecked Sendable {
    private let repository: any MediaRepository
    private let cache = NSCache<NSString, UIImage>()

    public init(repository: any MediaRepository) {
        self.repository = repository
        cache.countLimit = 200
    }

    /// Bild aus dem Speicher, ohne zu laden.
    public func cachedImage(for reference: MediaReference) -> UIImage? {
        cache.object(forKey: Self.key(reference))
    }

    /// Lädt das Bild (oder liefert es aus dem Speicher); `nil` bei Fehlern.
    public func image(for reference: MediaReference) async -> UIImage? {
        if let cached = cachedImage(for: reference) { return cached }
        guard let data = try? await repository.data(for: reference), let image = Self.decode(data) else { return nil }
        cache.setObject(image, forKey: Self.key(reference))
        return image
    }

    /// Legt ein gerade hochgeladenes Bild direkt in den Speicher (keine zweite Übertragung).
    public func store(_ data: Data, for reference: MediaReference) {
        guard let image = Self.decode(data) else { return }
        cache.setObject(image, forKey: Self.key(reference))
    }

    private static func key(_ reference: MediaReference) -> NSString {
        "\(reference.bucket.rawValue)/\(reference.path)" as NSString
    }

    /// Dekodiert Fotos und – bei mehreren Bildern – animierte GIFs.
    static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var duration: Double = 0
        for index in 0..<min(count, 300) {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: frame))
            duration += frameDuration(source, index)
        }
        guard !frames.isEmpty else { return UIImage(data: data) }
        return UIImage.animatedImage(with: frames, duration: max(duration, 0.1))
    }

    private static func frameDuration(_ source: CGImageSource, _ index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.1 }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let value = unclamped ?? clamped ?? 0.1
        return value < 0.02 ? 0.1 : value
    }
}

extension EnvironmentValues {
    /// Bildlader für Profil-, Gruppen- und Chatbilder; ohne Lader zeigen Avatare Initialen.
    @Entry public var paceImageLoader: PaceImageLoader?
}

/// Bild aus Storage (Gruppen- oder Chatbild) mit Platzhalter; GIFs laufen animiert.
public struct PaceRemoteImage: View {
    private let reference: MediaReference?
    private let contentMode: ContentMode

    @Environment(\.paceImageLoader) private var loader
    @State private var image: UIImage?
    @State private var failed = false

    public init(_ reference: MediaReference?, contentMode: ContentMode = .fill) {
        self.reference = reference
        self.contentMode = contentMode
    }

    public var body: some View {
        ZStack {
            if let image {
                if image.images != nil {
                    AnimatedImageView(image: image, contentMode: contentMode)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            } else {
                PaceColor.fieldBackground
                if failed {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(PaceColor.textSecondary)
                } else if reference != nil {
                    ProgressView()
                }
            }
        }
        .clipped()
        .task(id: reference) {
            guard let reference, let loader else { return }
            if let cached = loader.cachedImage(for: reference) {
                image = cached
                return
            }
            let loaded = await loader.image(for: reference)
            image = loaded
            failed = loaded == nil
        }
    }
}

/// `UIImageView` für animierte Bilder (SwiftUI-`Image` zeigt nur das erste Bild).
private struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage
    let contentMode: ContentMode

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.clipsToBounds = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
        view.image = image
        view.startAnimating()
    }
}
