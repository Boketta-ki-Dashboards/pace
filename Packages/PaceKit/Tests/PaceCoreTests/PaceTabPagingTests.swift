import Foundation
import PaceCore
import Testing

/// Wischen zwischen den Haupttabs: Richtung, Position, Ruhezustand, sichtbare Seiten.
struct PaceTabPagingTests {
    private let tabs = ["home", "rankings", "social", "profile"]

    @Test func fingerToTheRightLeadsToTheNextTab() {
        // Seiten liegen umgekehrt: Profil ganz links, Home ganz rechts (Start).
        #expect(PaceTabPaging.visualOrder(tabs, advancesWithFingerMovingRight: true) == ["profile", "social", "rankings", "home"])
        #expect(PaceTabPaging.visualOrder(tabs, advancesWithFingerMovingRight: false) == tabs)
        #expect(PaceTabPaging.advancesWithFingerMovingRight)
    }

    @Test func positionFollowsTheScrollOffset() {
        let width: CGFloat = 400
        // Ganz rechts (Versatz 1 200) = Home.
        #expect(PaceTabPaging.position(offset: 1_200, pageWidth: width, count: 4, advancesWithFingerMovingRight: true) == 0)
        // Finger nach rechts: Inhalt wandert nach rechts, der Versatz wird kleiner – halb zwischen Home und Rankings.
        #expect(PaceTabPaging.position(offset: 1_000, pageWidth: width, count: 4, advancesWithFingerMovingRight: true) == 0.5)
        #expect(PaceTabPaging.position(offset: 400, pageWidth: width, count: 4, advancesWithFingerMovingRight: true) == 2)
        #expect(PaceTabPaging.position(offset: 0, pageWidth: width, count: 4, advancesWithFingerMovingRight: true) == 3)
        // iOS-übliche Richtung.
        #expect(PaceTabPaging.position(offset: 600, pageWidth: width, count: 4, advancesWithFingerMovingRight: false) == 1.5)
    }

    @Test func rubberBandBeyondTheEndsIsClamped() {
        #expect(PaceTabPaging.position(offset: 1_350, pageWidth: 400, count: 4, advancesWithFingerMovingRight: true) == 0)
        #expect(PaceTabPaging.position(offset: -80, pageWidth: 400, count: 4, advancesWithFingerMovingRight: true) == 3)
        #expect(PaceTabPaging.position(offset: 100, pageWidth: 0, count: 4) == nil)
    }

    @Test func onlyWholePositionsCountAsSettled() {
        #expect(PaceTabPaging.settledIndex(2) == 2)
        #expect(PaceTabPaging.settledIndex(1.9995) == 2)
        #expect(PaceTabPaging.settledIndex(1.5) == nil)
        #expect(PaceTabPaging.settledIndex(0.98) == nil)
    }

    @Test func pagesInViewAreTheNeighboursOfThePosition() {
        #expect(PaceTabPaging.visibleIndices(1, count: 4) == [1])
        #expect(PaceTabPaging.visibleIndices(1.3, count: 4) == [1, 2])
        #expect(PaceTabPaging.visibleIndices(2.99, count: 4) == [2, 3])
        #expect(PaceTabPaging.visibleIndices(5, count: 4) == [3])
        #expect(PaceTabPaging.visibleIndices(0, count: 0).isEmpty)
    }

    @Test func initialAnchorPointsAtTheSelectedPage() {
        // Umgekehrte Reihenfolge: Home ganz rechts, Profil ganz links.
        #expect(PaceTabPaging.initialAnchorX(index: 0, count: 4) == 1)
        #expect(PaceTabPaging.initialAnchorX(index: 3, count: 4) == 0)
        #expect(abs(PaceTabPaging.initialAnchorX(index: 2, count: 4) - 1.0 / 3.0) < 0.0001)
        // Übliche Richtung: Home ganz links.
        #expect(PaceTabPaging.initialAnchorX(index: 0, count: 4, advancesWithFingerMovingRight: false) == 0)
        #expect(PaceTabPaging.initialAnchorX(index: 9, count: 4, advancesWithFingerMovingRight: false) == 1)
        #expect(PaceTabPaging.initialAnchorX(index: 0, count: 1) == 0)
        // Der Anker trifft genau die Seite: Versatz = Anker × (Seiten − 1) Seitenbreiten.
        let offset = PaceTabPaging.initialAnchorX(index: 2, count: 4) * 3 * 390
        #expect(PaceTabPaging.position(offset: offset, pageWidth: 390, count: 4).map { ($0 * 1000).rounded() / 1000 } == 2)
    }
}
