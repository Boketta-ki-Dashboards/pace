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
    /// Fehler beim Banner (Hochladen, Entfernen, unlesbares Foto) – erscheint direkt am Banner, nicht unten bei
    /// „Speichern“.
    public private(set) var bannerError: String?
    /// Nach erfolgreichem Speichern bis zur nächsten Änderung: „Gespeichert“.
    public private(set) var didSave = false

    // Entwurf beim Bearbeiten
    /// Ein Entwurf wurde begonnen (bleibt nach dem Verlassen von „Profil bearbeiten“ erhalten, bis er gespeichert oder
    /// verworfen wird).
    @ObservationIgnored private var hasDraftSession = false
    public var draftBio = ""
    public private(set) var draftInterests: [ProfileInterest] = []
    /// Selbst eingegebene Interessen (normalisiert, ohne Doppelte).
    public private(set) var draftCustomInterests: [String] = []
    public private(set) var draftLanguages: [String] = []
    public var draftCountry: String?
    public var draftShowsAchievements = false
    /// Eingabefeld „Eigenes Interesse hinzufügen“.
    public var customInterestInput = "" {
        didSet { if customInterestInput != oldValue { customInterestProblem = nil } }
    }
    /// Problem der letzten Eingabe (z. B. doppelt, zu lang) – verschwindet beim Weitertippen.
    public private(set) var customInterestProblem: CustomInterestRules.Problem?

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
        details.bio != nil || details.hasInterestsOrBackground || details.bannerPath != nil
            || !details.visibleAchievements.isEmpty
    }

    /// Der Server kennt eigene Interessen, Sprachen und Land (Migration 20261102100000).
    public var supportsExtendedProfile: Bool {
        details.supportsExtendedProfile
    }

    /// Auszeichnungen, die beim Einschalten veröffentlicht würden: erreichte Stufen, ohne schon veröffentlichte höhere
    /// zu verlieren (``ProfileAchievement/upgraded(_:with:)``).
    public var earned: [ProfileAchievement] {
        ProfileAchievement.upgraded(details.achievements, with: earnedAchievements())
    }

    /// Speichern oder Banner-Änderung läuft – weitere Schreibvorgänge warten (sonst überschreiben sich die Anfragen).
    public var isBusy: Bool {
        isSaving || bannerActivity != .idle
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
        hasDraftSession = true
        draftBio = details.bio ?? ""
        draftInterests = details.interests
        draftCustomInterests = details.customInterests
        draftLanguages = details.spokenLanguages
        draftCountry = details.countryCode
        draftShowsAchievements = details.showsAchievements
        customInterestInput = ""
        customInterestProblem = nil
        errorMessage = nil
        didSave = false
    }

    /// „Profil bearbeiten“ öffnen: Entwurf sofort aus dem bekannten Stand (die Felder sind nie leer, „Speichern“ ist
    /// ohne Änderung aus), danach frisch laden. Der Serverstand ersetzt den Entwurf nur, solange noch nichts geändert
    /// wurde – Eingaben während des Ladens bleiben.
    public func prepareEditing() async {
        // Ungespeicherte Änderungen aus einem früheren Besuch bleiben (Speichern oder ausdrücklich verwerfen).
        let keepsDraft = hasDraftSession && hasUserEdits
        if !keepsDraft { beginEditing() }
        let untouched = draft
        await load()
        if !keepsDraft, draft == untouched { beginEditing() }
    }

    /// Verwirft ungespeicherte Änderungen (zurück zum gespeicherten Stand).
    public func discardChanges() {
        beginEditing()
    }

    private struct Draft: Equatable {
        let bio: String
        let interests: [ProfileInterest]
        let customInterests: [String]
        let languages: [String]
        let country: String?
        let showsAchievements: Bool
        let customInterestInput: String
    }

    private var draft: Draft {
        Draft(
            bio: draftBio,
            interests: draftInterests,
            customInterests: draftCustomInterests,
            languages: draftLanguages,
            country: draftCountry,
            showsAchievements: draftShowsAchievements,
            customInterestInput: customInterestInput
        )
    }

    /// Zeichen der Bio wie auf dem Server gezählt (nach dem Normalisieren).
    public var bioLength: Int {
        ProfileBioRules.length(ProfileBioRules.normalized(draftBio) ?? "")
    }

    public var bioProblem: ProfileBioRules.Problem? {
        ProfileBioRules.normalized(draftBio).flatMap(ProfileBioRules.problem)
    }

    /// Von der Person geänderte Angaben – auch ein eingetippter, noch nicht hinzugefügter eigener Begriff. Neu
    /// erreichte Auszeichnungsstufen zählen nicht dazu (die trägt die App selbst nach).
    public var hasUserEdits: Bool {
        ProfileBioRules.normalized(draftBio) != details.bio
            || draftInterests != details.interests
            || draftCustomInterests != details.customInterests
            || draftLanguages != details.spokenLanguages
            || draftCountry != details.countryCode
            || draftShowsAchievements != details.showsAchievements
            || hasPendingCustomInterest
    }

    /// Etwas zu speichern (auch eine neu erreichte Auszeichnungsstufe, wenn Auszeichnungen eingeschaltet sind).
    public var hasChanges: Bool {
        hasUserEdits || (draftShowsAchievements && earned != details.achievements)
    }

    /// Im Feld „Eigenes Interesse“ steht Text, der noch nicht hinzugefügt wurde.
    public var hasPendingCustomInterest: Bool {
        supportsExtendedProfile && !CustomInterestRules.normalized(customInterestInput).isEmpty
    }

    public var canSave: Bool {
        isAvailable && bioProblem == nil && hasChanges && !isBusy
    }

    public func isSelected(_ interest: ProfileInterest) -> Bool {
        draftInterests.contains(interest)
    }

    /// Höchstzahl der Interessen (Katalog und eigene zusammen): 20, auf älteren Servern 5.
    public var interestLimit: Int {
        details.interestLimit
    }

    /// Ausgewählte Interessen (Katalog und eigene, dazu Einträge einer neueren App-Version, die hier nicht angezeigt
    /// werden, aber erhalten bleiben).
    public var selectedInterestCount: Int {
        draftInterests.count + draftCustomInterests.count + details.preservedInterestIDs.count
    }

    /// Kategorien zur Auswahl – auf älteren Servern nur die mit dem ursprünglichen Katalog.
    public var interestCategories: [ProfileInterestCategory] {
        ProfileInterestCategory.allCases.filter { !catalog(in: $0).isEmpty }
    }

    /// Wählbare Einträge einer Kategorie (ältere Server: nur der ursprüngliche Katalog).
    public func catalog(in category: ProfileInterestCategory) -> [ProfileInterest] {
        category.interests.filter { supportsExtendedProfile || $0.isLegacy }
    }

    /// Wählt ein Interesse aus oder ab (zusammen mit eigenen höchstens ``interestLimit``).
    public func toggleInterest(_ interest: ProfileInterest) {
        if let index = draftInterests.firstIndex(of: interest) {
            draftInterests.remove(at: index)
        } else if canAddInterest, supportsExtendedProfile || interest.isLegacy {
            select(interest)
        }
    }

    /// Wählt einen Katalogeintrag aus; ein gleichnamiger eigener Begriff (z. B. „Freestyle“) entfällt dabei, damit nichts
    /// doppelt erscheint.
    private func select(_ interest: ProfileInterest) {
        let titles = Set((interest.allTitles + [interest.rawValue]).map(CustomInterestRules.key))
        draftCustomInterests.removeAll { titles.contains(CustomInterestRules.key($0)) }
        draftInterests.append(interest)
    }

    public var canAddInterest: Bool {
        selectedInterestCount < interestLimit
    }

    /// Katalogeintrag, der zur aktuellen Eingabe passt (z. B. „rap“ → Rap) – wird statt eines eigenen Chips
    /// vorgeschlagen.
    public var customInterestSuggestion: ProfileInterest? {
        CustomInterestRules.catalogMatch(for: customInterestInput).flatMap { draftInterests.contains($0) ? nil : $0 }
    }

    /// „Hinzufügen“: Gibt es den Begriff im Katalog, wird der Katalogeintrag ausgewählt; sonst entsteht ein eigener
    /// Chip. Ungültige oder doppelte Eingaben bleiben im Feld und zeigen ``customInterestProblem``.
    /// - Returns: `true`, wenn etwas hinzugefügt wurde.
    @discardableResult
    public func addCustomInterest() -> Bool {
        guard supportsExtendedProfile else { return false }
        switch CustomInterestRules.validate(
            customInterestInput,
            existing: draftCustomInterests,
            selected: draftInterests,
            limit: interestLimit
        ) {
        case .success(let text):
            draftCustomInterests.append(text)
            customInterestInput = ""
            return true
        case .failure(.inCatalog(let interest)):
            guard canAddInterest else {
                customInterestProblem = .limitReached
                return false
            }
            select(interest)
            customInterestInput = ""
            return true
        case .failure(let problem):
            customInterestProblem = problem
            return false
        }
    }

    public func removeCustomInterest(_ text: String) {
        draftCustomInterests.removeAll { $0 == text }
    }

    // MARK: Sprachen und Land

    public func speaks(_ code: String) -> Bool {
        draftLanguages.contains(code)
    }

    public var canAddLanguage: Bool {
        draftLanguages.count < ProfileInterestRules.maximumLanguages
    }

    /// Wählt eine gesprochene Sprache aus oder ab (höchstens zehn).
    public func toggleLanguage(_ code: String) {
        if let index = draftLanguages.firstIndex(of: code) {
            draftLanguages.remove(at: index)
        } else if canAddLanguage, supportsExtendedProfile, SpokenLanguageCatalog.isValid(code) {
            draftLanguages.append(code)
        }
    }

    /// Land bzw. Kulturbezug wählen oder entfernen (`nil`).
    public func setCountry(_ code: String?) {
        guard supportsExtendedProfile || code == nil else { return }
        draftCountry = code.flatMap { ProfileCountryCatalog.isValid($0) ? $0 : nil }
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
        // Eingetippter, noch nicht hinzugefügter Begriff: erst hinzufügen (ungültig → Hinweis am Feld, nicht speichern).
        if hasPendingCustomInterest, !addCustomInterest() {
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        var updated = details
        updated.bio = ProfileBioRules.normalized(draftBio)
        updated.interests = draftInterests
        updated.customInterests = draftCustomInterests
        updated.spokenLanguages = draftLanguages
        updated.countryCode = draftCountry
        updated.showsAchievements = draftShowsAchievements
        updated.achievements = draftShowsAchievements ? earned : []
        do {
            details = try await repository.saveOwnDetails(updated)
            didSave = true
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// Bei eingeschalteten Auszeichnungen: neu erreichte Stufen nachtragen (z. B. eine längere Serie), ohne Rückfrage.
    /// Nur aufwerten, nie automatisch entfernen.
    public func refreshPublishedAchievements() async {
        guard let repository, isAvailable, details.showsAchievements, !isBusy else { return }
        let earned = earned
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
        guard let repository, let media, isAvailable, !isBusy else { return nil }
        guard jpegData.count <= MediaRules.maximumBytes(for: .avatar) else {
            bannerError = Self.message(for: MediaError.tooLarge)
            return nil
        }
        bannerActivity = .uploading
        bannerError = nil
        defer { bannerActivity = .idle }

        let previous = details.banner
        let uploaded: MediaReference
        do {
            uploaded = try await media.upload(jpegData, contentType: "image/jpeg", to: .avatar)
        } catch {
            bannerError = Self.message(for: error)
            return nil
        }
        var updated = details
        updated.bannerPath = uploaded.path
        do {
            details = try await repository.saveOwnDetails(updated)
        } catch {
            // Antwort verloren (Netz)? Dann nachsehen, ob der Server das neue Banner doch schon übernommen hat.
            if case .network = error as? ProfileDetailsError, let current = try? await repository.ownDetails(),
               current.bannerPath == uploaded.path {
                details = current
            } else {
                // Das neue Bild wird nicht verwendet – nicht als verwaiste Datei liegen lassen.
                try? await media.delete(uploaded)
                bannerError = Self.message(for: error)
                return nil
            }
        }
        // Das alte Banner erst löschen, wenn der Server das neue bestätigt hat.
        if let previous, previous != uploaded, details.bannerPath == uploaded.path {
            try? await media.delete(previous)
        }
        return uploaded
    }

    /// Entfernt das Banner (danach erscheint der neutrale Pace-Hintergrund) und löscht die Datei.
    public func removeBanner() async {
        guard let repository, let previous = details.banner, !isBusy else { return }
        bannerActivity = .removing
        bannerError = nil
        defer { bannerActivity = .idle }
        var updated = details
        updated.bannerPath = nil
        do {
            details = try await repository.saveOwnDetails(updated)
        } catch {
            bannerError = Self.message(for: error)
            return
        }
        try? await media?.delete(previous)
    }

    public func reportUnreadablePhoto() {
        bannerError = PaceLocalization.text(
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

    /// Kurze Beschriftung des Knopfs neben dem Profilbild (VoiceOver: ``editProfile``).
    public static var edit: String {
        PaceLocalization.text(de: "Bearbeiten", en: "Edit", ru: "Изменить")
    }

    public static var saved: String {
        PaceLocalization.text(de: "Gespeichert", en: "Saved", ru: "Сохранено")
    }

    public static var retry: String {
        PaceLocalization.text(de: "Erneut versuchen", en: "Try again", ru: "Повторить")
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

    public static func interestsHint(selected: Int, limit: Int) -> String {
        PaceLocalization.text(
            de: "\(selected) von \(limit) ausgewählt",
            en: "\(selected) of \(limit) selected",
            ru: "Выбрано \(selected) из \(limit)"
        )
    }

    public static var yourInterests: String {
        PaceLocalization.text(de: "Deine Auswahl", en: "Your selection", ru: "Твой выбор")
    }

    public static var noInterestsSelected: String {
        PaceLocalization.text(
            de: "Noch nichts ausgewählt – tippe unten auf Begriffe, die zu dir passen.",
            en: "Nothing selected yet – tap the terms below that fit you.",
            ru: "Пока ничего не выбрано – нажми ниже на то, что тебе близко."
        )
    }

    public static var addCustomInterest: String {
        PaceLocalization.text(de: "Eigenes Interesse hinzufügen", en: "Add your own interest", ru: "Добавить свой интерес")
    }

    public static var customInterestPlaceholder: String {
        PaceLocalization.text(de: "z. B. Musik produzieren", en: "e.g. Producing music", ru: "например, Битмейкинг")
    }

    public static var add: String {
        PaceLocalization.text(de: "Hinzufügen", en: "Add", ru: "Добавить")
    }

    public static func selectSuggestion(_ interest: ProfileInterest) -> String {
        PaceLocalization.text(
            de: "„\(interest.title)“ aus dem Katalog wählen",
            en: "Choose “\(interest.title)” from the catalog",
            ru: "Выбрать «\(interest.title)» из каталога"
        )
    }

    public static var customInterestNote: String {
        PaceLocalization.text(
            de: "Eigene Begriffe erscheinen nur auf deinem Profil – so, wie du sie schreibst. Andere können sie melden.",
            en: "Your own terms appear only on your profile – exactly as you write them. Others can report them.",
            ru: "Свои слова видны только в твоём профиле – так, как ты их пишешь. Другие могут на них пожаловаться."
        )
    }

    public static func removeInterest(_ title: String) -> String {
        PaceLocalization.text(de: "\(title) entfernen", en: "Remove \(title)", ru: "Удалить \(title)")
    }

    public static var legacyInterestsHint: String {
        PaceLocalization.text(
            de: "Mehr Interessen, eigene Begriffe und Sprachen kommen mit dem nächsten Server-Update.",
            en: "More interests, your own terms and languages arrive with the next server update.",
            ru: "Больше интересов, свои слова и языки появятся со следующим обновлением сервера."
        )
    }

    public static var allInterests: String {
        PaceLocalization.text(de: "Alle Interessen ansehen", en: "See all interests", ru: "Все интересы")
    }

    public static var spokenLanguages: String {
        PaceLocalization.text(de: "Gesprochene Sprachen", en: "Languages I speak", ru: "Языки, на которых я говорю")
    }

    public static var addLanguages: String {
        PaceLocalization.text(de: "Sprachen auswählen", en: "Choose languages", ru: "Выбрать языки")
    }

    public static var editLanguages: String {
        PaceLocalization.text(de: "Sprachen ändern", en: "Change languages", ru: "Изменить языки")
    }

    public static var languagesNote: String {
        PaceLocalization.text(
            de: "Freiwillig und unabhängig von der App-Sprache.",
            en: "Optional and independent of the app language.",
            ru: "По желанию и независимо от языка приложения."
        )
    }

    public static func languagesHint(selected: Int) -> String {
        PaceLocalization.text(
            de: "\(selected) von \(ProfileInterestRules.maximumLanguages) ausgewählt",
            en: "\(selected) of \(ProfileInterestRules.maximumLanguages) selected",
            ru: "Выбрано \(selected) из \(ProfileInterestRules.maximumLanguages)"
        )
    }

    public static var searchLanguages: String {
        PaceLocalization.text(de: "Sprache suchen", en: "Search languages", ru: "Найти язык")
    }

    public static var country: String {
        PaceLocalization.text(de: "Land & Kultur", en: "Country & culture", ru: "Страна и культура")
    }

    public static var chooseCountry: String {
        PaceLocalization.text(de: "Land auswählen", en: "Choose a country", ru: "Выбрать страну")
    }

    public static var removeCountry: String {
        PaceLocalization.text(de: "Land entfernen", en: "Remove country", ru: "Убрать страну")
    }

    public static var searchCountries: String {
        PaceLocalization.text(de: "Land suchen", en: "Search countries", ru: "Найти страну")
    }

    public static var countryNote: String {
        PaceLocalization.text(
            de: "Freiwillig: ein Land, mit dem du dich verbunden fühlst. Nur sichtbar, wenn du eins wählst – wird nicht überprüft und hat keinen Einfluss auf Ranglisten.",
            en: "Optional: a country you feel connected to. Only visible if you choose one – it isn't verified and doesn't affect rankings.",
            ru: "По желанию: страна, с которой ты себя связываешь. Видна, только если ты её выберешь, – не проверяется и не влияет на рейтинги."
        )
    }

    public static var done: String {
        PaceLocalization.text(de: "Fertig", en: "Done", ru: "Готово")
    }

    public static var noResults: String {
        PaceLocalization.text(de: "Keine Treffer", en: "No results", ru: "Ничего не найдено")
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
            de: "Freiwillig und standardmäßig aus. Sichtbar für alle, die dein Profil sehen können – nur die Stufen (z. B. „30 Tage in Folge“), nie deine genauen Schritte. Ermittelt aus deiner Serie und deinem besten Tag.",
            en: "Optional and off by default. Visible to everyone who can see your profile – only the levels (e.g. “30 days in a row”), never your exact steps. Based on your streak and your best day.",
            ru: "По желанию, по умолчанию выключено. Видно всем, кто может открыть твой профиль, – только уровни (например, «30 дней подряд»), без точного числа шагов. Основано на твоей серии и лучшем дне."
        )
    }

    public static var noAchievementsYet: String {
        PaceLocalization.text(
            de: "Noch keine Auszeichnung – die erste gibt es ab 7 Tagen in Folge.",
            en: "No achievements yet – the first one comes at 7 days in a row.",
            ru: "Наград пока нет – первая будет за 7 дней подряд."
        )
    }

    public static var unavailable: String {
        PaceLocalization.text(
            de: "Bio, Interessen und Banner stehen bald zur Verfügung. Bis dahin funktioniert dein Profil wie gewohnt.",
            en: "Bio, interests and banner are coming soon. Until then your profile works as usual.",
            ru: "Описание, интересы и обложка скоро появятся. А пока профиль работает как обычно."
        )
    }

    /// Kurz: steht in der Navigationsleiste zwischen „Abbrechen“ und „Verwenden“ (längere Titel würden abgeschnitten).
    public static var bannerCropTitle: String {
        PaceLocalization.text(de: "Ausschnitt", en: "Crop", ru: "Кадр")
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

    public static var profilePicture: String {
        PaceLocalization.text(de: "Profilbild", en: "Profile picture", ru: "Фото профиля")
    }

    public static var tapToEdit: String {
        PaceLocalization.text(de: "Antippen zum Ändern", en: "Tap to change", ru: "Нажми, чтобы изменить")
    }

    public static var picturesHint: String {
        PaceLocalization.text(
            de: "Profilbild oder Banner antippen, um sie zu ändern.",
            en: "Tap your photo or banner to change it.",
            ru: "Нажми на фото или обложку, чтобы изменить их."
        )
    }

    public static var editPicture: String {
        PaceLocalization.text(de: "Bild bearbeiten", en: "Edit picture", ru: "Изменить изображение")
    }

    public static var changePhoto: String {
        PaceLocalization.text(de: "Foto ändern", en: "Change photo", ru: "Изменить фото")
    }

    public static var removePhoto: String {
        PaceLocalization.text(de: "Foto entfernen", en: "Remove photo", ru: "Удалить фото")
    }

    public static var avatarCropTitle: String {
        PaceLocalization.text(de: "Ausschnitt", en: "Crop", ru: "Кадр")
    }

    public static var avatarCropHintHorizontal: String {
        PaceLocalization.text(
            de: "Verschiebe das Foto nach links oder rechts.",
            en: "Move the photo left or right.",
            ru: "Сдвинь фото влево или вправо."
        )
    }

    public static var avatarCropHintVertical: String {
        PaceLocalization.text(
            de: "Verschiebe das Foto nach oben oder unten.",
            en: "Move the photo up or down.",
            ru: "Сдвинь фото вверх или вниз."
        )
    }

    public static var discard: String {
        PaceLocalization.text(de: "Änderungen verwerfen", en: "Discard changes", ru: "Отменить изменения")
    }

    public static var unsavedHint: String {
        PaceLocalization.text(
            de: "Ungespeicherte Änderungen – speichern oder verwerfen.",
            en: "Unsaved changes – save or discard them.",
            ru: "Есть несохранённые изменения – сохрани или отмени их."
        )
    }
}
