import Foundation
import Observation
import PaceCore

/// Formular „Gruppe erstellen“ (Referenzbild 3): Bild, Name, Beschreibung, Gruppentyp, Privatsphäre, eingeladene
/// Freunde und Tagesziel pro Mitglied.
///
/// Geprüft wird wie auf dem Server (Name 3–40 Zeichen, Beschreibung höchstens 200, Ziel 1.000–100.000). Angelegt wird
/// die Gruppe über ``SocialViewModel/createGroup(_:image:)`` – erst danach wird das Bild hochgeladen. Fehler stehen im
/// gemeinsamen Hinweis (`social.notice`).
@MainActor
@Observable
public final class CreateGroupViewModel {
    public var name = ""
    public var description = ""
    public var kind: GroupKind = .friends
    public var privacy: GroupPrivacy = .inviteOnly
    public private(set) var dailyGoal = GroupGoalRules.defaultGoal
    /// Ausgewählte Freunde in der Reihenfolge der Auswahl.
    public private(set) var inviteeIDs: [UUID] = []
    /// Ausgewähltes, bereits verkleinertes Bild.
    public private(set) var image: SocialViewModel.GroupImageUpload?
    public private(set) var imageError: String?
    public private(set) var isCreating = false
    /// Nach dem ersten Absenden zeigt das Formular alle Eingabefehler.
    public private(set) var attemptedSubmit = false

    @ObservationIgnored private weak var social: SocialViewModel?

    public init(social: SocialViewModel?) {
        self.social = social
    }

    // MARK: Mitglieder

    /// Freunde, die eingeladen werden können (alphabetisch).
    public var friends: [Friend] {
        (social?.friends ?? []).sorted {
            $0.profile.displayName.localizedStandardCompare($1.profile.displayName) == .orderedAscending
        }
    }

    public var invitees: [SocialProfile] {
        let byID = Dictionary((social?.friends ?? []).map { ($0.profile.publicID, $0.profile) }, uniquingKeysWith: { first, _ in first })
        return inviteeIDs.compactMap { byID[$0] }
    }

    public func isInvited(_ publicID: UUID) -> Bool {
        inviteeIDs.contains(publicID)
    }

    public func toggleInvitee(_ publicID: UUID) {
        if let index = inviteeIDs.firstIndex(of: publicID) {
            inviteeIDs.remove(at: index)
        } else {
            inviteeIDs.append(publicID)
        }
    }

    // MARK: Tagesziel

    public func setGoal(_ goal: Int) {
        dailyGoal = GroupGoalRules.clamped(goal)
    }

    public func increaseGoal() {
        setGoal(dailyGoal + GroupGoalRules.increment)
    }

    public func decreaseGoal() {
        setGoal(dailyGoal - GroupGoalRules.increment)
    }

    public var canIncreaseGoal: Bool { dailyGoal < GroupGoalRules.range.upperBound }
    public var canDecreaseGoal: Bool { dailyGoal > GroupGoalRules.range.lowerBound }

    // MARK: Bild

    /// Ohne Bildspeicher (kein Backend) kann kein Gruppenbild gewählt werden.
    public var canPickImage: Bool {
        social?.media != nil
    }

    /// Übernimmt ein verkleinertes Bild. `false`, wenn es trotz Verkleinerung zu groß oder kein erlaubtes Format ist.
    @discardableResult
    public func setImage(_ upload: SocialViewModel.GroupImageUpload) -> Bool {
        guard MediaRules.allowedContentTypes.contains(upload.contentType) else {
            imageError = SocialText.imageNotLoaded
            return false
        }
        guard upload.data.count <= SocialViewModel.groupImageMaximumBytes else {
            imageError = SocialText.imageTooLarge
            return false
        }
        image = upload
        imageError = nil
        return true
    }

    /// Das ausgewählte Foto ließ sich nicht laden oder umwandeln.
    public func imageFailed() {
        imageError = SocialText.imageNotLoaded
    }

    public func removeImage() {
        image = nil
        imageError = nil
    }

    // MARK: Prüfen und Anlegen

    public var nameError: String? {
        guard attemptedSubmit || !name.isEmpty else { return nil }
        return GroupDraft(name: name).validName == nil ? SocialError.invalidName.message : nil
    }

    public var descriptionError: String? {
        GroupDraft(description: description).validDescription == nil ? SocialError.invalidDescription.message : nil
    }

    public var remainingDescriptionCharacters: Int {
        GroupDraft.descriptionLength.upperBound - description.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    public var isValid: Bool {
        let draft = self.draft
        return draft.validName != nil && draft.validDescription != nil && GroupGoalRules.range.contains(dailyGoal)
    }

    public var canSubmit: Bool {
        !isCreating && social?.isAvailable == true
    }

    var draft: GroupDraft {
        GroupDraft(name: name, description: description, kind: kind, dailyGoal: dailyGoal, privacy: privacy, inviteePublicIDs: inviteeIDs)
    }

    /// Legt die Gruppe an. Gibt sie zurück (die Ansicht öffnet dann die Details) oder `nil` bei Fehlern.
    public func create() async -> GroupSummary? {
        attemptedSubmit = true
        guard let social, !isCreating else { return nil }
        guard isValid else {
            // Gleiche Meldung wie der Server – das Formular markiert zusätzlich das Feld.
            if draft.validName == nil {
                social.show(SocialViewModel.Notice(text: SocialError.invalidName.message, isError: true))
            } else if draft.validDescription == nil {
                social.show(SocialViewModel.Notice(text: SocialError.invalidDescription.message, isError: true))
            } else {
                social.show(SocialViewModel.Notice(text: SocialError.invalidGoal.message, isError: true))
            }
            return nil
        }
        isCreating = true
        defer { isCreating = false }
        return await social.createGroup(draft, image: image)
    }
}
