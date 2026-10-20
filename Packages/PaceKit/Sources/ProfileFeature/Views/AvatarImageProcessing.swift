import Foundation
import PaceCore
import UIKit

/// Bereitet ein ausgewähltes Foto als Profilbild vor: mittig quadratisch zugeschnitten, auf höchstens 1.024 × 1.024
/// Pixel verkleinert und als JPEG komprimiert, bis es unter die Grenze des Servers (5 MB) passt.
enum AvatarImageProcessing {
    static let maximumDimension: CGFloat = 1_024

    /// `nil`, wenn die Daten kein lesbares Bild sind oder es sich nicht klein genug komprimieren lässt.
    static func squareJPEG(from data: Data, maximumBytes: Int = MediaRules.maximumBytes(for: .avatar)) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let side = min(image.size.width, image.size.height)
        let targetSide = min(side, maximumDimension).rounded()
        let size = CGSize(width: targetSide, height: targetSide)
        let scale = targetSide / side
        // Mittiger Ausschnitt: das Bild so zeichnen, dass die kürzere Seite das Quadrat füllt.
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (targetSide - drawSize.width) / 2, y: (targetSide - drawSize.height) / 2)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let squared = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        for quality in [0.85, 0.7, 0.55, 0.4] {
            if let jpeg = squared.jpegData(compressionQuality: quality), jpeg.count <= maximumBytes {
                return jpeg
            }
        }
        return nil
    }
}
