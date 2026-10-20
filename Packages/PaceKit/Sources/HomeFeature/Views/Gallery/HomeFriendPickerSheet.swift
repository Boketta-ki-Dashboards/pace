import DesignSystem
import PaceCore
import SwiftUI

/// Alle Freunde zur Auswahl für ein Freunde-Widget („Weitere…“).
struct HomeFriendPickerSheet: View {
    let gallery: HomeWidgetGalleryViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            HomeFriendPickerContent(gallery: gallery, onDone: { dismiss() })
                .padding(.horizontal, PaceSpacing.m)
                .padding(.vertical, PaceSpacing.m)
        }
        .paceScreenBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Inhalt der Freundesauswahl ohne Scrollen.
struct HomeFriendPickerContent: View {
    let gallery: HomeWidgetGalleryViewModel
    var onDone: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(PaceLocalization.text(de: "Freunde auswählen", en: "Choose friends", ru: "Выбери друзей"))
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: PaceSpacing.xs)
                Button(HomeTexts.done, action: onDone)
                    .buttonStyle(HomePillButtonStyle())
            }
            Text(gallery.friendIDs.isEmpty ? gallery.allFriendsHint : gallery.friendsHint)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if gallery.friendChoices.isEmpty {
                HomeWidgetHint(
                    systemImage: "person.2",
                    text: PaceLocalization.text(
                        de: "Du hast noch keine Freunde. Füge im Social-Tab Freunde hinzu.",
                        en: "You don't have any friends yet. Add friends in the Social tab.",
                        ru: "У тебя пока нет друзей. Добавь их во вкладке «Друзья»."
                    )
                )
                .padding(.top, PaceSpacing.s)
            } else {
                VStack(spacing: PaceSpacing.xs) {
                    ForEach(gallery.friendChoices) { profile in
                        let isSelected = gallery.isSelected(friend: profile.publicID)
                        Button {
                            gallery.toggleFriend(profile.publicID)
                        } label: {
                            HStack(spacing: PaceSpacing.s) {
                                PaceAvatar(name: profile.displayName, seed: profile.publicID.uuidString, size: 40, image: profile.avatar)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(profile.displayName)
                                        .font(PaceFont.headline)
                                        .foregroundStyle(PaceColor.textPrimary)
                                        .lineLimit(1)
                                    Text(verbatim: "@\(profile.username)")
                                        .font(PaceFont.caption)
                                        .foregroundStyle(PaceColor.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: PaceSpacing.xs)
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.title2)
                                    .foregroundStyle(isSelected ? PaceColor.actionFill : PaceColor.textSecondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, PaceSpacing.s)
                            .frame(minHeight: 56)
                            .background(
                                isSelected ? PaceColor.accentSoft : PaceColor.surface,
                                in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                                    .strokeBorder(isSelected ? PaceColor.accent.opacity(0.4) : PaceColor.border, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pacePressable)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }
}
