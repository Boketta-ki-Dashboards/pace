import Foundation
import PaceCore
import PaceTestSupport
@testable import ProfileFeature
import Testing

/// Interessen 2.0 (Auftrag 7, Teil D 5): Katalog in Kategorien, eigene Interessen, gesprochene Sprachen, Land.
struct ProfileInterestRulesTests {
    @Test func catalogKeepsTheOldIDsAndGroupsEverything() {
        // Die zehn IDs aus Auftrag 6 bleiben unverändert.
        #expect(ProfileInterest.legacyCases.map(\.rawValue) == [
            "walking", "running", "hiking", "fitness", "cycling", "football", "outdoor", "everyday_movement", "challenges", "wellbeing",
        ])
        #expect(ProfileInterest.allCases.count == 50)
        #expect(Set(ProfileInterest.allCases.map(\.rawValue)).count == 50)
        // Gleiche IDs wie im Server-Katalog (snake_case, wie der Check der Katalogtabelle).
        for interest in ProfileInterest.allCases {
            #expect(interest.rawValue.range(of: "^[a-z][a-z_]{1,39}$", options: .regularExpression) != nil, "\(interest)")
        }
        let counts = Dictionary(grouping: ProfileInterest.allCases, by: \.category).mapValues(\.count)
        #expect(counts == [.sport: 18, .creative: 10, .tech: 8, .leisure: 9, .culture: 5])
        // „Reisen“ erscheint in zwei Kategorien, bleibt aber ein Eintrag.
        #expect(ProfileInterestCategory.culture.interests.contains(.travel))
        #expect(ProfileInterestCategory.leisure.interests.contains(.travel))
        for language in AppLanguage.allCases {
            PaceLocalization.$languageOverride.withValue(language) {
                let titles = ProfileInterest.allCases.map(\.title)
                #expect(Set(titles).count == titles.count, "\(language): doppelte Titel")
                #expect(!titles.contains { $0.isEmpty })
                #expect(ProfileInterestCategory.allCases.allSatisfy { !$0.title.isEmpty })
            }
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(ProfileInterest.webDevelopment.title == "Веб-разработка")
            #expect(ProfileInterestCategory.tech.title == "Техника и игры")
        }
    }

    @Test func customInterestsAreNormalizedAndValidatedLikeTheServer() {
        #expect(CustomInterestRules.normalized("  Musik \n  produzieren\t ") == "Musik produzieren")
        // Zerlegte Akzente werden zusammengesetzt (NFC), sonst entstünden Doppelte in anderer Schreibweise.
        #expect(CustomInterestRules.normalized("Cafe\u{301}") == "Café")
        #expect(CustomInterestRules.problem("") == .empty)
        #expect(CustomInterestRules.problem("x") == .tooShort)
        #expect(CustomInterestRules.problem(String(repeating: "a", count: 30)) == nil)
        #expect(CustomInterestRules.problem(String(repeating: "a", count: 31)) == .tooLong)
        // Ein sehr langes Wort ist nur bis zur Höchstlänge erlaubt.
        #expect(CustomInterestRules.problem("Donaudampfschifffahrtsgesellschaft") == .tooLong)
        #expect(CustomInterestRules.problem("Рэп-баттлы") == nil)
        #expect(CustomInterestRules.problem(String(repeating: "я", count: 30)) == nil)
        #expect(CustomInterestRules.problem("Kaffee ☕") == nil)
        #expect(CustomInterestRules.problem("Wandern 🚶‍♀️") == nil)
        #expect(CustomInterestRules.problem("Rap\u{200B}Battle") == .invalidCharacters)
        #expect(CustomInterestRules.problem("Rap\u{202E}") == .invalidCharacters)
        #expect(CustomInterestRules.problem("www.spam.example") == .link)
        #expect(CustomInterestRules.problem("https://pace.example") == .link)
        #expect(CustomInterestRules.problem("@lena") == .link)
        #expect(CustomInterestRules.problem("t.me/spam") == .link)
        #expect(CustomInterestRules.problem("onlyfans.com") == .link)
        #expect(CustomInterestRules.problem("Node.js") == nil)
        // Leer dargestellte Füllzeichen ergäben leere Chips.
        #expect(CustomInterestRules.problem("\u{3164}\u{3164}") == .invalidCharacters)
        #expect(CustomInterestRules.problem("Rap\u{2800}") == .invalidCharacters)
        // Geschütztes Leerzeichen am Rand fällt beim Normalisieren weg.
        #expect(CustomInterestRules.normalized("\u{00A0}Rap\u{3000}") == "Rap")
    }

    @Test func duplicatesAndCatalogTermsAreRecognized() {
        func validate(_ input: String, existing: [String] = [], selected: [ProfileInterest] = [], limit: Int = 20) -> Result<String, CustomInterestRules.Problem> {
            CustomInterestRules.validate(input, existing: existing, selected: selected, limit: limit)
        }
        #expect(validate(" Freestyle  Rap ") == .success("Freestyle Rap"))
        // „Rap“, „rap“ und „RAP“ sind dasselbe – und gibt es im Katalog.
        for input in ["Rap", "rap", "RAP", "Рэп", "basketball", "Webcoding", "web development"] {
            guard case .failure(.inCatalog) = validate(input) else {
                Issue.record("\(input) sollte den Katalogeintrag vorschlagen")
                continue
            }
        }
        #expect(validate("rap", selected: [.rap]) == .failure(.duplicate))
        #expect(validate("MUSIK PRODUZIEREN", existing: ["Musik produzieren"]) == .failure(.duplicate))
        #expect(validate("музыка", existing: ["Музыка"]) == .failure(.duplicate))
        #expect(validate("Breakdance", existing: Array(repeating: "x", count: 5), selected: Array(ProfileInterest.allCases.prefix(15)))
            == .failure(.limitReached))
        #expect(CustomInterestRules.parse(["Rap battles", "rap battles", " Musik ", "x", "www.a.de"]) == ["Rap battles", "Musik"])
    }

    @Test func languagesAndCountriesUseCodesNeverTheAppLanguage() {
        #expect(SpokenLanguageCatalog.codes.prefix(3) == ["de", "en", "ru"])
        #expect(Set(SpokenLanguageCatalog.codes).count == SpokenLanguageCatalog.codes.count)
        #expect(SpokenLanguageCatalog.codes.allSatisfy { SpokenLanguageCatalog.isValid($0) })
        for code in ["it", "sr", "sq", "ka"] {
            #expect(SpokenLanguageCatalog.codes.contains(code))
        }
        #expect(!SpokenLanguageCatalog.isValid("Deutsch"))
        #expect(SpokenLanguageCatalog.parse(["de", "de", "XX", "sr"]) == ["de", "sr"])
        #expect(SpokenLanguageCatalog.search("").count == SpokenLanguageCatalog.codes.count)
        // Suche nach Code findet immer etwas, auch ohne Systemnamen.
        #expect(SpokenLanguageCatalog.search("sr").contains("sr"))
        #expect(!SpokenLanguageCatalog.name(for: "de").isEmpty)

        #expect(Set(ProfileCountryCatalog.codes).count == ProfileCountryCatalog.codes.count)
        #expect(ProfileCountryCatalog.codes.allSatisfy { ProfileCountryCatalog.isValid($0) })
        #expect(ProfileCountryCatalog.codes.contains("IT") && ProfileCountryCatalog.codes.contains("XK"))
        #expect(ProfileCountryCatalog.flag(for: "IT") == "🇮🇹")
        #expect(ProfileCountryCatalog.search("IT").contains("IT"))
        #expect(!ProfileCountryCatalog.isValid("Italien"))
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(ProfileCountryCatalog.name(for: "XK") == "Косово")
        }
    }
}

@MainActor
struct ProfileInterestsViewModelTests {
    private func makeViewModel(_ own: ProfileDetails) async -> (ProfileDetailsViewModel, ProfileDetailsRepositoryStub) {
        let repository = ProfileDetailsRepositoryStub { $0.own = own }
        let viewModel = ProfileDetailsViewModel(repository: repository, media: MediaRepositoryStub())
        await viewModel.load()
        viewModel.beginEditing()
        return (viewModel, repository)
    }

    @Test func oldProfilesWithThreeOrFiveInterestsStayIntact() async {
        let (three, _) = await makeViewModel(ProfileDetails(interests: [.walking, .hiking, .fitness], supportsExtendedProfile: true))
        #expect(three.draftInterests == [.walking, .hiking, .fitness])
        #expect(!three.hasChanges)
        #expect(three.interestLimit == 20)
        let (five, _) = await makeViewModel(ProfileDetails(interests: [.walking, .running, .hiking, .fitness, .cycling], supportsExtendedProfile: true))
        five.toggleInterest(.rap)
        #expect(five.draftInterests.count == 6)
        #expect(five.canAddInterest)
    }

    @Test func olderServerOffersOnlyTheOriginalCatalog() async {
        let (viewModel, _) = await makeViewModel(ProfileDetails(interests: [.walking]))
        #expect(!viewModel.supportsExtendedProfile)
        #expect(viewModel.interestLimit == 5)
        #expect(viewModel.interestCategories == [.sport])
        #expect(viewModel.catalog(in: .sport).allSatisfy { $0.isLegacy })
        viewModel.toggleInterest(.rap)
        #expect(viewModel.draftInterests == [.walking])
        viewModel.customInterestInput = "Freestyle"
        #expect(!viewModel.addCustomInterest())
        viewModel.toggleLanguage("de")
        viewModel.setCountry("IT")
        #expect(viewModel.draftLanguages.isEmpty)
        #expect(viewModel.draftCountry == nil)
        #expect(!viewModel.hasChanges)
    }

    @Test func twentyInterestsIncludingOwnOnesThenNoMore() async {
        let (viewModel, repository) = await makeViewModel(ProfileDetails(supportsExtendedProfile: true))
        for interest in ProfileInterest.allCases.prefix(17) {
            viewModel.toggleInterest(interest)
        }
        for term in ["Musik produzieren", "Рэп-баттлы", "Kaffee ☕"] {
            viewModel.customInterestInput = term
            #expect(viewModel.addCustomInterest(), "\(term)")
        }
        #expect(viewModel.selectedInterestCount == 20)
        #expect(!viewModel.canAddInterest)
        viewModel.toggleInterest(.animals)
        #expect(!viewModel.isSelected(.animals))
        viewModel.customInterestInput = "Breakdance"
        #expect(!viewModel.addCustomInterest())
        #expect(viewModel.customInterestProblem == .limitReached)
        // Solange der nicht hinzufügbare Begriff im Feld steht, speichert „Speichern“ nicht (Hinweis bleibt sichtbar).
        let blocked = await viewModel.save()
        #expect(!blocked)
        viewModel.customInterestInput = ""
        #expect(await viewModel.save())
        #expect(repository.state.withLock { $0.own.customInterests } == ["Musik produzieren", "Рэп-баттлы", "Kaffee ☕"])
        #expect(viewModel.details.allInterests.count == 20)

        // Eigenes Interesse wieder entfernen.
        viewModel.beginEditing()
        viewModel.removeCustomInterest("Kaffee ☕")
        #expect(viewModel.hasChanges)
        #expect(await viewModel.save())
        #expect(viewModel.details.customInterests == ["Musik produzieren", "Рэп-баттлы"])
    }

    @Test func catalogTermsAreSuggestedInsteadOfDuplicated() async {
        let (viewModel, _) = await makeViewModel(ProfileDetails(supportsExtendedProfile: true))
        viewModel.customInterestInput = "rap"
        #expect(viewModel.customInterestSuggestion == .rap)
        // „Hinzufügen“ wählt den Katalogeintrag statt eines eigenen Chips.
        #expect(viewModel.addCustomInterest())
        #expect(viewModel.draftInterests == [.rap])
        #expect(viewModel.draftCustomInterests.isEmpty)
        #expect(viewModel.customInterestInput.isEmpty)
        viewModel.customInterestInput = "RAP"
        #expect(viewModel.customInterestSuggestion == nil)
        #expect(!viewModel.addCustomInterest())
        #expect(viewModel.customInterestProblem == .duplicate)
        // Weitertippen blendet den Hinweis aus.
        viewModel.customInterestInput = "RAP-Battles"
        #expect(viewModel.customInterestProblem == nil)
        #expect(viewModel.addCustomInterest())
        viewModel.customInterestInput = "rap-battles"
        #expect(!viewModel.addCustomInterest())
        #expect(viewModel.customInterestProblem == .duplicate)
        viewModel.customInterestInput = "   "
        #expect(!viewModel.addCustomInterest())
        #expect(viewModel.customInterestProblem == .empty)
    }

    @Test func languagesAndCountryAreOptionalAndRemovable() async {
        let (viewModel, repository) = await makeViewModel(ProfileDetails(supportsExtendedProfile: true))
        #expect(viewModel.draftLanguages.isEmpty)
        for code in ["de", "ru", "sr", "sq", "ka"] {
            viewModel.toggleLanguage(code)
        }
        viewModel.setCountry("GE")
        #expect(await viewModel.save())
        #expect(repository.state.withLock { $0.own.spokenLanguages } == ["de", "ru", "sr", "sq", "ka"])
        #expect(repository.state.withLock { $0.own.countryCode } == "GE")

        viewModel.beginEditing()
        viewModel.toggleLanguage("ru")
        viewModel.setCountry(nil)
        #expect(await viewModel.save())
        #expect(viewModel.details.spokenLanguages == ["de", "sr", "sq", "ka"])
        #expect(viewModel.details.countryCode == nil)

        // Höchstens zehn Sprachen.
        viewModel.beginEditing()
        for code in SpokenLanguageCatalog.codes.prefix(12) {
            viewModel.toggleLanguage(code)
        }
        #expect(viewModel.draftLanguages.count == ProfileInterestRules.maximumLanguages)
        #expect(!viewModel.canAddLanguage)
    }

    @Test func languageSwitchTranslatesCatalogButKeepsOwnTerms() {
        let details = ProfileDetails(interests: [.rap, .travel], customInterests: ["Musik produzieren"], supportsExtendedProfile: true)
        let german = PaceLocalization.$languageOverride.withValue(.german) { details.allInterests.map(\.title) }
        let russian = PaceLocalization.$languageOverride.withValue(.russian) { details.allInterests.map(\.title) }
        #expect(german == ["Rap", "Reisen", "Musik produzieren"])
        #expect(russian == ["Рэп", "Путешествия", "Musik produzieren"])
    }

    @Test func pendingTermIsAddedOnSaveAndCatalogChoiceReplacesTheSameCustomTerm() async {
        let (viewModel, repository) = await makeViewModel(ProfileDetails(customInterests: ["Freestyle", "Kaffee ☕"], supportsExtendedProfile: true))
        // Katalog „Freestyle“ wählen: der gleichnamige eigene Begriff entfällt (nichts doppelt).
        viewModel.toggleInterest(.freestyle)
        #expect(viewModel.draftInterests == [.freestyle])
        #expect(viewModel.draftCustomInterests == ["Kaffee ☕"])
        // Eingetippt, aber nicht „Hinzufügen“ gedrückt: „Speichern“ übernimmt den Begriff.
        viewModel.customInterestInput = "Breakdance"
        #expect(viewModel.hasChanges)
        #expect(await viewModel.save())
        #expect(repository.state.withLock { $0.own.customInterests } == ["Kaffee ☕", "Breakdance"])
        #expect(viewModel.customInterestInput.isEmpty)
        // Ungültiger eingetippter Begriff: nicht speichern, Hinweis am Feld.
        viewModel.customInterestInput = "kaffee ☕"
        let savedInvalid = await viewModel.save()
        #expect(!savedInvalid)
        #expect(viewModel.customInterestProblem == .duplicate)
    }

    @Test func interestsOfANewerAppVersionCountAndAreKept() async {
        let (viewModel, repository) = await makeViewModel(ProfileDetails(
            interests: [.rap], customInterests: ["Freestyle Rap"], supportsExtendedProfile: true,
            preservedInterestIDs: ["future_0"]
        ))
        #expect(viewModel.selectedInterestCount == 3)
        viewModel.toggleInterest(.travel)
        #expect(await viewModel.save())
        #expect(repository.state.withLock { $0.own.preservedInterestIDs } == ["future_0"])
    }

    @Test func draftsAndDiscardIncludeTheNewFields() async {
        let (viewModel, _) = await makeViewModel(ProfileDetails(customInterests: ["Freestyle"], supportsExtendedProfile: true))
        viewModel.removeCustomInterest("Freestyle")
        viewModel.toggleLanguage("it")
        #expect(viewModel.hasChanges)
        viewModel.discardChanges()
        #expect(viewModel.draftCustomInterests == ["Freestyle"])
        #expect(viewModel.draftLanguages.isEmpty)
        #expect(!viewModel.hasChanges)
    }
}
