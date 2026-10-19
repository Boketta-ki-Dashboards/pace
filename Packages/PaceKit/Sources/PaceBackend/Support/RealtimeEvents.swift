import Foundation
import Realtime

/// Echtzeit-Hinweise über private Broadcast-Kanäle von Supabase Realtime (Migration 20261019100200/100300).
///
/// Der Server sendet nach jeder neuen oder gelöschten Nachricht ein Ereignis ohne Inhalt an `chat:<conversation_id>`
/// und `user:<public_id>`; wer ein Topic empfangen darf, prüft eine Policy auf `realtime.messages` mit dem Access
/// Token. Jeder Hinweis wird als `Void` weitergegeben – die App lädt dann über die RPCs.
///
/// Der Stream endet, sobald Realtime nicht erreichbar ist, der Beitritt abgelehnt wird oder der Kanal getrennt
/// wird. Die App fällt dann auf regelmäßiges Aktualisieren zurück (Vertrag von `ChatRepository`).
struct RealtimeEvents: Sendable {
    let client: RealtimeClientV2
    /// Der Realtime-Client teilt Kanäle je Topic (z. B. `user:<public_id>` für Chat-Liste und Ungelesen-Zähler).
    /// Entfernt wird ein Kanal erst, wenn der letzte Stream dieses Topics endet.
    let usage = TopicUsage()

    init(configuration: BackendConfiguration, tokens: AccessTokenProvider) {
        client = RealtimeClientV2(
            url: configuration.realtimeURL,
            options: RealtimeClientOptions(
                headers: ["apikey": configuration.publishableKey],
                // Nicht lange wiederholen: Ist Realtime nicht erreichbar, soll der Stream rasch enden.
                timeoutInterval: 10,
                maxRetryAttempts: 1,
                accessToken: { try await tokens.accessToken() }
            )
        )
    }

    /// Ereignisse `event` auf dem privaten Topic. Endet bei Abbruch der Verbindung oder wenn der Verbraucher den
    /// Stream nicht mehr liest.
    func stream(topic: String, event: String) -> AsyncStream<Void> {
        let client = client
        let usage = usage
        return AsyncStream { continuation in
            let task = Task {
                await Self.forward(client: client, usage: usage, topic: topic, event: event, to: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Wie `stream(topic:event:)`, das Topic wird aber erst beim Start ermittelt (z. B. die eigene öffentliche ID).
    /// Scheitert das, endet der Stream sofort.
    func stream(event: String, topic: @escaping @Sendable () async throws -> String) -> AsyncStream<Void> {
        let client = client
        let usage = usage
        return AsyncStream { continuation in
            let task = Task {
                guard let resolved = try? await topic() else {
                    continuation.finish()
                    return
                }
                await Self.forward(client: client, usage: usage, topic: resolved, event: event, to: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func forward(
        client: RealtimeClientV2,
        usage: TopicUsage,
        topic: String,
        event: String,
        to continuation: AsyncStream<Void>.Continuation
    ) async {
        await usage.acquire(topic)
        let channel = client.channel(topic) { $0.isPrivate = true }
        // Vor dem Beitritt registrieren, damit kein Hinweis verloren geht.
        let broadcasts = channel.broadcastStream(event: event)

        do {
            try await channel.subscribeWithError()
        } catch {
            await release(channel, topic: topic, client: client, usage: usage)
            continuation.finish()
            return
        }

        // Endet der Kanal (Trennung, Ablehnung), endet auch der Stream. Erst nach dem Beitritt abonnieren: Der Stream
        // liefert sofort den aktuellen Status, vorher also `.unsubscribed`.
        let statuses = channel.statusChange
        let watcher = Task {
            for await status in statuses where status == .unsubscribed {
                continuation.finish()
                return
            }
            continuation.finish()
        }

        for await _ in broadcasts {
            if Task.isCancelled { break }
            continuation.yield(())
        }

        watcher.cancel()
        await release(channel, topic: topic, client: client, usage: usage)
        continuation.finish()
    }

    private static func release(_ channel: RealtimeChannelV2, topic: String, client: RealtimeClientV2, usage: TopicUsage) async {
        await usage.release(topic) {
            await client.removeChannel(channel)
        }
    }
}

/// Wie viele Streams ein Topic gerade nutzen – und ob sein Kanal gerade entfernt wird.
///
/// Der Realtime-Client liefert für ein Topic denselben Kanal, bis `removeChannel` ihn nach dem Abmelden aus seiner
/// Liste nimmt. Ein Stream, der in dieser Zeit beginnt, bekäme sonst genau diesen Kanal: Er wäre danach zwar
/// angemeldet, aber nicht mehr im Client eingetragen, erhielte nie wieder Hinweise und endete auch nicht (kein
/// Rückfall auf regelmäßiges Aktualisieren). Deshalb wartet `acquire`, bis das Entfernen abgeschlossen ist.
actor TopicUsage {
    private var counts: [String: Int] = [:]
    private var removals: [String: Task<Void, Never>] = [:]

    /// Zählt eine Nutzung, sobald kein Entfernen des Kanals dieses Topics mehr läuft.
    func acquire(_ topic: String) async {
        while let removal = removals[topic] {
            await removal.value
            if removals[topic] == removal {
                removals[topic] = nil
            }
        }
        counts[topic, default: 0] += 1
    }

    /// Gibt eine Nutzung frei. War es die letzte, läuft `remove` (Kanal entfernen); neue Nutzungen warten darauf.
    /// - Returns: `true`, wenn das Topic danach von niemandem mehr genutzt wird.
    @discardableResult
    func release(_ topic: String, remove: @escaping @Sendable () async -> Void = {}) async -> Bool {
        let remaining = (counts[topic] ?? 1) - 1
        guard remaining <= 0 else {
            counts[topic] = remaining
            return false
        }
        counts[topic] = nil
        let removal = Task { await remove() }
        removals[topic] = removal
        await removal.value
        if removals[topic] == removal {
            removals[topic] = nil
        }
        return true
    }
}

extension BackendConfiguration {
    /// Endpunkt von Supabase Realtime (WebSocket unter `…/realtime/v1/websocket`).
    var realtimeURL: URL { supabaseURL.appendingPathComponent("realtime/v1") }

    /// Endpunkt von Supabase Storage.
    var storageURL: URL { supabaseURL.appendingPathComponent("storage/v1") }
}
