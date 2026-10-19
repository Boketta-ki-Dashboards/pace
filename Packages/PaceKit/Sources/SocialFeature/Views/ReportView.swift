import DesignSystem
import PaceCore
import SwiftUI

/// Meldung einer Person oder Gruppe an das Pace-Team: Grund wählen, optional Details, senden.
struct ReportView: View {
    @State private var model: ReportViewModel
    private let social: SocialViewModel
    @Environment(\.dismiss) private var dismiss

    init(model: ReportViewModel, social: SocialViewModel) {
        _model = State(initialValue: model)
        self.social = social
    }

    var body: some View {
        ReportContent(model: model, social: social) {
            Task {
                if await model.send() { dismiss() }
            }
        }
        .socialSubpageScroll()
    }
}

/// Inhalt der Meldung mit Kopfzeile (ohne Scrollen) – auch für Snapshot-Tests.
struct ReportContent: View {
    @Bindable var model: ReportViewModel
    let social: SocialViewModel
    var onSend: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: SocialText.social, title: model.subject.title, subtitle: model.subject.subtitle)
            if let notice = social.notice, notice.isError {
                NoticeBanner(notice: notice) { social.dismissNotice() }
            }
            SocialSectionTitle(SocialText.reportReasonPrompt)
            ForEach(ReportReason.allCases) { reason in
                SocialSelectableRow(
                    title: reason.title,
                    isSelected: model.reason == reason,
                    action: { model.reason = reason }
                ) {
                    EmptyView()
                }
            }
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                TextField(SocialText.reportDetailsPlaceholder, text: $model.details, axis: .vertical)
                    .lineLimit(3...6)
                    .font(PaceFont.body)
                    .padding(PaceSpacing.s)
                    .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(SocialText.charactersLeft(model.remainingCharacters))
                    .font(PaceFont.micro)
                    .foregroundStyle(model.remainingCharacters < 0 ? PaceColor.danger : PaceColor.textSecondary)
            }
            .padding(.top, PaceSpacing.xs)
            Text(SocialText.reportInfo)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onSend) {
                if model.isSending {
                    ProgressView().tint(PaceColor.onAccent)
                } else {
                    Text(SocialText.sendReport)
                }
            }
            .buttonStyle(.pacePrimary)
            .disabled(!model.canSend)
            .padding(.top, PaceSpacing.xs)
        }
    }
}
