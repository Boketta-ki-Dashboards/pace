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
        let image = try #require(PaceImageLoader.decode(try gif(frames: 100, side: 520)))
        let frames = try #require(image.images)
        #expect(frames.count <= PaceImageLoader.maximumAnimationFrames)
        #expect(frames.allSatisfy { max($0.size.width, $0.size.height) <= CGFloat(PaceImageLoader.maximumAnimationPixels) })
        #expect(frames.count == 50)
        // Laufzeit bleibt (100 × 0,05 s = 5 s).
        #expect(abs(image.duration - 5) < 0.3)
        #expect(PaceImageLoader.byteCost(of: image) <= PaceImageLoader.maximumAnimationFrames * 480 * 480 * 4)
    }

    @Test func smallGifsKeepAllFramesAndSize() throws {
        let image = try #require(PaceImageLoader.decode(try gif(frames: 12, side: 120)))
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
        let image = try #require(PaceImageLoader.decode(data))
        #expect(image.images == nil)
        #expect(max(image.size.width, image.size.height) <= CGFloat(PaceImageLoader.maximumPhotoPixels))
        #expect(abs(image.size.width / image.size.height - 4.0 / 3.0) < 0.01)
    }
}
