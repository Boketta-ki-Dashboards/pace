import Foundation
import PaceCore
import Testing

/// Wischen zwischen den Haupttabs (normales Paging): Richtung, Zwischenstände, Abbruch, Ränder, Startseite.
///
/// Tab-Index: 0 Home, 1 Rankings, 2 Social, 3 Profil. Fingerbewegung negativ = von rechts nach links.
struct PaceTabPagingTests {
    private let width: CGFloat = 393

    private func position(from index: Int, finger: CGFloat) -> Double? {
        PaceTabPaging.position(from: index, fingerTranslation: finger, pageWidth: width, count: 4)
    }

    // MARK: Alle sechs Übergänge

    @Test func fingerToTheLeftOpensTheNextTabOnTheRight() {
        #expect(position(from: 0, finger: -width) == 1) // Home → Rankings
        #expect(position(from: 1, finger: -width) == 2) // Rankings → Social
        #expect(position(from: 2, finger: -width) == 3) // Social → Profil
    }

    @Test func fingerToTheRightOpensThePreviousTabOnTheLeft() {
        #expect(position(from: 3, finger: width) == 2) // Profil → Social
        #expect(position(from: 2, finger: width) == 1) // Social → Rankings
        #expect(position(from: 1, finger: width) == 0) // Rankings → Home
    }

    // MARK: Zwischenstände, Abbruch, Ränder

    @Test func partialSwipeShowsBothPagesAndCanBeHeld() throws {
        // Home, Finger 40 % nach links: zu 40 % auf dem Weg zu Rankings, beide Seiten sichtbar.
        let held = try #require(position(from: 0, finger: -0.4 * width))
        #expect(abs(held - 0.4) < 0.0001)
        #expect(PaceTabPaging.visibleIndices(held, count: 4) == [0, 1])
        #expect(PaceTabPaging.settledIndex(held) == nil)
        // Weiter ziehen …
        let further = try #require(position(from: 0, finger: -0.75 * width))
        #expect(further > held)
    }

    @Test func pullingBackKeepsTheOriginalTab() throws {
        // Social, Finger erst 30 % nach rechts (Richtung Rankings), dann zurück an den Start.
        let halfway = try #require(position(from: 2, finger: 0.3 * width))
        #expect(abs(halfway - 1.7) < 0.0001)
        let back = try #require(position(from: 2, finger: 0))
        #expect(PaceTabPaging.settledIndex(back) == 2)
    }

    @Test func theEndsDoNotRotate() {
        // Home nach rechts bzw. Profil nach links: Gummiband, kein Sprung ans andere Ende.
        #expect(position(from: 0, finger: width) == 0)
        #expect(position(from: 3, finger: -width) == 3)
        #expect(position(from: 0, finger: 0.2 * width) == 0)
    }

    @Test func positionFollowsTheScrollOffset() {
        #expect(PaceTabPaging.position(offset: 0, pageWidth: 400, count: 4) == 0)
        #expect(PaceTabPaging.position(offset: 600, pageWidth: 400, count: 4) == 1.5)
        #expect(PaceTabPaging.position(offset: 1_200, pageWidth: 400, count: 4) == 3)
        #expect(PaceTabPaging.position(offset: -80, pageWidth: 400, count: 4) == 0)
        #expect(PaceTabPaging.position(offset: 1_350, pageWidth: 400, count: 4) == 3)
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

    // MARK: Startseite

    @Test func initialAnchorPointsAtTheSelectedPage() {
        // Home ganz links, Profil ganz rechts.
        #expect(PaceTabPaging.initialAnchorX(index: 0, count: 4) == 0)
        #expect(PaceTabPaging.initialAnchorX(index: 3, count: 4) == 1)
        #expect(abs(PaceTabPaging.initialAnchorX(index: 2, count: 4) - 2.0 / 3.0) < 0.0001)
        #expect(PaceTabPaging.initialAnchorX(index: 9, count: 4) == 1)
        #expect(PaceTabPaging.initialAnchorX(index: 0, count: 1) == 0)
        // Der Anker trifft genau die Seite: Versatz = Anker × (Seiten − 1) Seitenbreiten – auch für Social und Profil.
        for index in [2, 3] {
            let offset = PaceTabPaging.initialAnchorX(index: index, count: 4) * 3 * 390
            #expect(PaceTabPaging.position(offset: offset, pageWidth: 390, count: 4).map { ($0 * 1000).rounded() / 1000 } == Double(index))
        }
    }
}
