import DesignSystem
import Foundation
import PaceCore
import SwiftUI
import Testing
import UIKit

/// Wischrichtung der Haupttabs am echten UIKit-Pager im Fenster (Simulator, P0 Auftrag 4).
///
/// Geprüft wird die sichtbare Bewegung, nicht nur der Index: Jede Seite hat eine eigene Farbe (Home rot, Rankings
/// grün, Social blau, Profil gelb). Die Seiten folgen dem Finger wie bei einer echten Wischgeste (der Scroll-Versatz
/// ändert sich entgegengesetzt zur Fingerbewegung); danach wird an der linken und rechten Bildschirmhälfte gemessen,
/// welche Seite dort zu sehen ist.
@MainActor
@Suite(.serialized)
struct TabPagerDirectionTests {
    private static let size = CGSize(width: 393, height: 852)

    /// Finger von rechts nach links: Die nächste Seite kommt von rechts herein.
    @Test(arguments: [0, 1, 2])
    func fingerToTheLeftBringsInTheNextTabFromTheRight(start: Int) async throws {
        try await checkTransition(from: start, to: start + 1)
    }

    /// Finger von links nach rechts: Die vorherige Seite kommt von links herein.
    @Test(arguments: [3, 2, 1])
    func fingerToTheRightBringsInThePreviousTabFromTheLeft(start: Int) async throws {
        try await checkTransition(from: start, to: start - 1)
    }

    /// Anfangs gewählter Social- bzw. Profil-Tab (z. B. über einen Link): Der Pager steht sofort auf dieser Seite.
    @Test(arguments: [2, 3])
    func initiallySelectedTabIsShown(start: Int) async throws {
        let host = PagerHost(initial: start)
        defer { host.close() }
        try await host.settle(milliseconds: 700)
        #expect(host.page(atX: 40) == start)
        #expect(host.page(atX: Self.size.width - 40) == start)
        #expect(host.recorder.selection == start)
    }

    /// Unterseite offen, Anpassen-Modus oder Tastatur: Der Pager lässt sich nicht wischen (Zurück-Geste bleibt frei).
    @Test func subpagesDisablePaging() async throws {
        let host = PagerHost(initial: 2, isPagingEnabled: false)
        defer { host.close() }
        try await host.settle(milliseconds: 700)
        let pager = try #require(host.pager)
        #expect(!pager.isScrollEnabled)
    }

    // MARK: Ablauf

    /// Teilweise wischen (beide Seiten sichtbar, Tab-Fläche dazwischen), zurückziehen (Ausgangsseite bleibt), dann
    /// vollständig wischen (Zielseite aktiv).
    private func checkTransition(from start: Int, to target: Int) async throws {
        let host = PagerHost(initial: start)
        defer { host.close() }
        try await host.settle(milliseconds: 700)
        #expect(host.page(atX: 40) == start)
        #expect(host.page(atX: Self.size.width - 40) == start)

        let width = Self.size.width
        let fingerDirection: CGFloat = target > start ? -1 : 1

        // Halber Weg: Die Zielseite liegt auf der Seite, auf die der Finger zeigt.
        let middle = (Double(start) + Double(target)) / 2
        host.drag(fromTab: start, finger: fingerDirection * width / 2)
        try await host.wait { host.recorder.position.map { abs($0 - middle) < 0.05 } == true }
        let left = host.page(atX: width / 4)
        let right = host.page(atX: width * 3 / 4)
        if target > start {
            #expect(left == start, "Finger nach links: links noch die Ausgangsseite")
            #expect(right == target, "Finger nach links: die nächste Seite kommt von rechts")
        } else {
            #expect(left == target, "Finger nach rechts: die vorherige Seite kommt von links")
            #expect(right == start, "Finger nach rechts: rechts noch die Ausgangsseite")
        }
        // Die Tab-Leiste bekommt dieselbe Position: Die Fläche liegt zwischen beiden Tabs.
        let halfway = try #require(host.recorder.position)
        #expect(abs(halfway - middle) < 0.05)
        #expect(host.recorder.selection == start)

        // Zurückziehen: Ausgangsseite bleibt aktiv.
        host.drag(fromTab: start, finger: 0)
        try await host.wait { host.recorder.position.map { abs($0 - Double(start)) < 0.002 } == true }
        #expect(host.recorder.selection == start)
        #expect(host.page(atX: width / 4) == start)
        #expect(host.page(atX: width * 3 / 4) == start)

        // Vollständig: Zielseite ganz sichtbar und gewählt.
        host.drag(fromTab: start, finger: fingerDirection * width)
        try await host.wait { host.recorder.selection == target }
        #expect(host.page(atX: 40) == target)
        #expect(host.page(atX: width - 40) == target)
        #expect(host.recorder.selection == target)
        #expect(host.recorder.position.map { ($0 * 100).rounded() / 100 } == Double(target))
    }
}

// MARK: - Testaufbau

/// Hält fest, was der Pager meldet (Auswahl und laufende Position für die Tab-Leiste).
@MainActor
private final class PagerRecorder {
    var selection: Int
    var position: Double?

    init(selection: Int) {
        self.selection = selection
    }
}

/// Vier einfarbige Seiten im Pager, darunter die Tab-Leiste – wie `MainTabView`.
private struct PagerHarness: View {
    let recorder: PagerRecorder
    let isPagingEnabled: Bool

    @State private var selection: Int
    @State private var position: Double?

    init(recorder: PagerRecorder, isPagingEnabled: Bool) {
        self.recorder = recorder
        self.isPagingEnabled = isPagingEnabled
        _selection = State(initialValue: recorder.selection)
    }

    static let colors: [Color] = [
        Color(red: 1, green: 0, blue: 0),
        Color(red: 0, green: 1, blue: 0),
        Color(red: 0, green: 0, blue: 1),
        Color(red: 1, green: 1, blue: 0),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PaceTabPager(
                tabs: [0, 1, 2, 3],
                selection: $selection,
                isPagingEnabled: isPagingEnabled,
                onPositionChange: { value in
                    position = value
                    recorder.position = value
                }
            ) { tab in
                Self.colors[tab]
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            PaceTabBar(
                items: [
                    PaceTabItem(value: 0, title: "Home", systemImage: "house", selectedSystemImage: "house.fill"),
                    PaceTabItem(value: 1, title: "Rankings", systemImage: "chart.bar", selectedSystemImage: "chart.bar.fill"),
                    PaceTabItem(value: 2, title: "Social", systemImage: "person.2", selectedSystemImage: "person.2.fill"),
                    PaceTabItem(value: 3, title: "Profil", systemImage: "person", selectedSystemImage: "person.fill"),
                ],
                selection: $selection,
                position: position
            )
        }
        .onChange(of: selection) { _, value in
            recorder.selection = value
        }
    }
}

/// Fenster mit dem Pager; Wischen per Scroll-Versatz wie bei einer echten Geste.
@MainActor
private final class PagerHost {
    let recorder: PagerRecorder
    private let window: UIWindow
    private let controller: UIHostingController<PagerHarness>

    init(initial: Int, isPagingEnabled: Bool = true) {
        recorder = PagerRecorder(selection: initial)
        controller = UIHostingController(rootView: PagerHarness(recorder: recorder, isPagingEnabled: isPagingEnabled))
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: 393, height: 852)))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
    }

    func settle(milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
        controller.view.layoutIfNeeded()
    }

    /// Wartet, bis die Bedingung erfüllt ist (höchstens `timeout`). SwiftUI meldet Scroll-Positionen asynchron – auf
    /// ausgelasteten CI-Rechnern teils erst nach mehreren hundert Millisekunden; eine feste Wartezeit wäre zufällig.
    func wait(timeout: Duration = .seconds(3), until condition: () -> Bool) async throws {
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

    /// Die waagerechte Scrollansicht des Pagers.
    var pager: UIScrollView? {
        var found: [UIScrollView] = []
        func collect(_ view: UIView) {
            if let scrollView = view as? UIScrollView, scrollView.contentSize.width > scrollView.bounds.width + 1 {
                found.append(scrollView)
            }
            view.subviews.forEach(collect)
        }
        collect(controller.view)
        return found.max { $0.contentSize.width < $1.contentSize.width }
    }

    /// Finger hält nach einer waagerechten Bewegung (negativ = nach links) ab der Seite `tab`: Die Seiten folgen dem
    /// Finger, der Versatz ändert sich entgegengesetzt.
    func drag(fromTab tab: Int, finger translation: CGFloat) {
        guard let pager else { return }
        let start = CGFloat(tab) * pager.bounds.width
        pager.setContentOffset(CGPoint(x: start - translation, y: 0), animated: false)
    }

    /// Welche Seite (nach Farbe) an dieser Stelle in der Bildschirmmitte zu sehen ist.
    func page(atX x: CGFloat) -> Int? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { context in
            controller.view.layer.render(in: context.cgContext)
        }
        guard let cgImage = image.cgImage,
              let crop = cgImage.cropping(to: CGRect(x: Int(x), y: Int(window.bounds.height / 3), width: 1, height: 1))
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let (red, green, blue) = (pixel[0] > 160, pixel[1] > 160, pixel[2] > 160)
        switch (red, green, blue) {
        case (true, false, false): return 0
        case (false, true, false): return 1
        case (false, false, true): return 2
        case (true, true, false): return 3
        default: return nil
        }
    }
}
