import Foundation
import Observation
import PaceCore

/// Social-Profil 2.0 (Auftrag 6): eigene Bio, Interessen, Banner und freiwillige Auszeichnungen – anzeigen und unter
/// „Profil bearbeiten“ ändern.
///
/// - Alles ist freiwillig; ohne Angaben sieht das Profil aus wie bisher.
/// - Kennt der Server die Angaben noch nicht (Migration 20261030100000 fehlt), ist ``isAvailable`` `false`: Das Profil
///   zeigt dann nur die bisherigen Angaben, „Profil bearbeiten“ erklärt, dass die Funktion noch kommt.
/// - Auszeichnungen ermittelt die App aus ihrem vorhandenen Serien- und Bestwert-Modell (``earnedAchievements``) und
///   veröffentlicht sie nur, wenn die Person das einschaltet – ohne genaue Schrittzahlen.
@MainActor
@Observable
public final class ProfileDetailsViewModel {
    public enum Availability: Equatable {
        case unknown
        case available
        /// Server ohne Profilangaben (Migration fehlt) oder nicht angebunden.
        case unavailable
        case failed(String)
    }

    public enum BannerActivity: Equatable {
        case idle
        case uploading
        case removing
    }

    public private(set) var details: ProfileDetails = .empty
    public private(set) var availability: Availability = .unknown
    public private(set) var isSaving = false
    public private(set) var bannerActivity: BannerActivity = .idle
    public private(set) var errorMessage: String?

    // Entwurf beim Bearbeiten
    public var draftBio = ""
    public private(set) var draftInterests: [ProfileInterest] = []
    public var draftShowsAchievements = false

    @ObservationIgnored private let repository: (any ProfileDetailsRepository)?
    @ObservationIgnored private let media: (any MediaRepository)?
    @ObservationIgnored private let earnedAchievements: @MainActor () -> [ProfileAchievement]

    /// - Parameter earnedAchievements: Erreichte Auszeichnungen aus dem vorhandenen Serien- und Bestwert-Modell.
    public init(
        repository: (any ProfileDetailsRepository)?,
        media: (any MediaRepository)?,
        earnedAchievements: @escaping @MainActor () -> [ProfileAchievement] = { [] }
    ) {
        self.repository = repository
        self.media = media
        self.earnedAchievements = earnedAchievements
    }

    public var isAvailable: Bool {
        availability == .available
    }

    /// Ob das Profil etwas Neues zu zeigen hat (Bio, Interessen, Banner, sichtbare Auszeichnungen).
    public var hasContent: Bool {
        details.bio != nil || !details.interests.isEmpty || details.bannerPath != nil || !details.visibleAchievements.isEmpty
    }

    /// Auszeichnungen, die beim Einschalten veröffentlicht würden.
    public var earned: [ProfileAchievement] {
        earnedAchievements()
    }

    public func load() async {
        guard let repository else {
            availability = .unavailable
            return
        }
        do {
            details = try await repository.ownDetails()
            availability = .available
        } catch ProfileDetailsError.unavailable {
            availability = .unavailable
        } catch is CancellationError {
            return
        } catch {
            if availability != .available { availability = .failed(Self.message(for: error)) }
        }
    }

    // MARK: Bearbeiten

    /// Entwurf aus den gespeicherten Angaben.
    public func beginEditing() {
        draftBio = details.bio ?? ""
        draftInterests = details.interests
        draftShowsAchievements = details.showsAchievements
        errorMessage = nil
    }

    /// Zeichen der Bio wie auf dem Server gezählt (nach dem Normalisieren).
    public var bioLength: Int {
        ProfileBioRules.length(ProfileBioRules.normalized(draftBio) ?? "")
    }

    public var bioProblem: ProfileBioRules.Problem? {
        ProfileBioRules.normalized(draftBio).flatMap(ProfileBioRules.problem)
    }

    public var hasChanges: Bool {
        ProfileBioRules.normalized(draftBio) != details.bio
            || draftInterests != details.interests
            || draftShowsAchievements != details.showsAchievements
            || (draftShowsAchievements && earnedAchievements() != details.achievements)
    }

    public var canSave: Bool {
        isAvailable && bioProblem == nil && hasChanges && !isSaving
    }

    public func isSelected(_ interest: ProfileInterest) -> Bool {
        draftInterests.contains(interest)
    }

    /// Wählt ein Interesse aus oder ab (höchstens fünf).
    public func toggleInterest(_ interest: ProfileInterest) {
        if let index = draftInterests.firstIndex(of: interest) {
            draftInterests.remove(at: index)
        } else if draftInterests.count < ProfileInterest.maximumCount {
            draftInterests.append(interest)
        }
    }

    public var canAddInterest: Bool {
        draftInterests.count < ProfileInterest.maximumCount
    }

    public func removeBio() {
        draftBio = ""
    }

    /// Speichert Bio, Interessen und die Auszeichnungen (eingeschaltet: aktuell erreichte, ausgeschaltet: keine).
    /// - Returns: `true` bei Erfolg.
    @discardableResult
    public func save() async -> Bool {
        guard let repository, canSave else { return false }
        if let problem = bioProblem {
            errorMessage = ProfileBioRules.message(for: problem)
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        var updated = details
        updated.bio = ProfileBioRules.normalized(draftBio)
        updated.interests = draftInterests
        updated.showsAchievements = draftShowsAchievements
        updated.achievements = draftShowsAchievements ? earnedAchievements() : []
        do {
            details = try await repository.saveOwnDetails(updated)
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// Bei eingeschalteten Auszeichnungen: neu erreichte nachtragen (z. B. eine längere Serie), ohne Rückfrage.
    public func refreshPublishedAchievements() async {
        guard let repository, isAvailable, details.showsAchievements, !isSaving else { return }
        let earned = earnedAchievements()
        guard earned != details.achievements else { return }
        var updated = details
        updated.achievements = earned
        if let saved = try? await repository.saveOwnDetails(updated) {
            details = saved
        }
    }

    // MARK: Banner

    /// Lädt ein bereits zugeschnittenes JPEG als Banner hoch (Bucket `avatars`, eigener Ordner), speichert es und
    /// löscht danach das alte Banner.
    @discardableResult
    public func uploadBanner(jpegData: Data) async -> MediaReference? {
        guard let repository, let media, isAvailable, bannerActivity == .idle else { return nil }
        guard jpegData.count <= MediaRules.maximumBytes(for: .avatar) else {
            errorMessage = Self.message(for: MediaError.tooLarge)
            return nil
        }
        bannerActivity = .uploading
        errorMessage = nil
        defer { bannerActivity = .idle }

        let previous = details.banner
        let uploaded: MediaReference
        do {
            uploaded = try await media.upload(jpegData, contentType: "image/jpeg", to: .avatar)
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
        var updated = details
        updated.bannerPath = uploaded.path
        do {
            details = try await repository.saveOwnDetails(updated)
        } catch {
            // Das neue Bild wird nicht verwendet – nicht als verwaiste Datei liegen lassen.
            try? await media.delete(uploaded)
            errorMessage = Self.message(for: error)
            return nil
        }
        if let previous, previous != uploaded {
            try? await media.delete(previous)
        }
        return uploaded
    }

    /// Entfernt das Banner (danach erscheint der neutrale Pace-Hintergrund) und löscht die Datei.
    public func removeBanner() async {
        guard let repository, let previous = details.banner, bannerActivity == .idle else { return }
        bannerActivity = .removing
        errorMessage = nil
        defer { bannerActivity = .idle }
        var updated = details
        updated.bannerPath = nil
        do {
            details = try await repository.saveOwnDetails(updated)
        } catch {
            errorMessage = Self.message(for: error)
            return
        }
        try? await media?.delete(previous)
    }

    public func reportUnreadablePhoto() {
        errorMessage = PaceLocalization.text(
            de: "Das Foto konnte nicht gelesen werden. Bitte wähle ein anderes.",
            en: "The photo couldn't be read. Please choose a different one.",
            ru: "Не удалось прочитать фото. Пожалуйста, выбери другое."
        )
    }

    static func message(for error: Error) -> String {
        if let error = error as? MediaError, error == .tooLarge {
            return PaceLocalization.text(
                de: "Das Bild ist zu groß. Erlaubt sind höchstens 5 MB.",
                en: "The image is too large. The maximum is 5 MB.",
                ru: "Изображение слишком большое. Максимум 5 МБ."
            )
        }
        switch error as? ProfileDetailsError {
        case .unavailable:
            return ProfileDetailsTexts.unavailable
        case .invalid:
            return PaceLocalization.text(
                de: "Das konnte nicht gespeichert werden. Bitte prüfe Bio und Auswahl.",
                en: "This couldn't be saved. Please check your bio and selection.",
                ru: "Не удалось сохранить. Проверь описание и выбор."
            )
        case .network:
            return PaceLocalization.text(
                de: "Keine Verbindung. Bitte versuche es gleich noch einmal.",
                en: "No connection. Please try again in a moment.",
                ru: "Нет соединения. Попробуй ещё раз чуть позже."
            )
        case .rateLimited:
            return PaceLocalization.text(
                de: "Zu viele Änderungen in kurzer Zeit. Bitte warte einen Moment.",
                en: "Too many changes in a short time. Please wait a moment.",
                ru: "Слишком много изменений за короткое время. Подожди немного."
            )
        default:
            return PaceLocalization.text(
                de: "Das hat nicht geklappt. Bitte versuche es noch einmal.",
                en: "That didn't work. Please try again.",
                ru: "Не получилось. Попробуй ещё раз."
            )
        }
    }
}

/// Texte rund um die Profilangaben.
public enum ProfileDetailsTexts {
    public static var editProfile: String {
        PaceLocalization.text(de: "Profil bearbeiten", en: "Edit profile", ru: "Редактировать профиль")
    }

    public static var bio: String {
        PaceLocalization.text(de: "Bio", en: "Bio", ru: "О себе")
    }

    public static var addBio: String {
        PaceLocalization.text(de: "Bio hinzufügen", en: "Add a bio", ru: "Добавить описание")
    }

    public static var bioPlaceholder: String {
        PaceLocalization.text(
            de: "z. B. „Jeden Tag ein bisschen aktiver.“",
            en: "e.g. “A little more active every day.”",
            ru: "например, «Каждый день чуть активнее»"
        )
    }

    public static var removeBio: String {
        PaceLocalization.text(de: "Bio entfernen", en: "Remove bio", ru: "Удалить описание")
    }

    public static var interests: String {
        PaceLocalization.text(de: "Interessen", en: "Interests", ru: "Интересы")
    }

    public static func interestsHint(selected: Int) -> String {
        PaceLocalization.text(
            de: "\(selected) von \(ProfileInterest.maximumCount) ausgewählt",
            en: "\(selected) of \(ProfileInterest.maximumCount) selected",
            ru: "Выбрано \(selected) из \(ProfileInterest.maximumCount)"
        )
    }

    public static var banner: String {
        PaceLocalization.text(de: "Profilbanner", en: "Profile banner", ru: "Обложка профиля")
    }

    public static var addBanner: String {
        PaceLocalization.text(de: "Banner hinzufügen", en: "Add banner", ru: "Добавить обложку")
    }

    public static var changeBanner: String {
        PaceLocalization.text(de: "Banner ändern", en: "Change banner", ru: "Изменить обложку")
    }

    public static var removeBanner: String {
        PaceLocalization.text(de: "Banner entfernen", en: "Remove banner", ru: "Удалить обложку")
    }

    public static var achievements: String {
        PaceLocalization.text(de: "Auszeichnungen", en: "Achievements", ru: "Награды")
    }

    public static var showAchievements: String {
        PaceLocalization.text(de: "Auszeichnungen auf meinem Profil zeigen", en: "Show achievements on my profile", ru: "Показывать награды в профиле")
    }

    public static var achievementsNote: String {
        PaceLocalization.text(
            de: "Freiwillig und standardmäßig aus. Andere sehen nur die Stufen (z. B. „30 Tage in Folge“), nie deine genauen Schritte. Ermittelt aus deiner Serie und deinem besten Tag.",
            en: "Optional and off by default. Others only see the levels (e.g. “30 days in a row”), never your exact steps. Based on your streak and your best day.",
            ru: "По желанию, по умолчанию выключено. Другие видят только уровни (например, «30 дней подряд»), но не точное число шагов. Основано на твоей серии и лучшем дне."
        )
    }

    public static var noAchievementsYet: String {
        PaceLocalization.text(
            de: "Noch keine Auszeichnung – z. B. ab 7 Tagen in Folge.",
            en: "No achievement yet – e.g. from 7 days in a row.",
            ru: "Пока нет наград – например, с 7 дней подряд."
        )
    }

    public static var unavailable: String {
        PaceLocalization.text(
            de: "Bio, Interessen und Banner sind auf dem Server noch nicht eingerichtet. Dein Profil funktioniert wie bisher.",
            en: "Bio, interests and banner aren't set up on the server yet. Your profile works as before.",
            ru: "Описание, интересы и обложка пока не настроены на сервере. Профиль работает как раньше."
        )
    }

    public static var bannerCropTitle: String {
        PaceLocalization.text(de: "Ausschnitt wählen", en: "Choose the crop", ru: "Выбери фрагмент")
    }

    public static var bannerCropHint: String {
        PaceLocalization.text(
            de: "Verschiebe den Ausschnitt nach oben oder unten.",
            en: "Move the crop up or down.",
            ru: "Сдвинь фрагмент вверх или вниз."
        )
    }

    public static var use: String {
        PaceLocalization.text(de: "Verwenden", en: "Use", ru: "Использовать")
    }

    public static var cancel: String {
        PaceLocalization.text(de: "Abbrechen", en: "Cancel", ru: "Отмена")
    }

    public static var save: String {
        PaceLocalization.text(de: "Speichern", en: "Save", ru: "Сохранить")
    }
}
