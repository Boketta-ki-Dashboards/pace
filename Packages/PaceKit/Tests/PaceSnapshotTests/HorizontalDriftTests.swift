@testable import ActivityFeature
import DesignSystem
import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import SwiftUI
import Testing
import UIKit

/// Keine waagerechte Verschiebung von Seiten, die nur senkrecht scrollen (Auftrag 6, Teil A).
///
/// Im Anpassen-Modus von Home ließ sich auf dem iPhone die ganze Seite seitlich verschieben. Geprüft wird im echten
/// Fenster mit dem Pager der Haupttabs (Wischen im Anpassen-Modus gesperrt wie in `MainTabView`):
/// - Fingerbewegungen werden so auf die Scrollansichten übertragen, wie UIKit sie verteilt: Die innerste Scrollansicht,
///   die in der Hauptrichtung scrollen kann, folgt dem Finger; eine waagerechte Bewegung kommt nur an, wenn die
///   Scrollansicht waagerecht scrollen oder nachfedern kann, und die Richtungssperre hält diagonale Bewegungen in der
///   Hauptrichtung. Echte Berührungen lassen sich ohne eigenes UI-Test-Ziel nicht erzeugen – das bleibt der
///   Gerätetest (`docs/IPHONE_TEST.md`).
/// - Danach wird an den Pixeln gemessen, wo Wortmarke, Überschrift, „Fertig“/„+ Widget hinzufügen“ und die
///   Widget-Ränder liegen. Sie dürfen sich waagerecht nicht bewegen.
@MainActor
@Suite(.serialized)
struct HorizontalDriftTests {
    struct Device: CustomTestStringConvertible, Sendable {
        let name: String
        let size: CGSize
        let safeArea: UIEdgeInsets
        var testDescription: String { name }

        static let small = Device(name: "iPhone SE", size: CGSize(width: 375, height: 667), safeArea: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0))
        static let large = Device(name: "iPhone Pro Max", size: CGSize(width: 430, height: 932), safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0))
    }

    // MARK: Home im Anpassen-Modus

    /// Die zwölf Schritte aus dem Auftrag: normal, Anpassen, langsam/schnell nach links und rechts, diagonal nach unten
    /// und oben, Widget verschieben, Anpassen beenden, danach normales Tab-Wischen.
    @Test(arguments: [Device.small, Device.large])
    func editModeStaysHorizontallyFixed(device: Device) async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.loadStreakIfNeeded()
        let screen = DriftScreen(EditablePagerHarness(dashboard: dashboard), device: device)
        defer { screen.close() }
        try await screen.settle()

        // 1. Home normal.
        let normal = screen.measure()
        #expect(normal.header != nil && normal.title != nil && normal.content != nil, "Messung ohne Inhalt: \(normal)")

        // 2. Anpassen: Wischen zwischen den Tabs ist gesperrt.
        dashboard.beginEditing()
        try await screen.settle()
        let pager = try #require(screen.pager)
        #expect(!pager.isScrollEnabled)
        let pagerOffset = pager.contentOffset.x
        let editing = screen.measure()
        #expect(editing.header != nil && editing.title != nil && editing.content != nil, "Messung ohne Inhalt: \(editing)")
        screen.logScrollViews("Anpassen")

        // 3.–6. Langsam und schnell nach links und rechts (kleine und große Wege).
        for dx in [-40, 40, -device.size.width * 0.8, device.size.width * 0.8] as [CGFloat] {
            try await screen.drag(dx: dx, dy: 0)
            screen.expectNoHorizontalOffset("waagerecht \(Int(dx))")
            screen.expectSamePosition(editing, "waagerecht \(Int(dx))", compareRows: true)
            #expect(abs(pager.contentOffset.x - pagerOffset) < 0.5, "Pager bewegt (\(Int(dx)))")
            try await screen.release()
        }

        // 7./8. Diagonal nach unten und oben: senkrecht scrollt die Seite, waagerecht bleibt sie fest.
        let scrollView = try #require(screen.pageScrollView)
        let startY = scrollView.contentOffset.y
        try await screen.drag(dx: 60, dy: -160)
        #expect(scrollView.contentOffset.y > startY + 40, "Senkrechtes Scrollen muss weiter gehen")
        screen.expectNoHorizontalOffset("diagonal nach unten")
        screen.expectSamePosition(editing, "diagonal nach unten", compareRows: false)
        try await screen.release()
        try await screen.drag(dx: -60, dy: 160)
        screen.expectNoHorizontalOffset("diagonal nach oben")
        screen.expectSamePosition(editing, "diagonal nach oben", compareRows: false)
        try await screen.release()
        try await screen.scrollToTop()

        // 9./10. Widget verschieben und ablegen (Umsortieren wie mit dem Griff): Ränder bleiben, wo sie waren.
        let first = try #require(dashboard.modules.first?.id)
        dashboard.moveDown(first)
        try await screen.settle()
        screen.expectSamePosition(editing, "nach dem Verschieben", compareRows: false)
        screen.expectNoHorizontalOffset("nach dem Verschieben")
        #expect(abs(pager.contentOffset.x - pagerOffset) < 0.5)

        // 11./12. Anpassen beenden: normales Tab-Wischen funktioniert wieder (Finger nach links → nächster Tab).
        dashboard.endEditing()
        try await screen.settle()
        #expect(pager.isScrollEnabled)
        try await screen.drag(dx: -device.size.width / 2, dy: 0)
        #expect(pager.contentOffset.x > pagerOffset + device.size.width / 3, "Tab-Wischen nach dem Anpassen")
        #expect(screen.isPageColor(1, atX: device.size.width - 30), "Rechts erscheint der nächste Tab")
    }

    /// Gegenprobe ohne Sperre: Protokolliert, ob die Scrollansichten waagerecht beweglich wären (zur Ursachenanalyse;
    /// mit den Testdaten muss der Fehler nicht auftreten).
    @Test func diagnosisWithoutLock() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.loadStreakIfNeeded()
        dashboard.beginEditing()
        let screen = DriftScreen(
            EditablePagerHarness(dashboard: dashboard).environment(\.paceVerticalScrollLockEnabled, false),
            device: .large
        )
        defer { screen.close() }
        try await screen.settle()
        screen.logScrollViews("Gegenprobe ohne Sperre")
        try await screen.drag(dx: -80, dy: 20)
        screen.logScrollViews("Gegenprobe ohne Sperre, während des Ziehens")
        let pager = try #require(screen.pager)
        #expect(!pager.isScrollEnabled, "Auch ohne Sperre ist das Tab-Wischen im Anpassen-Modus aus")
    }

    // MARK: Andere Seiten (Teil A, 3)

    /// Seiten, die nur senkrecht scrollen: Weder waagerechte noch diagonale Bewegungen verschieben sie seitlich.
    @Test func verticalPagesNeverDriftSideways() async throws {
        let (dashboard, _) = try await SnapshotFixtures.makeDashboard()
        await dashboard.loadStreakIfNeeded()
        let social = await SocialSnapshotData.social()
        let (chats, loader) = await ChatSnapshotData.groupSetup()
        let chat = chats.chat(for: .group(id: ChatSnapshotData.groupID, name: "Smoking red"))
        await chat.load()

        let pages: [(String, AnyView)] = [
            ("Home", AnyView(HomeView(viewModel: dashboard))),
            ("Statistik", AnyView(NavigationStack { StatisticsView(viewModel: dashboard.statistics(for: StatisticsRoute(period: .week, metric: .steps)), backTitle: "Home") })),
            ("Flammenkalender", AnyView(NavigationStack { StreakDetailView(viewModel: dashboard.streakDetail(), backTitle: "Home") })),
            ("Social", AnyView(SocialView(viewModel: social))),
            ("Gruppenchat", AnyView(NavigationStack { ChatView(viewModel: chat, onOpenProfile: { _ in }) }.environment(\.paceImageLoader, loader))),
        ]
        for (name, page) in pages {
            let screen = DriftScreen(MainScreenHarness(selected: 0, content: page), device: .large)
            try await screen.settle(900)
            let before = screen.measure()
            for (dx, dy) in [(-120, 0), (120, 0), (70, -150), (-70, 150)] as [(CGFloat, CGFloat)] {
                try await screen.drag(dx: dx, dy: dy, lockPager: true)
                screen.expectNoHorizontalOffset("\(name) \(Int(dx))/\(Int(dy))")
                if dy == 0 {
                    // Karussells (bewusst waagerecht) dürfen sich bewegen – Kopf und Überschrift nicht.
                    screen.expectSamePosition(before, "\(name) \(Int(dx))", compareRows: true, compareContent: false)
                }
                try await screen.release()
            }
            screen.close()
        }
    }
}

// MARK: - Testaufbau

/// Pager wie in `MainTabView`: Wischen gesperrt, solange Home angepasst wird. Die anderen Tabs sind einfarbig, damit
/// eine Bewegung des Pagers sichtbar wäre.
private struct EditablePagerHarness: View {
    let dashboard: HomeDashboardViewModel
    @State private var selection = 0

    static let colors: [UIColor] = [.clear, UIColor(red: 0, green: 0.8, blue: 0, alpha: 1), .systemBlue, .systemYellow]

    var body: some View {
        PaceTabPager(tabs: [0, 1, 2, 3], selection: $selection, isPagingEnabled: !dashboard.isEditing, onPositionChange: { _ in }) { tab in
            if tab == 0 {
                HomeView(viewModel: dashboard)
            } else {
                Color(uiColor: Self.colors[tab])
            }
        }
    }
}

/// Fenster mit Messungen an Pixeln und nachgestellten Fingerbewegungen.
@MainActor
private final class DriftScreen {
    struct Extent: Equatable, CustomStringConvertible {
        var minX: Int
        var maxX: Int
        var description: String { "\(minX)…\(maxX)" }
    }

    struct Measurement: CustomStringConvertible {
        /// Zeile mit Wortmarke und „Anpassen“/„Fertig“.
        var header: Extent?
        /// Zeile mit Begrüßung (und „+ Widget hinzufügen“).
        var title: Extent?
        /// Linker und rechter Rand aller Inhalte unterhalb des Kopfes (Widget-Ränder).
        var content: Extent?
        var description: String { "Kopf \(header?.description ?? "–"), Titel \(title?.description ?? "–"), Inhalt \(content?.description ?? "–")" }
    }

    let controller: UIHostingController<AnyView>
    let window: UIWindow
    let device: HorizontalDriftTests.Device
    /// Versatz vor der laufenden Fingerbewegung (für das Loslassen).
    private var dragStart: [(UIScrollView, CGPoint)] = []

    init(_ content: some View, device: HorizontalDriftTests.Device) {
        self.device = device
        controller = UIHostingController(rootView: AnyView(content))
        controller.overrideUserInterfaceStyle = .light
        controller.additionalSafeAreaInsets = device.safeArea
        window = UIWindow(frame: CGRect(origin: .zero, size: device.size))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
    }

    func settle(_ milliseconds: Int = 600) async throws {
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(milliseconds))
        controller.view.layoutIfNeeded()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }

    // MARK: Scrollansichten

    var scrollViews: [UIScrollView] {
        var result: [UIScrollView] = []
        func collect(_ view: UIView) {
            if let scrollView = view as? UIScrollView, !scrollView.isHidden, scrollView.window != nil {
                result.append(scrollView)
            }
            view.subviews.forEach(collect)
        }
        collect(controller.view)
        return result
    }

    var pager: UIScrollView? {
        scrollViews.first { PaceVerticalScrollLockRules.isPager($0) }
    }

    /// Senkrechte Scrollansichten in Seitengröße (keine Karussells, keine Seitenleiste).
    var pageScrollViews: [UIScrollView] {
        scrollViews.filter { scrollView in
            guard !PaceVerticalScrollLockRules.isPager(scrollView) else { return false }
            let frame = scrollView.convert(scrollView.bounds, to: window)
            return frame.width >= device.size.width * 0.9 && frame.height >= device.size.height * 0.4
                && window.bounds.intersects(frame)
                && frame.minX > -1 && frame.maxX < device.size.width + 1
        }
    }

    var pageScrollView: UIScrollView? {
        pageScrollViews.max { $0.contentSize.height < $1.contentSize.height }
    }

    func logScrollViews(_ label: String) {
        for scrollView in scrollViews {
            let frame = scrollView.convert(scrollView.bounds, to: window)
            print("""
            [Drift] \(label): \(type(of: scrollView)) frame=\(frame.integral) content=\(scrollView.contentSize) \
            offset=\(scrollView.contentOffset) enabled=\(scrollView.isScrollEnabled) \
            bounceH=\(scrollView.alwaysBounceHorizontal) bounceV=\(scrollView.alwaysBounceVertical) \
            lock=\(scrollView.isDirectionalLockEnabled) pager=\(PaceVerticalScrollLockRules.isPager(scrollView)) \
            canMoveH=\(Self.canMove(scrollView, horizontally: true))
            """)
        }
    }

    /// Ob UIKit eine Fingerbewegung in dieser Richtung an die Scrollansicht weitergäbe (scrollen oder nachfedern).
    static func canMove(_ scrollView: UIScrollView, horizontally: Bool) -> Bool {
        guard scrollView.isScrollEnabled, scrollView.isUserInteractionEnabled, scrollView.panGestureRecognizer.isEnabled else { return false }
        let inset = scrollView.adjustedContentInset
        if horizontally {
            return scrollView.contentSize.width + inset.left + inset.right > scrollView.bounds.width + 0.5 || scrollView.alwaysBounceHorizontal
        }
        return scrollView.contentSize.height + inset.top + inset.bottom > scrollView.bounds.height + 0.5 || scrollView.alwaysBounceVertical
    }

    // MARK: Fingerbewegung

    /// Finger um (`dx`, `dy`) in der Bildschirmmitte bewegen: Die innerste Scrollansicht unter dem Finger, die in der
    /// Hauptrichtung scrollen kann, übernimmt die Bewegung (wie UIKit). Sie folgt dem Finger (Versatz entgegengesetzt)
    /// – waagerecht nur, wenn sie waagerecht scrollen oder nachfedern kann, und mit Richtungssperre nur in der
    /// Hauptrichtung.
    /// - Parameter lockPager: Die Seitenleiste nicht bewegen (wie auf Unterseiten, wo Wischen gesperrt ist).
    func drag(dx: CGFloat, dy: CGFloat, lockPager: Bool = false) async throws {
        let point = CGPoint(x: device.size.width / 2, y: device.size.height / 2)
        let horizontalDominant = abs(dx) >= abs(dy)
        // Innerste zuerst: tiefere Scrollansichten stehen in der Sammlung später.
        let candidates = scrollViews.reversed().filter { scrollView in
            scrollView.convert(scrollView.bounds, to: window).contains(point)
                && !(lockPager && PaceVerticalScrollLockRules.isPager(scrollView))
        }
        guard let target = candidates.first(where: { Self.canMove($0, horizontally: horizontalDominant) }) else { return }
        dragStart = [(target, target.contentOffset)]
        var moveX = Self.canMove(target, horizontally: true) ? -dx : 0
        var moveY = Self.canMove(target, horizontally: false) ? -dy : 0
        if target.isDirectionalLockEnabled {
            if horizontalDominant { moveY = 0 } else { moveX = 0 }
        }
        target.contentOffset = CGPoint(x: target.contentOffset.x + moveX, y: target.contentOffset.y + moveY)
        try await settle(250)
    }

    /// Finger loslassen: Die Scrollansicht kehrt in den gültigen Bereich zurück (Nachfedern endet).
    func release() async throws {
        for (scrollView, start) in dragStart {
            let inset = scrollView.adjustedContentInset
            let maxY = max(-inset.top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
            let y = min(max(scrollView.contentOffset.y, -inset.top), maxY)
            let maxX = max(-inset.left, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
            let x = PaceVerticalScrollLockRules.isPager(scrollView) ? start.x : min(max(scrollView.contentOffset.x, -inset.left), maxX)
            scrollView.contentOffset = CGPoint(x: x, y: y)
        }
        dragStart = []
        try await settle(250)
    }

    func scrollToTop() async throws {
        guard let scrollView = pageScrollView else { return }
        scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top)
        try await settle(300)
    }

    // MARK: Prüfungen

    /// Keine senkrechte Seite ist waagerecht verschoben.
    func expectNoHorizontalOffset(_ label: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for scrollView in pageScrollViews {
            let resting = PaceVerticalScrollLockRules.restingX(scrollView)
            #expect(abs(scrollView.contentOffset.x - resting) < 0.5, "\(label): Seite um \(scrollView.contentOffset.x - resting) pt verschoben", sourceLocation: sourceLocation)
        }
    }

    /// Wortmarke, Überschrift, Buttons und Widget-Ränder stehen waagerecht an derselben Stelle (± 3 pt für das
    /// Wackeln und die Schatten im Anpassen-Modus).
    func expectSamePosition(
        _ reference: Measurement,
        _ label: String,
        compareRows: Bool,
        compareContent: Bool = true,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let now = measure()
        func check(_ old: Extent?, _ new: Extent?, _ part: String) {
            guard let old else { return }
            guard let new else {
                Issue.record("\(label): \(part) nicht mehr sichtbar", sourceLocation: sourceLocation)
                return
            }
            #expect(abs(old.minX - new.minX) <= 3 && abs(old.maxX - new.maxX) <= 3, "\(label): \(part) \(old) → \(new)", sourceLocation: sourceLocation)
        }
        if compareRows {
            check(reference.header, now.header, "Kopfzeile (Wortmarke, Button)")
            check(reference.title, now.title, "Überschrift")
        }
        if compareContent {
            check(reference.content, now.content, "Widget-Ränder")
        }
    }

    func isPageColor(_ page: Int, atX x: CGFloat) -> Bool {
        let (data, width, _) = pixels()
        let y = Int(device.size.height / 2)
        let index = (y * width + Int(x)) * 4
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        EditablePagerHarness.colors[page].getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return abs(Int(data[index]) - Int(red * 255)) < 30 && abs(Int(data[index + 1]) - Int(green * 255)) < 30
            && abs(Int(data[index + 2]) - Int(blue * 255)) < 30
    }

    // MARK: Pixel

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

    private var background: (Int, Int, Int) {
        let color = UIColor(PaceColor.background).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    /// Kopfzeile, Überschrift (erste und zweite Inhaltszeile unter der Statusleiste) und Inhaltsränder darunter.
    func measure() -> Measurement {
        let (data, width, height) = pixels()
        let (red, green, blue) = background
        func isContent(_ x: Int, _ y: Int) -> Bool {
            let index = (y * width + x) * 4
            return abs(Int(data[index]) - red) > 10 || abs(Int(data[index + 1]) - green) > 10 || abs(Int(data[index + 2]) - blue) > 10
        }
        func extent(rows: Range<Int>) -> Extent? {
            var minX = Int.max, maxX = Int.min
            for y in rows where y >= 0 && y < height {
                for x in 0..<width where isContent(x, y) {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                }
            }
            return minX <= maxX ? Extent(minX: minX, maxX: maxX) : nil
        }
        // Zusammenhängende Inhaltszeilen unterhalb der Statusleiste.
        let top = Int(device.safeArea.top)
        var runs: [Range<Int>] = []
        var start: Int?
        for y in top..<min(top + 240, height) {
            let hasContent = (0..<width).contains { isContent($0, y) }
            if hasContent, start == nil { start = y }
            if !hasContent, let begin = start {
                if y - begin >= 8 { runs.append(begin..<y) }
                start = nil
            }
            if runs.count == 2 { break }
        }
        let contentTop = (runs.last?.upperBound ?? top + 120) + 20
        let contentBottom = height - Int(device.safeArea.bottom) - 20
        return Measurement(
            header: runs.first.flatMap { extent(rows: $0) },
            title: runs.count > 1 ? extent(rows: runs[1]) : nil,
            content: contentTop < contentBottom ? extent(rows: contentTop..<contentBottom) : nil
        )
    }
}
