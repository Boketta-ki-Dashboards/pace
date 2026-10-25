@testable import DesignSystem
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

/// Bilder und GIFs werden verkleinert dekodiert, damit lange Chats den Arbeitsspeicher nicht sprengen (Auftrag 4,
/// Stabilität).
struct ImageDecodingTests {
    private func gif(frames: Int, side: Int, delay: Double = 0.05) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString, frames, nil))
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
        for index in 0..<frames {
            let image = renderer.image { context in
                UIColor(hue: CGFloat(index) / CGFloat(frames), saturation: 1, brightness: 1, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            }
            CGImageDestinationAddImage(destination, try #require(image.cgImage), properties)
        }
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func longLargeGifsAreThinnedAndDownsampled() throws {
        // 100 Bilder à 520 px: mehr als erlaubt und größer als die Grenze (klein genug, damit das Erzeugen schnell geht).
        let image = try #require(PaceImageLoader.decode(try gif(frames: 100, side: 520), size: .bubble))
        let frames = try #require(image.images)
        #expect(frames.count <= PaceImageLoader.maximumAnimationFrames)
        #expect(frames.allSatisfy { max($0.size.width, $0.size.height) <= CGFloat(PaceImageLoader.Size.bubble.animationPixels) })
        // Byte-Budget je GIF: 480 × 480 × 4 Bytes je Bild passen 18-mal in 16 MB → jedes 6. Bild (17 Bilder).
        #expect(PaceImageLoader.byteCost(of: image) <= PaceImageLoader.Size.bubble.animationByteBudget)
        #expect(frames.count == 17)
        // Laufzeit bleibt (100 × 0,05 s = 5 s).
        #expect(abs(image.duration - 5) < 0.3)
    }

    @Test func smallGifsKeepAllFramesAndSize() throws {
        let image = try #require(PaceImageLoader.decode(try gif(frames: 12, side: 120), size: .bubble))
        #expect(image.images?.count == 12)
        #expect(image.images?.first?.size == CGSize(width: 120, height: 120))
    }

    @Test func photosAreLimitedToTheMaximumEdge() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4_000, height: 3_000), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        let data = renderer.jpegData(withCompressionQuality: 0.5) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4_000, height: 3_000))
        }
        let bubble = try #require(PaceImageLoader.decode(data, size: .bubble))
        #expect(bubble.images == nil)
        #expect(max(bubble.size.width, bubble.size.height) == CGFloat(PaceImageLoader.Size.bubble.photoPixels))
        #expect(abs(bubble.size.width / bubble.size.height - 4.0 / 3.0) < 0.01)
        // Vollbild schärfer, Profilbild klein – jeweils eigene Größe.
        let full = try #require(PaceImageLoader.decode(data, size: .full))
        #expect(max(full.size.width, full.size.height) == CGFloat(PaceImageLoader.Size.full.photoPixels))
        let avatar = try #require(PaceImageLoader.decode(data, size: .avatar(points: 44)))
        #expect(max(avatar.size.width, avatar.size.height) == 192)
    }
}
