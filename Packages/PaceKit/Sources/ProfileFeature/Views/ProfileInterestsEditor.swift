import DesignSystem
import PaceCore
import SwiftUI

// MARK: - Interessen

/// Interessen unter „Profil bearbeiten“ (Auftrag 7): oben die eigene Auswahl (entfernen per ×), darunter „+ Eigenes
/// Interesse hinzufügen“ und der Katalog in aufklappbaren Kategorien. Auf älteren Servern nur der ursprüngliche
/// Katalog mit höchstens fünf Einträgen.
struct ProfileInterestsCard: View {
    @Bindable var details: ProfileDetailsViewModel
    /// Für Vorschaubilder: diese Kategorien aufgeklappt (sonst die mit Auswahl, mindestens die erste).
    var initiallyExpanded: Set<ProfileInterestCategory>?
    /// Für Vorschaubilder: Eingabefeld für ein eigenes Interesse gleich offen.
    var showsCustomFieldInitially = false

    @State private var expanded: Set<ProfileInterestCategory>?
    @State private var showsCustomField = false
    @FocusState private var isCustomFieldFocused: Bool

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    PaceCardHeader(ProfileDetailsTexts.interests)
                    Spacer()
                    Text(ProfileDetailsTexts.interestsHint(selected: details.selectedInterestCount, limit: details.interestLimit))
                        .font(PaceFont.caption.monospacedDigit())
                        .foregroundStyle(details.canAddInterest ? PaceColor.textSecondary : PaceColor.accent)
                }
                selection
                if details.supportsExtendedProfile {
                    customInterest
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(details.interestCategories) { category in
                        Divider().overlay(PaceColor.border)
                        categorySection(category)
                    }
                }
                if !details.supportsExtendedProfile {
                    ProfileFootnote(text: ProfileDetailsTexts.legacyInterestsHint)
                }
            }
        }
    }

    // MARK: Auswahl

    private var selection: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            Text(ProfileDetailsTexts.yourInterests)
                .font(PaceFont.caption.weight(.semibold))
                .foregroundStyle(PaceColor.textSecondary)
            if details.selectedInterestCount == 0 {
                ProfileFootnote(text: ProfileDetailsTexts.noInterestsSelected)
            } else {
                PaceFlowLayout(spacing: PaceSpacing.xs) {
                    ForEach(details.draftInterests) { interest in
                        ProfileRemovableChip(title: interest.title, systemImage: interest.systemImage) {
                            details.toggleInterest(interest)
                        }
                    }
                    ForEach(details.draftCustomInterests, id: \.self) { text in
                        ProfileRemovableChip(title: text, systemImage: nil) {
                            details.removeCustomInterest(text)
                        }
                    }
                }
            }
        }
    }

    // MARK: Eigenes Interesse

    @ViewBuilder private var customInterest: some View {
        if showsCustomField || showsCustomFieldInitially {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                HStack(spacing: PaceSpacing.xs) {
                    TextField(ProfileDetailsTexts.customInterestPlaceholder, text: $details.customInterestInput)
                        .font(PaceFont.body)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($isCustomFieldFocused)
                        .onSubmit(add)
                        .padding(.horizontal, PaceSpacing.s)
                        .frame(minHeight: 44)
                        .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                        .accessibilityLabel(ProfileDetailsTexts.addCustomInterest)
                    Button(ProfileDetailsTexts.add, action: add)
                        .buttonStyle(.paceCompact)
                        .disabled(CustomInterestRules.normalized(details.customInterestInput).isEmpty || !details.canAddInterest)
                }
                if let problem = details.customInterestProblem {
                    ProfileFootnote(text: CustomInterestRules.message(for: problem), isError: true)
                } else if let suggestion = details.customInterestSuggestion {
                    // Gibt es den Begriff im Katalog, lieber den Katalogeintrag (übersetzt, mit Symbol).
                    Button {
                        details.toggleInterest(suggestion)
                        details.customInterestInput = ""
                    } label: {
                        Label(ProfileDetailsTexts.selectSuggestion(suggestion), systemImage: suggestion.systemImage)
                            .font(PaceFont.callout.weight(.semibold))
                            .foregroundStyle(PaceColor.accent)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pacePressable)
                    .disabled(!details.canAddInterest)
                }
                ProfileFootnote(text: ProfileDetailsTexts.customInterestNote)
            }
            .task {
                // Kurz warten, bis das neu eingeblendete Feld im Layout steht – sonst bleibt die Tastatur zu.
                guard showsCustomField else { return }
                try? await Task.sleep(for: .milliseconds(150))
                isCustomFieldFocused = true
            }
        } else {
            Button {
                showsCustomField = true
            } label: {
                Label(ProfileDetailsTexts.addCustomInterest, systemImage: "plus")
                    .font(PaceFont.callout.weight(.semibold))
                    .foregroundStyle(PaceColor.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .disabled(!details.canAddInterest)
        }
    }

    private func add() {
        if details.addCustomInterest() { isCustomFieldFocused = true }
    }

    // MARK: Katalog

    private var expandedCategories: Set<ProfileInterestCategory> {
        if let expanded { return expanded }
        if let initiallyExpanded { return initiallyExpanded }
        let withSelection = details.interestCategories.filter { category in
            details.catalog(in: category).contains(where: details.isSelected)
        }
        return Set(withSelection.isEmpty ? Array(details.interestCategories.prefix(1)) : withSelection)
    }

    private func toggle(_ category: ProfileInterestCategory) {
        var current = expandedCategories
        if current.contains(category) { current.remove(category) } else { current.insert(category) }
        withAnimation(.snappy(duration: 0.22)) { expanded = current }
    }

    private func categorySection(_ category: ProfileInterestCategory) -> some View {
        let interests = details.catalog(in: category)
        let selectedCount = interests.filter(details.isSelected).count
        let isExpanded = expandedCategories.contains(category)
        return VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            Button {
                toggle(category)
            } label: {
                HStack(spacing: PaceSpacing.xs) {
                    Image(systemName: category.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PaceColor.accent)
                        .frame(width: 24)
                    Text(category.title)
                        .font(PaceFont.callout.weight(.semibold))
                        .foregroundStyle(PaceColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if selectedCount > 0 {
                        Text(selectedCount.paceFormatted)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(PaceColor.onSelection)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(PaceColor.selectionFill, in: Capsule())
                    }
                    Spacer(minLength: PaceSpacing.xs)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                        .rotationEffect(isExpanded ? .zero : .degrees(-90))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .accessibilityValue(isExpanded
                ? PaceLocalization.text(de: "Aufgeklappt", en: "Expanded", ru: "Развёрнуто")
                : PaceLocalization.text(de: "Zugeklappt", en: "Collapsed", ru: "Свёрнуто"))
            if isExpanded {
                PaceFlowLayout(spacing: PaceSpacing.xs) {
                    ForEach(interests) { interest in
                        chip(interest)
                    }
                }
                .padding(.bottom, PaceSpacing.s)
            }
        }
    }

    private func chip(_ interest: ProfileInterest) -> some View {
        let isSelected = details.isSelected(interest)
        let isDisabled = !isSelected && !details.canAddInterest
        return Button {
            details.toggleInterest(interest)
        } label: {
            Label(interest.title, systemImage: isSelected ? "checkmark" : interest.systemImage)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, PaceSpacing.s)
                .frame(minHeight: 36)
                .foregroundStyle(isSelected ? PaceColor.onSelection : PaceColor.textPrimary)
                .background(isSelected ? PaceColor.selectionFill : PaceColor.fieldBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? PaceColor.accent : PaceColor.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.pacePressable)
        .disabled(isDisabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isDisabled ? PaceLocalization.text(
            de: "Höchstens \(details.interestLimit) Interessen. Entferne zuerst eines.",
            en: "At most \(details.interestLimit) interests. Remove one first.",
            ru: "Не больше \(details.interestLimit) интересов. Сначала убери один."
        ) : "")
    }
}

/// Gewählter Eintrag mit ×: entfernt ihn aus dem Entwurf (gespeichert wird erst mit „Speichern“).
struct ProfileRemovableChip: View {
    let title: String
    let systemImage: String?
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(PaceColor.accent)
                }
                // Eigene Einträge sind nutzergenerierter Text: wörtlich, ohne Markdown.
                Text(verbatim: title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PaceColor.textSecondary)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(PaceColor.textPrimary)
            .padding(.horizontal, PaceSpacing.s)
            .frame(minHeight: 36)
            .background(PaceColor.accentSoft, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.pacePressable)
        .accessibilityLabel(ProfileDetailsTexts.removeInterest(title))
    }
}

// MARK: - Gesprochene Sprachen

/// Eigener kompakter Bereich für gesprochene Sprachen – nie aus der App-Sprache abgeleitet.
struct ProfileLanguagesCard: View {
    @Bindable var details: ProfileDetailsViewModel
    @State private var showsPicker = false

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    PaceCardHeader(ProfileDetailsTexts.spokenLanguages)
                    Spacer()
                    if !details.draftLanguages.isEmpty {
                        Text(ProfileDetailsTexts.languagesHint(selected: details.draftLanguages.count))
                            .font(PaceFont.caption.monospacedDigit())
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                }
                if !details.draftLanguages.isEmpty {
                    PaceFlowLayout(spacing: PaceSpacing.xs) {
                        ForEach(details.draftLanguages, id: \.self) { code in
                            ProfileRemovableChip(title: SpokenLanguageCatalog.name(for: code), systemImage: nil) {
                                details.toggleLanguage(code)
                            }
                        }
                    }
                }
                Button {
                    showsPicker = true
                } label: {
                    Label(
                        details.draftLanguages.isEmpty ? ProfileDetailsTexts.addLanguages : ProfileDetailsTexts.editLanguages,
                        systemImage: "character.bubble"
                    )
                    .font(PaceFont.callout.weight(.semibold))
                    .foregroundStyle(PaceColor.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                ProfileFootnote(text: ProfileDetailsTexts.languagesNote)
            }
        }
        .sheet(isPresented: $showsPicker) {
            ProfileLanguagePicker(details: details)
        }
    }
}

/// Auswahlliste mit Suche (Name in der App-Sprache, auf Englisch oder in der Sprache selbst).
struct ProfileLanguagePicker: View {
    @Bindable var details: ProfileDetailsViewModel
    @State var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: PaceSpacing.s) {
                PaceSearchField(ProfileDetailsTexts.searchLanguages, text: $query)
                    .padding(.horizontal, PaceSpacing.m)
                Text(ProfileDetailsTexts.languagesHint(selected: details.draftLanguages.count))
                    .font(PaceFont.caption.monospacedDigit())
                    .foregroundStyle(PaceColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PaceSpacing.m)
                let codes = SpokenLanguageCatalog.search(query)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if codes.isEmpty {
                            ProfileFootnote(text: ProfileDetailsTexts.noResults)
                                .padding(PaceSpacing.m)
                        }
                        ForEach(codes, id: \.self) { code in
                            let isSelected = details.speaks(code)
                            ProfilePickerRow(
                                title: SpokenLanguageCatalog.name(for: code),
                                subtitle: SpokenLanguageCatalog.nativeName(for: code).flatMap { native in
                                    native == SpokenLanguageCatalog.name(for: code) ? nil : native
                                },
                                isSelected: isSelected,
                                isDisabled: !isSelected && !details.canAddLanguage
                            ) {
                                details.toggleLanguage(code)
                            }
                        }
                    }
                    .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
                    .padding(.horizontal, PaceSpacing.m)
                    .padding(.bottom, PaceSpacing.l)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .padding(.top, PaceSpacing.s)
            .paceScreenBackground()
            .navigationTitle(ProfileDetailsTexts.spokenLanguages)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ProfileDetailsTexts.done) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Land & Kultur

/// Freiwilliger Länder- bzw. Kulturbezug: höchstens ein Land, nur sichtbar, wenn eins gewählt ist.
struct ProfileCountryCard: View {
    @Bindable var details: ProfileDetailsViewModel
    @State private var showsPicker = false

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(ProfileDetailsTexts.country)
                if let code = details.draftCountry {
                    HStack(spacing: PaceSpacing.s) {
                        Text(verbatim: "\(ProfileCountryCatalog.flag(for: code)) \(ProfileCountryCatalog.name(for: code))")
                            .font(PaceFont.body.weight(.semibold))
                            .foregroundStyle(PaceColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: PaceSpacing.xs)
                        Button(ProfileDetailsTexts.edit) { showsPicker = true }
                            .buttonStyle(.paceCompact)
                    }
                    Button(role: .destructive) {
                        details.setCountry(nil)
                    } label: {
                        Text(ProfileDetailsTexts.removeCountry)
                            .font(PaceFont.callout)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                } else {
                    Button {
                        showsPicker = true
                    } label: {
                        Label(ProfileDetailsTexts.chooseCountry, systemImage: "globe.europe.africa")
                            .font(PaceFont.callout.weight(.semibold))
                            .foregroundStyle(PaceColor.accent)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pacePressable)
                }
                ProfileFootnote(text: ProfileDetailsTexts.countryNote)
            }
        }
        .sheet(isPresented: $showsPicker) {
            ProfileCountryPicker(details: details)
        }
    }
}

/// Länderliste mit Suche; Auswahl schließt die Liste.
struct ProfileCountryPicker: View {
    @Bindable var details: ProfileDetailsViewModel
    @State var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: PaceSpacing.s) {
                PaceSearchField(ProfileDetailsTexts.searchCountries, text: $query)
                    .padding(.horizontal, PaceSpacing.m)
                let codes = ProfileCountryCatalog.search(query)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if codes.isEmpty {
                            ProfileFootnote(text: ProfileDetailsTexts.noResults)
                                .padding(PaceSpacing.m)
                        }
                        ForEach(codes, id: \.self) { code in
                            ProfilePickerRow(
                                title: "\(ProfileCountryCatalog.flag(for: code))  \(ProfileCountryCatalog.name(for: code))",
                                subtitle: nil,
                                isSelected: details.draftCountry == code,
                                isDisabled: false
                            ) {
                                details.setCountry(code)
                                dismiss()
                            }
                        }
                    }
                    .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
                    .padding(.horizontal, PaceSpacing.m)
                    .padding(.bottom, PaceSpacing.l)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .padding(.top, PaceSpacing.s)
            .paceScreenBackground()
            .navigationTitle(ProfileDetailsTexts.country)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ProfileDetailsTexts.cancel) { dismiss() }
                }
            }
        }
    }
}

/// Zeile einer Auswahlliste: Titel, optional Untertitel, Häkchen.
struct ProfilePickerRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(PaceFont.body)
                        .foregroundStyle(PaceColor.textPrimary)
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                }
                Spacer(minLength: PaceSpacing.xs)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PaceColor.accent)
                }
            }
            .padding(.horizontal, PaceSpacing.m)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .bottom) {
            Divider().overlay(PaceColor.border).padding(.leading, PaceSpacing.m)
        }
    }
}
