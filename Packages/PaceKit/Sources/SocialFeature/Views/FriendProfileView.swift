import DesignSystem
import PaceCore
import SwiftUI

/// Profil eines Freundes: Namen und Wettbewerbsschritte von heute und dieser Woche – keine weiteren Daten.
struct FriendProfileView: View {
    @State private var viewModel: FriendProfileViewModel
    @State private var confirmsRemoval = false
    @Environment(\.dismiss) private var dismiss

    init(viewModel: @autoclosure () -> FriendProfileViewModel) {
        _viewModel = State(initialValue: viewModel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                header
                switch viewModel.state {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                case .failed(let message):
                    PaceStatusView(systemImage: "wifi.exclamationmark", title: "Profil nicht geladen", message: message, tint: PaceColor.warning) {
                        Button("Erneut versuchen") { Task { await viewModel.load() } }
                            .buttonStyle(.pacePrimary)
                    }
                case .removed:
                    PaceStatusView(
                        systemImage: "person.crop.circle.badge.xmark",
                        title: "Nicht mehr befreundet",
                        message: "Ihr seht eure Schritte nicht mehr."
                    )
                case .loaded(let details):
                    stepsCard(details)
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.danger)
                    }
                    Button(role: .destructive) {
                        confirmsRemoval = true
                    } label: {
                        Text("Freund entfernen")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.paceSecondary)
                    .disabled(viewModel.isRemoving)
                }
            }
            .padding(.horizontal, PaceSpacing.m)
            .padding(.bottom, PaceSpacing.l)
        }
        .refreshable { [viewModel] in await viewModel.load() }
        .paceScreenBackground()
        .navigationTitle(viewModel.profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { [viewModel] in await viewModel.load() }
        .confirmationDialog("Freund entfernen?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("\(viewModel.profile.displayName) entfernen", role: .destructive) {
                Task {
                    await viewModel.remove()
                    if viewModel.state == .removed { dismiss() }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Ihr seht danach eure Schritte nicht mehr. Offene Gruppeneinladungen zwischen euch werden zurückgezogen.")
        }
    }

    private var header: some View {
        PaceCard {
            HStack(spacing: PaceSpacing.m) {
                PaceAvatar(name: viewModel.profile.displayName, seed: viewModel.profile.publicID.uuidString, size: 64)
                VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                    Text(viewModel.profile.displayName)
                        .font(PaceFont.title)
                        .foregroundStyle(PaceColor.textPrimary)
                    Text("@\(viewModel.profile.username)")
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                    if case .loaded(let details) = viewModel.state {
                        Text("Befreundet seit \(details.friendsSince.formatted(.dateTime.day().month(.abbreviated).year().locale(PaceLocale.german)))")
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func stepsCard(_ details: FriendProfileDetails) -> some View {
        PaceCard {
            HStack(spacing: PaceSpacing.s) {
                StepsFact(title: "Heute", value: details.stepsToday)
                Divider().frame(height: 44)
                StepsFact(title: "Diese Woche", value: details.stepsWeek)
            }
        }
    }
}

private struct StepsFact: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
            Text(value.paceFormatted)
                .font(PaceFont.metric(size: 28))
                .monospacedDigit()
                .foregroundStyle(PaceColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Wettbewerbsschritte")
                .font(PaceFont.micro)
                .foregroundStyle(PaceColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
