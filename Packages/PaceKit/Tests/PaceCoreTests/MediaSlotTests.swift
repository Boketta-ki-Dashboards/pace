import Foundation
import PaceCore
import Testing

/// Welches Bild eine wiederverwendete Ansicht zeigt (Auftrag 6, Profil- und Gruppenbilder): nie ein fremdes, nie ein
/// verspätet geladenes, kein endloses Laden nach einem Fehler.
struct MediaSlotTests {
    private let mia = MediaReference(bucket: .avatars, path: "mia/1.jpg")
    private let leon = MediaReference(bucket: .avatars, path: "leon/1.jpg")
    private let miaNew = MediaReference(bucket: .avatars, path: "mia/2.jpg")
    private let group = MediaReference(bucket: .groupImages, path: "g/1.jpg")

    @Test func firstLoadShowsPlaceholderThenImage() {
        var slot = MediaSlot<String>()
        #expect(isEmpty(slot.phase))
        slot.show(mia)
        #expect(isLoading(slot.phase))
        #expect(slot.value == nil)
        let accepted1 = slot.deliver("Mia", for: mia)
        #expect(accepted1)
        #expect(slot.value == "Mia")
    }

    @Test func switchingPeopleNeverShowsThePreviousImage() {
        var slot = MediaSlot<String>()
        slot.show(mia)
        slot.deliver("Mia", for: mia)
        // Schneller Wechsel zu Leon (z. B. wiederverwendete Zeile im Freunde-Ranking): sofort kein Foto von Mia mehr.
        slot.show(leon)
        #expect(slot.value == nil)
        #expect(isLoading(slot.phase))
        // Mias Download kommt verspätet an: wird verworfen.
        let accepted2 = slot.deliver("Mia (spät)", for: mia)
        #expect(!accepted2)
        #expect(slot.value == nil)
        slot.deliver("Leon", for: leon)
        #expect(slot.value == "Leon")
        // Und noch einmal zurück: wieder neu laden, nicht Leons Bild zeigen.
        slot.show(mia)
        #expect(slot.value == nil)
    }

    @Test func changedAndRemovedPicture() {
        var slot = MediaSlot<String>()
        slot.show(mia)
        slot.deliver("Mia alt", for: mia)
        // Neues Profilbild: neuer Verweis (Dateinamen sind je Upload eindeutig) – das alte verschwindet sofort.
        slot.show(miaNew)
        #expect(slot.value == nil)
        slot.deliver("Mia neu", for: miaNew)
        #expect(slot.value == "Mia neu")
        // Bild entfernt: Initialen.
        slot.show(nil)
        #expect(isEmpty(slot.phase))
        #expect(slot.value == nil)
        // Ein noch laufender Download des entfernten Bilds ändert nichts.
        let accepted3 = slot.deliver("Mia neu (spät)", for: miaNew)
        #expect(!accepted3)
        #expect(isEmpty(slot.phase))
    }

    @Test func failureShowsPlaceholderAndCanBeRetried() {
        var slot = MediaSlot<String>()
        slot.show(group)
        slot.deliver(nil, for: group)
        #expect(slot.isFailed)
        #expect(slot.value == nil)
        // Ein Fehlschlag gilt nur für diesen Verweis.
        slot.show(leon)
        #expect(!slot.isFailed)
        slot.show(group)
        #expect(isLoading(slot.phase))
        slot.deliver(nil, for: group)
        slot.retry()
        #expect(isLoading(slot.phase))
        slot.deliver("Gruppe", for: group)
        #expect(slot.value == "Gruppe")
        // Wiederholen ohne Fehlschlag verwirft kein geladenes Bild.
        slot.retry()
        #expect(slot.value == "Gruppe")
    }

    @Test func sameReferenceKeepsItsImage() {
        var slot = MediaSlot<String>()
        slot.show(mia)
        slot.deliver("Mia", for: mia)
        slot.show(mia)
        #expect(slot.value == "Mia")
    }

    private func isEmpty(_ phase: MediaSlot<String>.Phase) -> Bool {
        if case .empty = phase { return true }
        return false
    }

    private func isLoading(_ phase: MediaSlot<String>.Phase) -> Bool {
        if case .loading = phase { return true }
        return false
    }
}
