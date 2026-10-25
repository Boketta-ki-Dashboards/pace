import Foundation
@testable import HomeFeature
import PaceCore
import PaceTestSupport
import Testing

/// Umsortieren am Ziehgriff: Zielposition, Auto-Scroll und dauerhafte Speicherung.
struct HomeReorderMathTests {
    /// Drei Widgets untereinander: A (0–100), B (112–312, hoch), C (324–424).
    private let frames: [String: CGRect] = [
        "A": CGRect(x: 0, y: 0, width: 360, height: 100),
        "B": CGRect(x: 0, y: 112, width: 360, height: 200),
        "C": CGRect(x: 0, y: 324, width: 360, height: 100),
    ]
    private let order = ["A", "B", "C"]

    @Test func widgetStaysWhileItsCenterHasNotPassedANeighbour() {
        // A wird ein wenig nach unten gezogen – Mitte 90 liegt noch vor der Mitte von B (212).
        #expect(HomeReorderMath.targetIndex(order: order, frames: frames, dragging: "A", draggedCenterY: 90) == 0)
    }

    @Test func passingTheMiddleOfTheNextWidgetMovesDown() {
        #expect(HomeReorderMath.targetIndex(order: order, frames: frames, dragging: "A", draggedCenterY: 213) == 1)
        #expect(HomeReorderMath.targetIndex(order: order, frames: frames, dragging: "A", draggedCenterY: 400) == 2)
    }

    @Test func passingTheMiddleOfThePreviousWidgetMovesUp() {
        #expect(HomeReorderMath.targetIndex(order: order, frames: frames, dragging: "C", draggedCenterY: 211) == 1)
        #expect(HomeReorderMath.targetIndex(order: order, frames: frames, dragging: "C", draggedCenterY: 20) == 0)
    }

    @Test func positionDoesNotFlipBackAfterSwappingWithATallerWidget() {
        // A ist an B vorbei (neue Reihenfolge B, A, C); B liegt jetzt oben (0–200), A bei 212–312.
        let swapped: [String: CGRect] = [
            "B": CGRect(x: 0, y: 0, width: 360, height: 200),
            "A": CGRect(x: 0, y: 212, width: 360, height: 100),
            "C": CGRect(x: 0, y: 324, width: 360, height: 100),
        ]
        // Der Finger steht noch an derselben Stelle (Mitte von A bei 215) – keine Rückwärtsbewegung.
        #expect(HomeReorderMath.targetIndex(order: ["B", "A", "C"], frames: swapped, dragging: "A", draggedCenterY: 215) == 1)
    }

    @Test func missingFramesOrUnknownWidgetGiveNoTarget() {
        #expect(HomeReorderMath.targetIndex(order: order, frames: ["A": frames["A"]!], dragging: "A", draggedCenterY: 300) == nil)
        #expect(HomeReorderMath.targetIndex(order: order, frames: frames, dragging: "X", draggedCenterY: 300) == nil)
    }

    @Test func autoScrollOnlyNearTheEdgesAndFasterTowardsThem() {
        let height: CGFloat = 700
        #expect(HomeReorderMath.autoScrollVelocity(fingerY: 350, viewportHeight: height) == 0)
        #expect(HomeReorderMath.autoScrollVelocity(fingerY: 120, viewportHeight: height) == 0)

        let nearTop = HomeReorderMath.autoScrollVelocity(fingerY: 60, viewportHeight: height)
        let atTop = HomeReorderMath.autoScrollVelocity(fingerY: 0, viewportHeight: height)
        #expect(nearTop < 0)
        #expect(atTop < nearTop)
        #expect(atTop == -HomeReorderMath.maximumAutoScrollSpeed)

        let nearBottom = HomeReorderMath.autoScrollVelocity(fingerY: 640, viewportHeight: height)
        let beyondBottom = HomeReorderMath.autoScrollVelocity(fingerY: 760, viewportHeight: height)
        #expect(nearBottom > 0)
        #expect(beyondBottom == HomeReorderMath.maximumAutoScrollSpeed)
    }

    @Test func autoScrollZoneShrinksOnShortViewports() {
        // 180 pt hoch: Randzonen je 60 pt, die Mitte bleibt ruhig.
        #expect(HomeReorderMath.autoScrollVelocity(fingerY: 90, viewportHeight: 180) == 0)
        #expect(HomeReorderMath.autoScrollVelocity(fingerY: 10, viewportHeight: 180) < 0)
        #expect(HomeReorderMath.autoScrollVelocity(fingerY: 0, viewportHeight: 0) == 0)
    }

    @Test func scrollOffsetStaysInsideTheScrollableRange() {
        #expect(HomeReorderMath.clampedOffset(100, delta: 20, minimum: -59, maximum: 900) == 120)
        #expect(HomeReorderMath.clampedOffset(-50, delta: -40, minimum: -59, maximum: 900) == -59)
        #expect(HomeReorderMath.clampedOffset(890, delta: 40, minimum: -59, maximum: 900) == 900)
        // Inhalt kürzer als der sichtbare Bereich: kein Scrollen.
        #expect(HomeReorderMath.clampedOffset(-59, delta: 40, minimum: -59, maximum: -200) == -59)
    }
}

@MainActor
struct HomeSettingsReorderTests {
    @Test func movingToAnIndexIsSavedImmediately() throws {
        let store = InMemoryHomePreferencesStore()
        let settings = HomeSettings(store: store)
        let ids = settings.modules.map(\.id)
        try #require(ids.count >= 4)

        settings.move(ids[0], toIndex: 3)
        #expect(settings.modules.map(\.id) == [ids[1], ids[2], ids[3], ids[0]] + ids.dropFirst(4))

        settings.move(ids[0], toIndex: 0)
        #expect(settings.modules.map(\.id) == ids)

        // Außerhalb des Bereichs: an den Rand, unbekannte Widgets: nichts.
        settings.move(ids[1], toIndex: 99)
        #expect(settings.modules.last?.id == ids[1])
        settings.move("unbekannt", toIndex: 0)
        #expect(settings.modules.last?.id == ids[1])

        // „Neustart“: dieselbe Reihenfolge.
        #expect(HomeSettings(store: store).modules == settings.modules)
    }
}

/// Ziehen mit festgehaltenem Listenaufbau (P0 Auftrag 4): kein Springen nach einem Platztausch, keine Sprünge zurück,
/// alle typischen Bewegungen landen an der erwarteten Stelle.
struct HomeReorderLayoutTests {
    /// Klein (100), Groß (320), Klein (100), Mittel (210), Klein (100) – Abstand 12.
    private let heights: [String: CGFloat] = ["s1": 100, "L": 320, "s2": 100, "M": 210, "s3": 100]
    private let order = ["s1", "L", "s2", "M", "s3"]

    private var layout: HomeReorderLayout<String> {
        HomeReorderLayout(top: 140, spacing: 12, heights: heights)
    }

    /// Ablauf wie im Controller: Fingerpunkt → Mitte des gezogenen Widgets → Zielindex → neue Reihenfolge.
    private func drag(_ id: String, in start: [String], fingerPath: [CGFloat]) -> (order: [String], visualTops: [CGFloat], indices: [Int]) {
        var order = start
        let grab = fingerPath[0] - (layout.slotTop(of: id, order: order) ?? 0)
        var tops: [CGFloat] = []
        var indices: [Int] = []
        for finger in fingerPath {
            let center = finger - grab + heights[id]! / 2
            if let target = HomeReorderMath.targetIndex(order: order, frames: layout.frames(order: order), dragging: id, draggedCenterY: center),
               let source = order.firstIndex(of: id), target != source {
                order.remove(at: source)
                order.insert(id, at: target)
            }
            // Sichtbare Oberkante = Platz in der aktuellen Reihenfolge + Verschiebung (wie `offset(for:)`).
            let slot = layout.slotTop(of: id, order: order)!
            let offset = finger - grab - slot
            tops.append(slot + offset)
            indices.append(order.firstIndex(of: id)!)
        }
        return (order, tops, indices)
    }

    @Test func layoutFromMeasuredFramesDetectsTopSpacingAndHeights() throws {
        let frames = layout.frames(order: order)
        let measured = try #require(HomeReorderLayout(order: order, frames: frames, fallbackSpacing: 8))
        #expect(measured == layout)
        #expect(HomeReorderLayout(order: order, frames: ["s1": frames["s1"]!], fallbackSpacing: 8) == nil)
        #expect(HomeReorderMath.spacing(of: [frames["s1"]!], fallback: 8) == 8)
    }

    @Test func slotsFollowTheOrderImmediately() {
        #expect(layout.slotTop(of: "s1", order: order) == 140)
        #expect(layout.slotTop(of: "L", order: order) == 252)
        // Nach dem Tausch s1 ↔ L liegt s1 sofort unter L – ohne neue Messung.
        #expect(layout.slotTop(of: "s1", order: ["L", "s1", "s2", "M", "s3"]) == 472)
    }

    @Test func theDraggedWidgetStaysUnderTheFingerAcrossSwaps() {
        // Langsam von ganz oben nach ganz unten: Die sichtbare Oberkante folgt exakt dem Finger (kein Springen).
        let path = stride(from: CGFloat(160), through: 1_100, by: 3).map { $0 }
        let result = drag("s1", in: order, fingerPath: path)
        for (finger, top) in zip(path, result.visualTops) {
            #expect(abs(top - (finger - 20)) < 0.001)
        }
        #expect(result.order.last == "s1")
        // Beim Ziehen nach unten nie zurück nach oben (kein Flackern zwischen zwei Plätzen).
        #expect(zip(result.indices, result.indices.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func swappingTwoSmallWidgets() {
        let result = drag("s3", in: ["s1", "s2", "s3"].filter { heights[$0] != nil }, fingerPath: [0, -60, -115])
        // Klein-Liste ohne L/M: s3 (bei 364) über die Mitte von s2 hinaus.
        #expect(result.order == ["s1", "s3", "s2"])
    }

    @Test func movingTheLargeWidget() {
        // L nach unten bis hinter M.
        let result = drag("L", in: order, fingerPath: [260, 400, 560, 700])
        #expect(result.order == ["s1", "s2", "M", "L", "s3"])
    }

    @Test func fromTheEndToTheTopAndBack() {
        let up = drag("s3", in: order, fingerPath: [1_000, 600, 200, 100])
        #expect(up.order.first == "s3")
        let down = drag("s3", in: up.order, fingerPath: [150, 600, 1_100])
        #expect(down.order.last == "s3")
    }

    @Test func fastDragJumpsStraightToTheTarget() {
        // Ein einziger großer Schritt (schnelles Ziehen) landet direkt am Ende, ohne Zwischenstopps.
        let result = drag("s1", in: order, fingerPath: [150, 1_200])
        #expect(result.order.last == "s1")
        #expect(result.indices == [0, 4])
    }

    @Test func holdingStillDoesNotKeepReordering() {
        let result = drag("L", in: order, fingerPath: Array(repeating: 380, count: 30))
        #expect(result.order == order)
        #expect(Set(result.indices) == [1])
    }

    @Test func repeatedReorderingRightAfterAnotherStaysConsistent() {
        var current = order
        for (id, path) in [("s1", [150.0, 700.0]), ("M", [700.0, 150.0]), ("s3", [1_000.0, 300.0]), ("L", [300.0, 1_100.0])] {
            current = drag(id, in: current, fingerPath: path.map { CGFloat($0) }).order
            #expect(Set(current) == Set(order))
            #expect(current.count == order.count)
        }
    }
}

/// Beim Ziehen ändert sich die Reihenfolge live, gespeichert wird einmal beim Loslassen.
@MainActor
struct HomeReorderSavingTests {
    private final class CountingStore: HomePreferencesStoring, @unchecked Sendable {
        private let inner = InMemoryHomePreferencesStore()
        private(set) var saves = 0

        func load() -> HomePreferences? { inner.load() }

        func save(_ preferences: HomePreferences) {
            saves += 1
            inner.save(preferences)
        }
    }

    @Test func manySwapsAreSavedOnceAtTheEnd() throws {
        let store = CountingStore()
        let settings = HomeSettings(store: store)
        let ids = settings.modules.map(\.id)
        try #require(ids.count >= 4)

        settings.beginDeferringSave()
        settings.move(ids[0], toIndex: 1)
        settings.move(ids[0], toIndex: 2)
        settings.move(ids[0], toIndex: 3)
        #expect(store.saves == 0)
        #expect(settings.modules.map(\.id)[3] == ids[0])

        settings.endDeferringSave()
        #expect(store.saves == 1)
        #expect(HomeSettings(store: store).modules == settings.modules)

        // Ohne Änderung kein Speichern; danach wieder sofort.
        settings.beginDeferringSave()
        settings.endDeferringSave()
        #expect(store.saves == 1)
        settings.move(ids[0], toIndex: 0)
        #expect(store.saves == 2)
    }
}

/// Ausweichen der anderen Widgets während des Ziehens (die Reihenfolge ändert sich erst beim Loslassen).
struct HomeReorderDisplacementTests {
    @Test func widgetsBetweenSourceAndTargetMoveAside() {
        // Von Platz 1 nach Platz 3: Plätze 2 und 3 rücken nach oben, die anderen bleiben.
        #expect(HomeReorderMath.displacement(index: 0, source: 1, target: 3, step: 112) == 0)
        #expect(HomeReorderMath.displacement(index: 2, source: 1, target: 3, step: 112) == -112)
        #expect(HomeReorderMath.displacement(index: 3, source: 1, target: 3, step: 112) == -112)
        #expect(HomeReorderMath.displacement(index: 4, source: 1, target: 3, step: 112) == 0)
        // Von Platz 3 nach Platz 0: Plätze 0–2 rücken nach unten.
        #expect(HomeReorderMath.displacement(index: 0, source: 3, target: 0, step: 50) == 50)
        #expect(HomeReorderMath.displacement(index: 2, source: 3, target: 0, step: 50) == 50)
        #expect(HomeReorderMath.displacement(index: 4, source: 3, target: 0, step: 50) == 0)
        // Noch am Ausgangsplatz: niemand weicht aus.
        #expect((0..<5).allSatisfy { HomeReorderMath.displacement(index: $0, source: 2, target: 2, step: 80) == 0 })
    }

    @Test func visiblePositionsMatchTheFinalOrderOnRelease() {
        // Sichtbare Oberkanten während des Ziehens (Start-Layout + Ausweichen) = Oberkanten nach dem Übernehmen.
        let heights: [String: CGFloat] = ["a": 100, "b": 320, "c": 100, "d": 210]
        let layout = HomeReorderLayout(top: 0, spacing: 12, heights: heights)
        let order = ["a", "b", "c", "d"]
        let (source, target) = (0, 2)
        let step = heights["a"]! + 12
        var final = order
        final.remove(at: source)
        final.insert("a", at: target)
        let start = layout.frames(order: order)
        let end = layout.frames(order: final)
        for (index, id) in order.enumerated() where id != "a" {
            let visible = start[id]!.minY + HomeReorderMath.displacement(index: index, source: source, target: target, step: step)
            #expect(abs(visible - end[id]!.minY) < 0.001, "\(id) springt beim Loslassen")
        }
    }
}
