import DesignSystem
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
import SwiftUI
import Testing
import UIKit

/// Home darf beim Scrollen nicht unter Uhrzeit und Symbole der Statusleiste laufen (Auftrag 5, A1).
///
/// Geprüft wird im echten Fenster mit der Safe Area eines kleinen (iPhone SE) und eines großen iPhones (Pro Max), in
/// Hell und Dunkel: Der Bereich der Statusleiste zeigt nur den Seitenhintergrund – oben, leicht gescrollt, weit
/// gescrollt, am Ende, nach einem Tabwechsel und im Anpassen-Modus. Am oberen Ende beginnt der Inhalt direkt unter der
/// Statusleiste (kein großer Leerraum). Gegenprobe: Ohne den Hintergrund liegt dort Inhalt.
@MainActor
@Suite(.serialized)
struct StatusBarSafeAreaTests {
    struct Device: CustomTestStringConvertible, Sendable {
        let name: String
        let width: CGFloat
        let height: CGFloat
        let top: CGFloat
        let bottom: CGFloat

        var testDescription: String { name }
        var size: CGSize { CGSize(width: width, height: height) }
        var safeArea: UIEdgeInsets { UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0) }

        static let small = Device(name: "iPhone SE", width: 375, height: 667, top: 20, bottom: 0)
        static let large = Device(name: "iPhone Pro Max", width: 430, height: 932, top: 59, bottom: 34)
    }

    /// Ein Fenster mit Home im Aufbau von `MainTabView`.
    @MainActor
    private final class Screen {
        let controller: UIHostingController<AnyView>
        let window: UIWindow
        let device: Device
        let scheme: ColorScheme

        init(_ content: some View, device: Device, scheme: ColorScheme) {
            self.device = device
            self.scheme = scheme
            controller = UIHostingController(rootView: AnyView(content.environment(\.colorScheme, scheme)))
            controller.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
            controller.additionalSafeAreaInsets = device.safeArea
            window = UIWindow(frame: CGRect(origin: .zero, size: device.size))
            window.rootViewController = controller
            window.isHidden = false
            controller.view.frame = window.bounds
        }

        func settle(_ milliseconds: Int = 500) async throws {
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(milliseconds))
            controller.view.layoutIfNeeded()
        }

        func close() {
            window.isHidden = true
            window.rootViewController = nil
        }

        /// RGBA-Pixel des Fensters (Skalierung 1, sRGB).
        func pixels() -> (data: [UInt8], width: Int, height: Int) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.preferredRange = .standard
            let image = UIGraphicsImageRenderer(size: device.size, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            let width = Int(device.size.width)
            let height = Int(device.size.height)
            var data = [UInt8](repeating: 0, count: width * height * 4)
            if let cgImage = image.cgImage,
               let context = CGContext(
                   data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
               ) {
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            return (data, width, height)
        }

        /// Seitenhintergrund im aktuellen Erscheinungsbild.
        var background: (Int, Int, Int) {
            let color = UIColor(PaceColor.background).resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
        }

        /// Zeilen (von oben), in denen etwas anderes als der Seitenhintergrund zu sehen ist.
        func rowsWithContent(in rows: Range<Int>) -> [Int] {
            let (data, width, _) = pixels()
            let (red, green, blue) = background
            return rows.filter { row in
                (0..<width).contains { column in
                    let index = (row * width + column) * 4
                    return abs(Int(data[index]) - red) > 6 || abs(Int(data[index + 1]) - green) > 6 || abs(Int(data[index + 2]) - blue) > 6
                }
            }
        }

        /// Statusleistenbereich (obere Safe Area) zeigt nur den Seitenhintergrund.
        var statusBarAreaIsClear: Bool {
            rowsWithContent(in: 0..<Int(device.safeArea.top)).isEmpty
        }

        var homeScrollView: UIScrollView? {
            var scrollViews: [UIScrollView] = []
            func collect(_ view: UIView) {
                if let scrollView = view as? UIScrollView, scrollView.contentSize.height > scrollView.bounds.height {
                    scrollViews.append(scrollView)
                }
                view.subviews.forEach(collect)
            }
            collect(controller.view)
            return scrollViews.max { $0.contentSize.height < $1.contentSize.height }
        }

        func scroll(to offset: CGFloat) async throws {
            guard let scrollView = homeScrollView else { return }
            let top = -scrollView.adjustedContentInset.top
            let bottom = max(top, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
            scrollView.setContentOffset(CGPoint(x: 0, y: min(bottom, top + offset)), animated: false)
            try await settle(250)
        }
    }

    private func homeScreen(editing: Bool = false, backdrop: Bool = true) async throws -> some View {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.loadStreakIfNeeded()
        if editing { dashboard.beginEditing() }
        return MainScreenHarness(selected: 0, content: AnyView(HomeView(viewModel: dashboard)))
            .environment(\.paceStatusBarBackdropEnabled, backdrop)
    }

    @Test(arguments: [Device.small, Device.large], [ColorScheme.light, ColorScheme.dark])
    func contentNeverReachesTheStatusBar(device: Device, scheme: ColorScheme) async throws {
        let screen = Screen(try await homeScreen(), device: device, scheme: scheme)
        defer { screen.close() }
        try await screen.settle(800)
        let top = Int(device.safeArea.top)

        // Oben: Inhalt beginnt direkt unter der Statusleiste – kein großer Leerraum.
        #expect(screen.statusBarAreaIsClear, "oben")
        let firstContentRow = screen.rowsWithContent(in: top..<(top + 80)).first
        #expect(firstContentRow.map { $0 < top + 40 } == true, "Inhalt beginnt erst bei \(firstContentRow ?? -1)")

        // Langsam ein Stück, weit und bis zum Ende gescrollt.
        for offset in [24, 64, 140, 600, 100_000] as [CGFloat] {
            try await screen.scroll(to: offset)
            #expect(screen.statusBarAreaIsClear, "gescrollt um \(offset)")
        }

        // Tabwechsel und zurück: weiterhin frei.
        Snapshot.scrollPager(in: screen.controller.view, toPosition: 1, pageCount: 4)
        try await screen.settle(300)
        Snapshot.scrollPager(in: screen.controller.view, toPosition: 0, pageCount: 4)
        try await screen.settle(300)
        #expect(screen.statusBarAreaIsClear, "nach Tabwechsel")

        // Zurück nach oben: kein Sprung, der Kopf steht wieder direkt unter der Statusleiste.
        try await screen.scroll(to: 0)
        #expect(screen.statusBarAreaIsClear, "wieder oben")
        #expect(screen.rowsWithContent(in: top..<(top + 80)).first == firstContentRow)
    }

    @Test func editModeAlsoStaysBelowTheStatusBar() async throws {
        let screen = Screen(try await homeScreen(editing: true), device: .large, scheme: .light)
        defer { screen.close() }
        try await screen.settle(800)
        for offset in [0, 120, 400] as [CGFloat] {
            try await screen.scroll(to: offset)
            #expect(screen.statusBarAreaIsClear, "Anpassen-Modus, gescrollt um \(offset)")
        }
    }

    /// Gegenprobe: Ohne den Statusleisten-Hintergrund läuft der Inhalt in den Bereich der Statusleiste (früherer Fehler).
    @Test func withoutTheBackdropContentRunsUnderTheStatusBar() async throws {
        let screen = Screen(try await homeScreen(backdrop: false), device: .large, scheme: .light)
        defer { screen.close() }
        try await screen.settle(800)
        try await screen.scroll(to: 64)
        #expect(!screen.statusBarAreaIsClear)
    }
}
