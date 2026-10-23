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
