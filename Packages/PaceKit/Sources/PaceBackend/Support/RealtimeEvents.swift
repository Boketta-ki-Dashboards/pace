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
        return AsyncStream { continuation in
            let task = Task {
                await Self.forward(client: client, topic: topic, event: event, to: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Wie `stream(topic:event:)`, das Topic wird aber erst beim Start ermittelt (z. B. die eigene öffentliche ID).
    /// Scheitert das, endet der Stream sofort.
    func stream(event: String, topic: @escaping @Sendable () async throws -> String) -> AsyncStream<Void> {
        let client = client
        return AsyncStream { continuation in
            let task = Task {
                guard let resolved = try? await topic() else {
                    continuation.finish()
                    return
                }
                await Self.forward(client: client, topic: resolved, event: event, to: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func forward(
        client: RealtimeClientV2,
        topic: String,
        event: String,
        to continuation: AsyncStream<Void>.Continuation
    ) async {
        let channel = client.channel(topic) { $0.isPrivate = true }
        // Vor dem Beitritt registrieren, damit kein Hinweis verloren geht.
        let broadcasts = channel.broadcastStream(event: event)

        do {
            try await channel.subscribeWithError()
        } catch {
            await client.removeChannel(channel)
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
        await client.removeChannel(channel)
        continuation.finish()
    }
}

extension BackendConfiguration {
    /// Endpunkt von Supabase Realtime (WebSocket unter `…/realtime/v1/websocket`).
    var realtimeURL: URL { supabaseURL.appendingPathComponent("realtime/v1") }

    /// Endpunkt von Supabase Storage.
    var storageURL: URL { supabaseURL.appendingPathComponent("storage/v1") }
}
