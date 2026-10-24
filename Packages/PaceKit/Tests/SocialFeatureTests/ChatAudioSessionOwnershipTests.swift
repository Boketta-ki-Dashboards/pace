@testable import SocialFeature
import Testing

/// Gemeinsame Audio-Sitzung: Nur wer sie hält, gibt sie ab (P0 Auftrag 4 – Aufnahme brach nach etwa einer Sekunde ab,
/// weil das Sperren der Wiedergabe die Sitzung der laufenden Aufnahme deaktivierte).
struct ChatAudioSessionOwnershipTests {

    @Test func stoppingPlaybackDoesNotEndARecording() {
        var session = ChatAudioSessionOwnership()
        // Mikrofon gedrückt: Wiedergabe wird gestoppt (hält nichts), Aufnahme übernimmt.
        let released1 = session.release(.player)
        #expect(!released1)
        session.take(.recorder)
        // Aufnahme läuft, die Wiedergabe wird gesperrt und dabei gestoppt: Sitzung bleibt aktiv.
        let released2 = session.release(.player)
        #expect(!released2)
        #expect(session.owner == .recorder)
        // Aufnahme beendet: jetzt wird sie frei.
        let released3 = session.release(.recorder)
        #expect(released3)
        #expect(session.owner == nil)
    }

    @Test func previewPlaybackIsNotCutByDiscardingTheRecorder() {
        var session = ChatAudioSessionOwnership()
        session.take(.recorder)
        let released4 = session.release(.recorder)
        #expect(released4) // Vorschau fertig aufgenommen
        session.take(.player)                // Vorschau anhören
        // Aufräumen des Rekorders (z. B. beim Senden) beendet die Wiedergabe nicht über die Sitzung.
        let released5 = session.release(.recorder)
        #expect(!released5)
        #expect(session.owner == .player)
        let released6 = session.release(.player)
        #expect(released6)
    }

    @Test func recordingTakesOverFromPlayback() {
        var session = ChatAudioSessionOwnership()
        session.take(.player)
        session.take(.recorder)
        let released7 = session.release(.player)
        #expect(!released7)
        #expect(session.owner == .recorder)
    }
}
