import Foundation

/// Wer die gemeinsame Audio-Sitzung gerade hält. Aufnahme und Wiedergabe teilen sich eine Sitzung (`AVAudioSession`);
/// nur wer sie aktiviert hat, gibt sie wieder ab.
///
/// Hintergrund (P0 Auftrag 4, Sprachnachricht brach nach etwa einer Sekunde ab): Beim Start einer Aufnahme wurde die
/// Wiedergabe gesperrt und dabei gestoppt – und das Stoppen deaktivierte die gemeinsame Sitzung. Eine deaktivierte
/// Sitzung beendet laufende Aufnahmen; der Rekorder meldete daraufhin „zu kurz“ bzw. die Zeit blieb stehen.
struct ChatAudioSessionOwnership: Equatable {
    enum Owner: Equatable {
        case recorder
        case player
    }

    private(set) var owner: Owner?

    /// Übernimmt die Sitzung (z. B. die Aufnahme nach einer Wiedergabe).
    mutating func take(_ owner: Owner) {
        self.owner = owner
    }

    /// Gibt die Sitzung ab. `true` nur, wenn `owner` sie wirklich hielt – erst dann darf sie deaktiviert werden.
    mutating func release(_ owner: Owner) -> Bool {
        guard self.owner == owner else { return false }
        self.owner = nil
        return true
    }
}
