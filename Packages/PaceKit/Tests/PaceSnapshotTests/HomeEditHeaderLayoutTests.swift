import DesignSystem
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
import SwiftUI
import Testing
import UIKit

/// Home-Anpassen-Kopf (Auftrag 7, Teil A 1): „Fertig“ und „+ Widget hinzufügen“ berühren oder überlagern sich nie –
/// auf schmalen (iPhone SE, auch mit Display-Zoom), normalen und großen iPhones, in Deutsch, Englisch und Russisch,
/// mit normaler, großer und Bedienungshilfen-Schrift. Beide Pillen stehen rechtsbündig, „Fertig“ oben, keine ragt über den Rand.
///
/// Gemessen wird im gerenderten Bild: Die beiden mintfarbenen Flächen (`PaceColor.selectionFill`) werden als
/// zusammenhängende Bereiche gesucht.
@MainActor
struct HomeEditHeaderLayoutTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let device: String
        let width: CGFloat
        let language: AppLanguage
        let textSize: DynamicTypeSize

        var testDescription: String {
            "\(device) \(language.rawValue) \(textSize)"
        }

        /// SE mit Display-Zoom (320 pt), SE (375), iPhone 16 (393), Pro Max (430) × DE/EN/RU × Standard, größte normale
        /// Schrift (xxxLarge) und Bedienungshilfen-Schrift (AX3).
        static let all: [Case] = {
            let devices: [(String, CGFloat)] = [("SE Zoom", 320), ("SE", 375), ("16", 393), ("Pro Max", 430)]
            let sizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility3]
            return devices.flatMap { device in
                AppLanguage.allCases.flatMap { language in
                    sizes.map { Case(device: device.0, width: device.1, language: language, textSize: $0) }
                }
            }
        }()
    }

    private static let scale: CGFloat = 2

    @Test(arguments: Case.all)
    func pillsNeverTouch(_ testCase: Case) async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        dashboard.beginEditing()
        let image = try PaceLocalization.$languageOverride.withValue(testCase.language) {
            let view = HomeHeaderView(viewModel: dashboard, onAddWidget: {})
                .padding(.horizontal, PaceSpacing.m)
                .frame(width: testCase.width)
                .background(PaceColor.background)
                .environment(\.colorScheme, .light)
                .environment(\.locale, testCase.language.locale)
                .environment(\.dynamicTypeSize, testCase.textSize)
            let renderer = ImageRenderer(content: view)
            renderer.scale = Self.scale
            renderer.proposedSize = ProposedViewSize(width: testCase.width, height: nil)
            return try #require(renderer.cgImage)
        }
        let pills = Self.pills(in: image)
        try #require(pills.count == 2, "\(testCase): \(pills.count) mintfarbene Pillen gefunden: \(pills)")
        let done = pills.min { $0.minY < $1.minY }!
        let add = pills.max { $0.minY < $1.minY }!
        // Mindestens 4 pt Abstand in jede Richtung, „Fertig“ oben.
        let gap: CGFloat = 4 * Self.scale
        #expect(!done.insetBy(dx: -gap, dy: -gap).intersects(add), "\(testCase): Pillen zu nah \(done) \(add)")
        #expect(done.maxY + gap <= add.minY, "\(testCase): „Fertig“ nicht über „+ Widget hinzufügen“ \(done) \(add)")
        // Rechtsbündig, nichts über den Rand.
        #expect(abs(done.maxX - add.maxX) <= 3 * Self.scale, "\(testCase): nicht rechtsbündig \(done) \(add)")
        let trailing = (testCase.width - PaceSpacing.m) * Self.scale
        #expect(done.maxX <= trailing + 1 && add.maxX <= trailing + 1, "\(testCase): ragt über den Rand \(done) \(add)")
        #expect(add.minX >= PaceSpacing.m * Self.scale - 1, "\(testCase): ragt links über den Rand \(add)")
        // Gut tippbar: sichtbare Höhe mindestens 36 pt.
        #expect(done.height >= 35 * Self.scale && add.height >= 35 * Self.scale, "\(testCase): Pillen zu niedrig \(done) \(add)")
        dashboard.endEditing()
    }

    /// Begrenzungsrechtecke (Pixel) der zusammenhängenden Flächen in der Farbe `selectionFill` (hell), mindestens
    /// 30 × 40 pt groß – kleinere Treffer (z. B. Kantenglättung) zählen nicht.
    static func pills(in image: CGImage) -> [CGRect] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // PaceColor.selectionFill (hell) = #D3F9EA.
        let target: (Int, Int, Int) = (0xD3, 0xF9, 0xEA)
        func matches(_ index: Int) -> Bool {
            abs(Int(pixels[index]) - target.0) <= 6 && abs(Int(pixels[index + 1]) - target.1) <= 6
                && abs(Int(pixels[index + 2]) - target.2) <= 6
        }
        var visited = [Bool](repeating: false, count: width * height)
        var rects: [CGRect] = []
        for start in 0..<(width * height) where !visited[start] && matches(start * 4) {
            var stack = [start]
            visited[start] = true
            var minX = width, maxX = 0, minY = height, maxY = 0
            while let current = stack.popLast() {
                let x = current % width
                let y = current / width
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                    let next = ny * width + nx
                    if !visited[next] && matches(next * 4) {
                        visited[next] = true
                        stack.append(next)
                    }
                }
            }
            let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            if rect.height >= 30 * scale && rect.width >= 40 * scale {
                rects.append(rect)
            }
        }
        return rects
    }
}
