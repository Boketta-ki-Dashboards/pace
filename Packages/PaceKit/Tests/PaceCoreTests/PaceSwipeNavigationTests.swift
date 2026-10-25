import Foundation
import PaceCore
import Testing

/// Wischen durch Tage, Wochen und Monate (Statistik, Kalender, Flammenkalender): Finger nach rechts = vorheriger,
/// Finger nach links = nächster Zeitraum; senkrechtes Scrollen und zurückgezogene Gesten wechseln nichts.
struct PaceSwipeNavigationTests {
    private func step(
        _ width: CGFloat,
        height: CGFloat = 0,
        predicted: CGFloat? = nil,
        canShowPrevious: Bool = true,
        canShowNext: Bool = true
    ) -> PaceSwipeStep? {
        PaceSwipeNavigation.step(
            translation: CGSize(width: width, height: height),
            predictedEndTranslation: CGSize(width: predicted ?? width, height: height),
            canShowPrevious: canShowPrevious,
            canShowNext: canShowNext
        )
    }

    @Test func fingerToTheRightShowsThePreviousPeriod() {
        #expect(step(120) == .previous)
    }

    @Test func fingerToTheLeftShowsTheNextPeriod() {
        #expect(step(-120) == .next)
    }

    @Test func shortMovementsDoNotSwitch() {
        #expect(step(40) == nil)
        #expect(step(-40) == nil)
    }

    @Test func aQuickFlickSwitchesEvenIfShort() {
        #expect(step(40, predicted: 220) == .previous)
        #expect(step(-40, predicted: -220) == .next)
    }

    @Test func pullingBackCancelsTheSwitch() {
        // Weit nach rechts gezogen, dann schnell zurück nach links: kein Wechsel.
        #expect(step(90, predicted: -60) == nil)
        #expect(step(-90, predicted: 60) == nil)
    }

    @Test func verticalScrollingNeverSwitches() {
        #expect(step(80, height: 200) == nil)
        #expect(step(-80, height: -90) == nil)
        #expect(!PaceSwipeNavigation.isHorizontal(CGSize(width: 30, height: 40)))
        #expect(PaceSwipeNavigation.isHorizontal(CGSize(width: 90, height: 20)))
    }

    @Test func thereIsNothingAfterTodayOrBeforeTheFirstData() {
        #expect(step(-200, canShowNext: false) == nil)
        #expect(step(200, canShowPrevious: false) == nil)
        // Die andere Richtung bleibt möglich.
        #expect(step(200, canShowNext: false) == .previous)
        #expect(step(-200, canShowPrevious: false) == .next)
    }

    @Test func contentFollowsTheFingerWithResistanceAtTheEnd() {
        let free = PaceSwipeNavigation.dragOffset(translation: CGSize(width: 80, height: 0), canShowPrevious: true, canShowNext: true)
        let blocked = PaceSwipeNavigation.dragOffset(translation: CGSize(width: -80, height: 0), canShowPrevious: true, canShowNext: false)
        #expect(free > 0) // folgt dem Finger nach rechts
        #expect(blocked < 0 && abs(blocked) < abs(free)) // nach links nur gegen Widerstand
        let far = PaceSwipeNavigation.dragOffset(translation: CGSize(width: 2000, height: 0), canShowPrevious: true, canShowNext: true)
        #expect(far == PaceSwipeNavigation.maximumOffset)
        #expect(PaceSwipeNavigation.dragOffset(translation: CGSize(width: 20, height: 80), canShowPrevious: true, canShowNext: true) == 0)
    }

    @Test func theNewPeriodSlidesInFromTheMatchingSide() {
        // Vorheriger Zeitraum kommt von links, der nächste von rechts – wie beim Blättern.
        #expect(PaceSwipeNavigation.entryOffset(for: .previous) < 0)
        #expect(PaceSwipeNavigation.entryOffset(for: .next) > 0)
    }
}
