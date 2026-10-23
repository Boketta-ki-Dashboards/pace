import Foundation
@testable import SocialFeature
import Testing

/// Scrollverhalten im Chat: unten angeheftet mitgehen, beim Lesen älterer Nachrichten nur ein Hinweis.
struct ChatScrollTrackerTests {
    /// Sichtbarer Bereich 500 pt, Inhalt 1 200 pt.
    private func trackerAtBottom() -> ChatScrollTracker {
        var tracker = ChatScrollTracker()
        tracker.update(contentBottom: 1_200, contentHeight: 1_200, viewportHeight: 500)
        // Ans Ende gescrollt: Unterkante liegt an der Unterkante des sichtbaren Bereichs.
        tracker.update(contentBottom: 500, contentHeight: 1_200, viewportHeight: 500)
        return tracker
    }

    @Test func firstLoadAndOwnMessagesAlwaysScrollToTheEnd() {
        var tracker = ChatScrollTracker()
        let firstLoadFollows = tracker.newLastEntry(isOwn: false, isFirstEntry: true)
        #expect(firstLoadFollows)
        tracker.update(contentBottom: 500, contentHeight: 1_200, viewportHeight: 500)
        tracker.update(contentBottom: 1_000, contentHeight: 1_200, viewportHeight: 500)
        #expect(!tracker.isPinnedToBottom)
        let ownMessageFollows = tracker.newLastEntry(isOwn: true, isFirstEntry: false)
        #expect(ownMessageFollows)
        #expect(tracker.isPinnedToBottom)
        #expect(!tracker.hasUnseenMessages)
    }

    @Test func atTheBottomNewMessagesFollow() {
        var tracker = trackerAtBottom()
        #expect(tracker.isPinnedToBottom)
        let follows = tracker.newLastEntry(isOwn: false, isFirstEntry: false)
        #expect(follows)
        #expect(!tracker.hasUnseenMessages)
    }

    @Test func readingOlderMessagesShowsAHintInsteadOfJumping() {
        var tracker = trackerAtBottom()
        // Nach oben gescrollt: Unterkante 400 pt unter dem sichtbaren Bereich.
        tracker.update(contentBottom: 900, contentHeight: 1_200, viewportHeight: 500)
        #expect(!tracker.isPinnedToBottom)
        let follows = tracker.newLastEntry(isOwn: false, isFirstEntry: false)
        #expect(!follows)
        #expect(tracker.hasUnseenMessages)
        // Zurück nach unten gescrollt: Hinweis verschwindet.
        tracker.update(contentBottom: 520, contentHeight: 1_200, viewportHeight: 500)
        #expect(tracker.isPinnedToBottom)
        #expect(!tracker.hasUnseenMessages)
    }

    @Test func tappingTheHintPinsAgain() {
        var tracker = trackerAtBottom()
        tracker.update(contentBottom: 900, contentHeight: 1_200, viewportHeight: 500)
        _ = tracker.newLastEntry(isOwn: false, isFirstEntry: false)
        tracker.scrolledToBottom()
        #expect(tracker.isPinnedToBottom)
        #expect(!tracker.hasUnseenMessages)
    }

    @Test func growingContentKeepsThePinnedStateAndAsksToStick() {
        var tracker = trackerAtBottom()
        // Neue Nachricht (60 pt) – die Unterkante rutscht nach unten, das ist kein Hochscrollen.
        let sticks = tracker.update(contentBottom: 560, contentHeight: 1_260, viewportHeight: 500)
        #expect(sticks)
        #expect(tracker.isPinnedToBottom)
    }

    @Test func growingContentWhileReadingDoesNotScroll() {
        var tracker = trackerAtBottom()
        tracker.update(contentBottom: 900, contentHeight: 1_200, viewportHeight: 500)
        let sticks = tracker.update(contentBottom: 960, contentHeight: 1_260, viewportHeight: 500)
        #expect(!sticks)
        #expect(!tracker.isPinnedToBottom)
    }

    @Test func keyboardShrinkingTheViewportKeepsTheEndVisible() {
        var tracker = trackerAtBottom()
        // Tastatur: sichtbarer Bereich 500 → 240 pt; vorher unten → weiter unten bleiben.
        let sticks = tracker.update(contentBottom: 500, contentHeight: 1_200, viewportHeight: 240)
        #expect(sticks)
        #expect(tracker.isPinnedToBottom)
    }

    @Test func tinyMeasurementNoiseCountsAsScrolling() {
        var tracker = trackerAtBottom()
        // 0,2 pt Rundung bei der Inhaltshöhe ändert nichts am Layout.
        let sticks = tracker.update(contentBottom: 800, contentHeight: 1_200.2, viewportHeight: 500)
        #expect(!sticks)
        #expect(!tracker.isPinnedToBottom)
    }
}
