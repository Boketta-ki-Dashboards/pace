import Foundation
@testable import PaceBackend
import Testing

/// Kanäle werden je Topic geteilt (Chat-Liste und Ungelesen-Zähler hören beide auf `user:<public_id>`); erst der letzte
/// Stream eines Topics darf den Kanal entfernen.
struct RealtimeEventsTests {
    @Test func channelIsReleasedOnlyByTheLastStreamOfATopic() async {
        let usage = TopicUsage()
        await usage.acquire("user:a")
        await usage.acquire("user:a")
        await usage.acquire("chat:b")

        #expect(await !usage.release("user:a"))
        #expect(await usage.release("user:a"))
        #expect(await usage.release("chat:b"))
    }

    @Test func topicCanBeUsedAgainAfterRelease() async {
        let usage = TopicUsage()
        await usage.acquire("chat:c")
        #expect(await usage.release("chat:c"))
        await usage.acquire("chat:c")
        #expect(await usage.release("chat:c"))
        // Überzählige Freigaben richten keinen Schaden an.
        #expect(await usage.release("chat:c"))
    }
}
