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

    @Test func removalRunsOnlyForTheLastStream() async {
        let usage = TopicUsage()
        let log = EventLog()
        await usage.acquire("chat:e")
        await usage.acquire("chat:e")

        await usage.release("chat:e") { await log.append("removed") }
        #expect(await log.entries.isEmpty)
        await usage.release("chat:e") { await log.append("removed") }
        #expect(await log.entries == ["removed"])
    }

    /// Ein neuer Stream darf den Kanal nicht übernehmen, während der letzte Stream ihn noch entfernt.
    @Test(.timeLimit(.minutes(1)))
    func newStreamWaitsUntilTheChannelIsRemoved() async {
        let usage = TopicUsage()
        let log = EventLog()
        let (gate, openGate) = AsyncStream<Void>.makeStream()
        await usage.acquire("chat:d")

        let releasing = Task {
            await usage.release("chat:d") {
                await log.append("removing")
                var iterator = gate.makeAsyncIterator()
                _ = await iterator.next()
                await log.append("removed")
            }
        }
        while await log.entries.isEmpty {
            await Task.yield()
        }

        let acquiring = Task {
            await usage.acquire("chat:d")
            await log.append("acquired")
        }
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(await log.entries == ["removing"])

        openGate.yield()
        openGate.finish()
        #expect(await releasing.value)
        await acquiring.value
        #expect(await log.entries == ["removing", "removed", "acquired"])
        #expect(await usage.release("chat:d"))
    }
}

private actor EventLog {
    private(set) var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }
}
