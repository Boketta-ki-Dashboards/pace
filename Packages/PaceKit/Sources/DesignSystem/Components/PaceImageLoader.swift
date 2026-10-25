import ImageIO
import PaceCore
import SwiftUI
import UIKit

/// Lädt Bilder aus den privaten Storage-Buckets (Profil-, Gruppen- und Chatbilder) und hält sie im Speicher vor.
/// Animierte GIFs werden als animiertes `UIImage` geliefert.
///
/// Speicher und Leistung:
/// - Dekodiert wird in der Größe, in der das Bild erscheint (``Size``): Profilbilder klein, Chatbilder in der Blase
///   mittel, im Vollbild groß. Jede Größe hat ihren eigenen Eintrag.
/// - Die heruntergeladenen (komprimierten) Daten liegen getrennt im Speicher; eine andere Größe braucht deshalb keinen
///   zweiten Download. Gleichzeitige Anfragen derselben Datei teilen sich einen Download.
/// - GIFs haben ein Byte-Budget je Bild: lange GIFs werden gleichmäßig ausgedünnt (die Laufzeit bleibt).
/// - Beide Speicher sind nach Bytes begrenzt. Dekodiert wird nie auf dem Main Thread.
public final class PaceImageLoader: @unchecked Sendable {
    /// Größe, in der ein Bild gebraucht wird.
    public enum Size: Hashable, Sendable {
        /// Profil- und Gruppenbilder: längste Kante in Pixeln.
        case pixels(Int)
        /// Bild bzw. GIF in einer Chatblase.
        case bubble
        /// Vollbild mit Zoom.
        case full

        /// Profilbild für `points` Punkte Durchmesser (3-fache Auflösung, in Stufen, damit Einträge geteilt werden).
        public static func avatar(points: CGFloat) -> Size {
            let pixels = Int((points * 3).rounded(.up))
            return .pixels([96, 192, 384].first { $0 >= pixels } ?? 512)
        }

        var photoPixels: Int {
            switch self {
            case .pixels(let pixels): pixels
            case .bubble: 1_200
            case .full: 2_048
            }
        }

        var animationPixels: Int {
            switch self {
            case .pixels(let pixels): min(pixels, 480)
            case .bubble: 480
            case .full: 720
            }
        }

        /// Höchstens so viele Bytes dekodierte Einzelbilder je GIF.
        var animationByteBudget: Int {
            switch self {
            case .pixels, .bubble: 16 * 1_024 * 1_024
            case .full: 40 * 1_024 * 1_024
            }
        }

        var key: String {
            switch self {
            case .pixels(let pixels): "p\(pixels)"
            case .bubble: "bubble"
            case .full: "full"
            }
        }
    }

    /// Höchstens so viele Einzelbilder je GIF (längere werden gleichmäßig ausgedünnt).
    static let maximumAnimationFrames = 90
    /// Obergrenze der dekodierten Bilder in Bytes.
    static let imageByteLimit = 96 * 1_024 * 1_024
    /// Obergrenze der heruntergeladenen (komprimierten) Daten in Bytes.
    static let dataByteLimit = 32 * 1_024 * 1_024

    private let repository: any MediaRepository
    private let images = NSCache<NSString, UIImage>()
    private let downloaded = NSCache<NSString, NSData>()
    private let lock = NSLock()
    private var downloads: [String: Task<Data?, Never>] = [:]

    public init(repository: any MediaRepository) {
        self.repository = repository
        images.totalCostLimit = Self.imageByteLimit
        downloaded.totalCostLimit = Self.dataByteLimit
    }

    /// Bild aus dem Speicher, ohne zu laden.
    public func cachedImage(for reference: MediaReference, size: Size = .bubble) -> UIImage? {
        images.object(forKey: Self.imageKey(reference, size))
    }

    /// Lädt das Bild in der gewünschten Größe (oder liefert es aus dem Speicher); `nil` bei Fehlern. Läuft nicht auf dem
    /// Main Thread.
    public func image(for reference: MediaReference, size: Size = .bubble) async -> UIImage? {
        if let cached = cachedImage(for: reference, size: size) { return cached }
        guard let data = await data(for: reference), let image = Self.decode(data, size: size) else { return nil }
        images.setObject(image, forKey: Self.imageKey(reference, size), cost: Self.byteCost(of: image))
        return image
    }

    /// Legt die Daten eines gerade hochgeladenen Bilds in den Speicher (keine zweite Übertragung). Dekodiert wird erst
    /// bei Bedarf – nicht hier auf dem Main Thread.
    public func store(_ data: Data, for reference: MediaReference) {
        downloaded.setObject(data as NSData, forKey: Self.dataKey(reference), cost: data.count)
    }

    /// Komprimierte Daten: aus dem Speicher oder per (geteiltem) Download.
    private func data(for reference: MediaReference) async -> Data? {
        let key = Self.dataKey(reference)
        if let cached = downloaded.object(forKey: key) { return cached as Data }
        let repository = repository
        let task = lock.withLock {
            if let running = downloads[key as String] { return running }
            let task = Task<Data?, Never> { try? await repository.data(for: reference) }
            downloads[key as String] = task
            return task
        }
        let data = await task.value
        lock.withLock { downloads[key as String] = nil }
        if let data {
            downloaded.setObject(data as NSData, forKey: key, cost: data.count)
        }
        return data
    }

    private static func dataKey(_ reference: MediaReference) -> NSString {
        "\(reference.bucket.rawValue)/\(reference.path)" as NSString
    }

    private static func imageKey(_ reference: MediaReference, _ size: Size) -> NSString {
        "\(reference.bucket.rawValue)/\(reference.path)@\(size.key)" as NSString
    }

    /// Dekodiert Fotos und – bei mehreren Bildern – animierte GIFs, jeweils verkleinert.
    static func decode(_ data: Data, size: Size = .bubble) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            return thumbnail(source, index: 0, maximumPixels: size.photoPixels).map { UIImage(cgImage: $0) } ?? UIImage(data: data)
        }
        // Wie viele Einzelbilder ins Budget passen (aus der Größe des ersten Bilds nach dem Verkleinern).
        let frameBytes = scaledFrameBytes(source, maximumPixels: size.animationPixels)
        let affordable = max(1, size.animationByteBudget / max(frameBytes, 1))
        let maximumFrames = min(maximumAnimationFrames, affordable)
        // Lange GIFs gleichmäßig ausdünnen; die Dauer übersprungener Bilder zählt zum vorigen, die Laufzeit bleibt.
        let step = max(1, Int((Double(count) / Double(maximumFrames)).rounded(.up)))
        var frames: [UIImage] = []
        var duration: Double = 0
        for index in stride(from: 0, to: count, by: step) {
            for skipped in index..<min(index + step, count) {
                duration += frameDuration(source, skipped)
            }
            guard let frame = thumbnail(source, index: index, maximumPixels: size.animationPixels) else { continue }
            frames.append(UIImage(cgImage: frame))
        }
        guard !frames.isEmpty else { return UIImage(data: data) }
        return UIImage.animatedImage(with: frames, duration: max(duration, 0.1))
    }

    /// Bytes eines verkleinerten Einzelbilds (aus den Bildeigenschaften, ohne zu dekodieren).
    private static func scaledFrameBytes(_ source: CGImageSource, maximumPixels: Int) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return maximumPixels * maximumPixels * 4 }
        let scale = min(1, Double(maximumPixels) / Double(max(width, height)))
        return Int(Double(width) * scale * Double(height) * scale) * 4
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
