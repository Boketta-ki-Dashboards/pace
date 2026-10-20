import Foundation
import PaceCore

/// Regeln für Bilder und GIFs aus der Mediathek (ohne UIKit, damit sie auf Linux getestet werden).
enum ChatMediaSupport {
    static let gifContentType = "image/gif"
    static let jpegContentType = "image/jpeg"
    /// Längste Kante eines Fotos nach dem Verkleinern (scharf auf allen iPhones, deutlich kleiner als das Original).
    static let maximumPhotoDimension: Double = 2_048
    /// JPEG-Qualitäten, die nacheinander probiert werden, bis das Foto unter die Grenze passt.
    static let jpegQualities: [Double] = [0.85, 0.75, 0.6, 0.45]

    /// Die Daten sind ein GIF (Signatur `GIF87a` bzw. `GIF89a`) – unabhängig davon, was die Mediathek angibt.
    static func isGIF(_ data: Data) -> Bool {
        let signature = Array(data.prefix(6))
        return signature == Array("GIF87a".utf8) || signature == Array("GIF89a".utf8)
    }

    /// Größte erlaubte Datei für Chat-Anhänge (wie der Bucket `chat-media` auf dem Server).
    static var maximumBytes: Int {
        MediaRules.maximumBytes(for: .chat(conversationID: UUID()))
    }

    /// Zielgröße eines Fotos: längste Kante höchstens ``maximumPhotoDimension``, Seitenverhältnis bleibt.
    static func scaledSize(width: Double, height: Double) -> (width: Double, height: Double) {
        guard width > 0, height > 0 else { return (0, 0) }
        let scale = min(1, maximumPhotoDimension / max(width, height))
        return ((width * scale).rounded(), (height * scale).rounded())
    }
}
