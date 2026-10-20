import DesignSystem
import PaceCore
import SwiftUI

/// Suchfeld und Trefferliste für Gemeinden. Ohne eigene ScrollView – der Aufrufer bettet sie ein.
public struct RegionSearchView: View {
    private let viewModel: RegionSearchViewModel

    @State private var query = ""

    public init(viewModel: RegionSearchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            searchField
            // Die Auswahl bleibt immer sichtbar, auch während einer neuen Suche – gespeichert wird genau sie.
            if let selection = viewModel.selection {
                VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                    Text(PaceLocalization.text(de: "Ausgewählt", en: "Selected", ru: "Выбрано"))
                        .font(PaceFont.caption.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                    RegionResultRow(hierarchy: selection, isSelected: true) {}
                }
            }
            content
        }
        .task(id: query) { [viewModel, query] in
            await viewModel.search(query)
        }
    }

    private var searchField: some View {
        HStack(spacing: PaceSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PaceColor.textSecondary)
                .accessibilityHidden(true)
            TextField(
                PaceLocalization.text(de: "Gemeinde oder Stadt suchen", en: "Search municipality or city", ru: "Найти город или общину"),
                text: $query
            )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PaceColor.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PaceLocalization.text(de: "Suche löschen", en: "Clear search", ru: "Очистить поиск"))
            }
        }
        .padding(PaceSpacing.s)
        .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.button, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            if viewModel.selection == nil {
                hint(PaceLocalization.text(
                    de: "Gib mindestens zwei Buchstaben ein, z. B. „Pfungstadt“.",
                    en: "Enter at least two letters, e.g. “Pfungstadt”.",
                    ru: "Введи хотя бы две буквы, например «Pfungstadt»."
                ))
            }

        case .searching:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, PaceSpacing.m)

        case .results(let results):
            VStack(spacing: PaceSpacing.xxs) {
                ForEach(results) { hierarchy in
                    RegionResultRow(hierarchy: hierarchy, isSelected: hierarchy.id == viewModel.selection?.id) {
                        viewModel.select(hierarchy)
                    }
                }
            }

        case .noResults(let query):
            hint(PaceLocalization.text(
                de: "Keine Gemeinde gefunden für „\(query)“. Prüfe die Schreibweise.",
                en: "No municipality found for “\(query)”. Check the spelling.",
                ru: "По запросу «\(query)» ничего не найдено. Проверь написание."
            ))

        case .failed(let message):
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                hint(message)
                Button(PaceLocalization.text(de: "Erneut versuchen", en: "Try again", ru: "Повторить")) {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.paceSecondary)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(PaceFont.callout)
            .foregroundStyle(PaceColor.textSecondary)
            .padding(.vertical, PaceSpacing.xs)
    }
}

/// Ein Treffer: Gemeinde, darunter Bundesland und Kreis.
private struct RegionResultRow: View {
    let hierarchy: RegionHierarchy
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: PaceSpacing.s) {
                VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                    Text(hierarchy.municipality.name)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                    Text(hierarchy.subtitle)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PaceColor.accent)
                }
            }
            .padding(PaceSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? PaceColor.accent.opacity(0.12) : PaceColor.surface,
                in: RoundedRectangle(cornerRadius: PaceRadius.button, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
