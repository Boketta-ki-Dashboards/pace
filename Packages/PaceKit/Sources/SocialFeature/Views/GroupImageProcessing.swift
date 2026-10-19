import Foundation
import PaceCore
import UIKit

/// Bereitet ein ausgewähltes Foto als Gruppenbild vor: verkleinert auf höchstens 1.024 Pixel Kantenlänge und als JPEG
/// komprimiert, bis es unter die Grenze des Servers (5 MB) passt.
enum GroupImageProcessing {
    static let maximumDimension: CGFloat = 1_024

    /// `nil`, wenn die Daten kein lesbares Bild sind oder es sich nicht klein genug komprimieren lässt.
    static func upload(from data: Data, maximumBytes: Int = SocialViewModel.groupImageMaximumBytes) -> SocialViewModel.GroupImageUpload? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.85, 0.7, 0.55, 0.4] {
            if let jpeg = resized.jpegData(compressionQuality: quality), jpeg.count <= maximumBytes {
                return SocialViewModel.GroupImageUpload(data: jpeg, contentType: "image/jpeg")
            }
        }
        return nil
    }
}
