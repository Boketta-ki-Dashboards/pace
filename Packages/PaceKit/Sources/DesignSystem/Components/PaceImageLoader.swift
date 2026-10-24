import ImageIO
import PaceCore
import SwiftUI
import UIKit

/// Lädt Bilder aus den privaten Storage-Buckets (Profil-, Gruppen- und Chatbilder) und hält sie im Speicher vor.
/// Animierte GIFs werden als animiertes `UIImage` geliefert.
///
/// Speicher: Bilder werden beim Dekodieren verkleinert (Fotos höchstens ``maximumPhotoPixels``, GIF-Bilder höchstens
/// ``maximumAnimationPixels`` Pixel Kantenlänge, höchstens ``maximumAnimationFrames`` Einzelbilder) und der Speicher
/// ist nach dekodierter Größe begrenzt (``cacheByteLimit``) – ein langer Chat mit vielen Fotos und GIFs lässt den
/// Arbeitsspeicher so nicht unbegrenzt wachsen.
public final class PaceImageLoader: @unchecked Sendable {
    /// Längste Kante eines Fotos nach dem Dekodieren (reicht für Vollbild auf allen iPhones).
    static let maximumPhotoPixels = 1_600
    /// Längste Kante eines GIF-Einzelbilds.
    static let maximumAnimationPixels = 480
    /// Höchstens so viele Einzelbilder je GIF (längere werden gleichmäßig ausgedünnt, die Laufzeit bleibt).
    static let maximumAnimationFrames = 90
    /// Obergrenze des Bildspeichers in Bytes (dekodiert).
    static let cacheByteLimit = 96 * 1_024 * 1_024

    private let repository: any MediaRepository
    private let cache = NSCache<NSString, UIImage>()

    public init(repository: any MediaRepository) {
        self.repository = repository
        cache.countLimit = 200
        cache.totalCostLimit = Self.cacheByteLimit
    }

    /// Bild aus dem Speicher, ohne zu laden.
    public func cachedImage(for reference: MediaReference) -> UIImage? {
        cache.object(forKey: Self.key(reference))
    }

    /// Lädt das Bild (oder liefert es aus dem Speicher); `nil` bei Fehlern.
    public func image(for reference: MediaReference) async -> UIImage? {
        if let cached = cachedImage(for: reference) { return cached }
        guard let data = try? await repository.data(for: reference), let image = Self.decode(data) else { return nil }
        cache.setObject(image, forKey: Self.key(reference), cost: Self.byteCost(of: image))
        return image
    }

    /// Legt ein gerade hochgeladenes Bild direkt in den Speicher (keine zweite Übertragung).
    public func store(_ data: Data, for reference: MediaReference) {
        guard let image = Self.decode(data) else { return }
        cache.setObject(image, forKey: Self.key(reference), cost: Self.byteCost(of: image))
    }

    private static func key(_ reference: MediaReference) -> NSString {
        "\(reference.bucket.rawValue)/\(reference.path)" as NSString
    }

    /// Dekodiert Fotos und – bei mehreren Bildern – animierte GIFs, jeweils verkleinert.
    static func decode(_ data: Data) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            return thumbnail(source, index: 0, maximumPixels: maximumPhotoPixels).map { UIImage(cgImage: $0) } ?? UIImage(data: data)
        }
        // Lange GIFs gleichmäßig ausdünnen; die Dauer übersprungener Bilder zählt zum vorigen, die Laufzeit bleibt.
        let step = max(1, Int((Double(count) / Double(maximumAnimationFrames)).rounded(.up)))
        var frames: [UIImage] = []
        var duration: Double = 0
        for index in stride(from: 0, to: count, by: step) {
            guard let frame = thumbnail(source, index: index, maximumPixels: maximumAnimationPixels) else { continue }
            frames.append(UIImage(cgImage: frame))
            for skipped in index..<min(index + step, count) {
                duration += frameDuration(source, skipped)
            }
        }
        guard !frames.isEmpty else { return UIImage(data: data) }
        return UIImage.animatedImage(with: frames, duration: max(duration, 0.1))
    }

    /// Verkleinertes, richtig gedrehtes Einzelbild (nie größer als das Original).
    private static func thumbnail(_ source: CGImageSource, index: Int, maximumPixels: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    /// Dekodierte Größe in Bytes (alle Einzelbilder), als Kosten im Bildspeicher.
    static func byteCost(of image: UIImage) -> Int {
        let frames = image.images ?? [image]
        return frames.reduce(0) { total, frame in
            let size = frame.cgImage.map { CGSize(width: $0.width, height: $0.height) } ?? frame.size
            return total + Int(size.width * size.height) * 4
        }
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
