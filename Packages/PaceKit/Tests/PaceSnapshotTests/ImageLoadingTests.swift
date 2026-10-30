import DesignSystem
import Foundation
import Observation
import PaceCore
import PaceTestSupport
import SwiftUI
import Testing
import UIKit

/// Profil- und Gruppenbilder (Auftrag 6, Teil A 4): richtige Person, kein altes Bild nach einem Wechsel, verspätete
/// Downloads ohne Wirkung, ein Download je Datei, Speicher als Rückfall ohne Netz.
@MainActor
@Suite(.serialized)
struct ImageLoadingTests {
    private let mia = MediaReference(bucket: .avatars, path: "mia/a.png")
    private let leon = MediaReference(bucket: .avatars, path: "leon/b.png")
    private let group = MediaReference(bucket: .groupImages, path: "group/c.png")

    private static func png(_ color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }

    private func repository() -> MediaRepositoryStub {
        MediaRepositoryStub { [mia, leon, group] state in
            state.files[mia] = Self.png(.red)
            state.files[leon] = Self.png(.blue)
            state.files[group] = Self.png(.green)
        }
    }

    // MARK: Lader

    @Test func oneDownloadForAllSizesAndViews() async throws {
        let media = repository()
        let loader = PaceImageLoader(repository: media)
        async let small = loader.image(for: mia, size: .avatar(points: 28))
        async let large = loader.image(for: mia, size: .avatar(points: 96))
        async let bubble = loader.image(for: mia, size: .bubble)
        let images = await [small, large, bubble]
        #expect(images.allSatisfy { $0 != nil })
        #expect(media.state.withLock { $0.downloads[mia] } == 1)
        // Erneut (andere Ansicht, gleiches Bild): aus dem Speicher.
        _ = await loader.image(for: mia, size: .avatar(points: 28))
        #expect(media.state.withLock { $0.downloads[mia] } == 1)
    }

    @Test func cachedImagesStayAvailableOfflineAndFailuresCanBeRetried() async throws {
        let media = repository()
        let loader = PaceImageLoader(repository: media)
        #expect(await loader.image(for: mia, size: .avatar(points: 40)) != nil)
        // Kein Netz mehr: Das schon geladene Bild kommt aus dem Speicher – auch in einer anderen Größe.
        media.state.withLock { $0.error = .network }
        #expect(await loader.image(for: mia, size: .avatar(points: 40)) != nil)
        #expect(await loader.image(for: mia, size: .avatar(points: 120)) != nil)
        // Ein neues Bild schlägt fehl (nil, kein Absturz, kein Hängen) …
        #expect(await loader.image(for: leon, size: .avatar(points: 40)) == nil)
        // … und klappt beim nächsten Versuch, sobald das Netz zurück ist (kein dauerhaft gemerkter Fehler).
        media.state.withLock { $0.error = nil }
        #expect(await loader.image(for: leon, size: .avatar(points: 40)) != nil)
    }

    // MARK: Avatar

    /// Schneller Wechsel zwischen zwei Personen, der erste Download kommt zu spät: Es bleibt das Bild der zweiten.
    @Test func lateDownloadNeverReplacesTheCurrentPerson() async throws {
        let media = repository()
        media.gate.close("data:\(mia.path)")
        let loader = PaceImageLoader(repository: media)
        let model = ReferenceModel(mia)
        let host = ImageHost(AvatarProbe(model: model), loader: loader)
        defer { host.close() }
        try await host.settle()
        // Mia lädt noch: Initialen, kein Foto.
        #expect(!host.centerIs(.red) && !host.centerIs(.blue))

        model.reference = leon
        try await host.wait { host.centerIs(.blue) }
        #expect(host.centerIs(.blue))

        // Mias Download kommt jetzt erst an – Leon bleibt.
        media.gate.open("data:\(mia.path)")
        try await host.settle(400)
        #expect(host.centerIs(.blue), "Verspäteter Download hat das Bild überschrieben")

        // Zurück zu Mia: sofort (Mias Daten sind inzwischen im Speicher) bzw. nach dem Laden ihr Bild, nie Leons.
        model.reference = mia
        try await host.settle(50)
        #expect(!host.centerIs(.blue), "Altes Bild nach dem Wechsel sichtbar")
        try await host.wait { host.centerIs(.red) }
        #expect(host.centerIs(.red))

        // Bild entfernt: Initialen.
        model.reference = nil
        try await host.settle(100)
        #expect(!host.centerIs(.red) && !host.centerIs(.blue))
    }

    /// Fehlgeschlagener Download: Initialen statt endlosem Laden; dasselbe Bild in mehreren Ansichten lädt einmal.
    @Test func failedDownloadShowsInitialsAndSharedImagesLoadOnce() async throws {
        let media = repository()
        media.state.withLock { $0.error = .network }
        let loader = PaceImageLoader(repository: media)
        let model = ReferenceModel(leon)
        let host = ImageHost(AvatarProbe(model: model, copies: 3), loader: loader)
        defer { host.close() }
        try await host.settle(400)
        #expect(!host.centerIs(.blue))
        #expect(media.state.withLock { $0.downloads[leon] ?? 0 } <= 3)

        media.state.withLock { $0.error = nil; $0.downloads = [:] }
        model.reference = mia
        try await host.wait { host.centerIs(.red) }
        #expect(host.centerIs(.red))
        #expect(media.state.withLock { $0.downloads[mia] } == 1, "Gleiches Bild in drei Ansichten: ein Download")
    }

    /// Gruppenbild: Wechsel zu einer anderen Gruppe zeigt nie das Bild der vorherigen.
    @Test func groupImageSwitchesCleanly() async throws {
        let media = repository()
        let loader = PaceImageLoader(repository: media)
        let model = ReferenceModel(group)
        let host = ImageHost(RemoteImageProbe(model: model), loader: loader)
        defer { host.close() }
        try await host.wait { host.centerIs(.green) }
        #expect(host.centerIs(.green))

        media.gate.close("data:\(leon.path)")
        model.reference = leon
        try await host.settle(100)
        #expect(!host.centerIs(.green), "Bild der vorherigen Gruppe sichtbar")
        media.gate.open("data:\(leon.path)")
        try await host.wait { host.centerIs(.blue) }
        #expect(host.centerIs(.blue))
    }
}

// MARK: - Testaufbau

@MainActor
@Observable
private final class ReferenceModel {
    var reference: MediaReference?

    init(_ reference: MediaReference?) {
        self.reference = reference
    }
}

private struct AvatarProbe: View {
    let model: ReferenceModel
    var copies = 1

    var body: some View {
        // Oben ausgerichtet: Das große Bild liegt fest bei y = 0…120 (Messpunkt in seiner Mitte).
        VStack(spacing: 4) {
            PaceAvatar(name: "Test Person", seed: "x", size: 120, image: model.reference)
            ForEach(1..<max(copies, 1), id: \.self) { _ in
                PaceAvatar(name: "Test Person", seed: "x", size: 24, image: model.reference)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct RemoteImageProbe: View {
    let model: ReferenceModel

    var body: some View {
        PaceRemoteImage(model.reference)
            .frame(width: 120, height: 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

@MainActor
private final class ImageHost {
    private let controller: UIHostingController<AnyView>
    private let window: UIWindow
    private static let size = CGSize(width: 200, height: 300)

    init(_ content: some View, loader: PaceImageLoader) {
        controller = UIHostingController(rootView: AnyView(content.environment(\.paceImageLoader, loader)))
        controller.overrideUserInterfaceStyle = .light
        window = UIWindow(frame: CGRect(origin: .zero, size: Self.size))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
    }

    func settle(_ milliseconds: Int = 300) async throws {
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(milliseconds))
        controller.view.layoutIfNeeded()
    }

    func wait(timeout: Duration = .seconds(6), until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        controller.view.layoutIfNeeded()
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            controller.view.layoutIfNeeded()
        }
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }

    /// Farbe in der Mitte des ersten (großen) Bilds.
    func centerIs(_ color: UIColor) -> Bool {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: Self.size, format: format).image { context in
            controller.view.layer.render(in: context.cgContext)
        }
        guard let cgImage = image.cgImage else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        // Mitte des oberen Bilds (120 pt, oben im zentrierten Stapel).
        let point = CGPoint(x: Self.size.width / 2, y: probeY)
        context.translateBy(x: -point.x, y: -(Self.size.height - point.y))
        context.draw(cgImage, in: CGRect(origin: .zero, size: Self.size))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return abs(Int(pixel[0]) - Int(red * 255)) < 40 && abs(Int(pixel[1]) - Int(green * 255)) < 40 && abs(Int(pixel[2]) - Int(blue * 255)) < 40
    }

    /// Senkrechte Mitte des großen Bilds (oben ausgerichtet, 120 pt hoch).
    private var probeY: CGFloat { 60 }
}
