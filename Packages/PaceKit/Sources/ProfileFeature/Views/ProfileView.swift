import ActivityFeature
import DesignSystem
import PaceCore
import RegionFeature
import SwiftUI

/// Profil-Tab: Profil, persönliche Aktivität, Region, Ranking-Sichtbarkeit, Darstellung und die Kategorien der
/// Einstellungen mit eigenen Unterseiten.
public struct ProfileView: View {
    @Bindable private var viewModel: ProfileViewModel

    public init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack(path: $viewModel.path) {
            ScrollView {
                ProfileContent(viewModel: viewModel, onOpen: { viewModel.open($0) })
                    .padding(.horizontal, PaceSpacing.m)
                    .padding(.bottom, PaceSpacing.l)
                    .paceTabRoot(isAtRoot: viewModel.path.isEmpty) { viewModel.path.removeAll() }
            }
            .refreshable { [viewModel] in await viewModel.load() }
            .paceScreenBackground()
            .paceRootPage()
            .navigationDestination(for: ProfileRoute.self) { route in
                destination(for: route, backTitle: backTitle(for: route))
            }
        }
        .task { [viewModel] in await viewModel.load() }
        .task { [viewModel] in await viewModel.loadActivity() }
        .sheet(isPresented: $viewModel.isEditingGoal) {
            if let goals = viewModel.streak?.goals {
                StepGoalSheet(goals: goals)
            }
        }
        .sheet(item: regionSheetBinding) { search in
            RegionChangeSheet(viewModel: viewModel, search: search)
        }
    }

    @ViewBuilder
    private func destination(for route: ProfileRoute, backTitle: String) -> some View {
        switch route {
        case .account:
            AccountPage(viewModel: viewModel.account, backTitle: backTitle)
        case .appearance:
            AppearancePage(viewModel: viewModel, backTitle: backTitle)
        case .language:
            LanguagePage(viewModel: viewModel, backTitle: backTitle)
        case .privacy:
            PrivacyPage(viewModel: viewModel, backTitle: backTitle)
        case .notifications:
            NotificationsPage(viewModel: viewModel.notifications, backTitle: backTitle)
        case .social:
            SocialSettingsPage(viewModel: viewModel, backTitle: backTitle)
        case .dataPrivacy:
            DataPrivacyPage(viewModel: viewModel, backTitle: backTitle)
        case .deleteAccount:
            DeleteAccountPage(viewModel: viewModel.dataPrivacy, backTitle: backTitle)
        case .help:
            HelpPage(viewModel: viewModel, backTitle: backTitle)
        case .feedback(let kind):
            FeedbackPage(viewModel: viewModel.makeFeedback(kind), backTitle: backTitle)
        case .legal:
            LegalPage(backTitle: backTitle) { viewModel.open($0) }
        case .legalDocument(let document):
            LegalDocumentPage(document: document, backTitle: backTitle)
        case .statistics(let statisticsRoute):
            if let statistics = viewModel.statistics(for: statisticsRoute) {
                StatisticsView(viewModel: statistics, backTitle: backTitle)
            }
        case .activityHealth:
            ActivityHealthPage(viewModel: viewModel, backTitle: backTitle)
        case .calorieEstimation:
            CalorieEstimationPage(settings: viewModel.bodyMetrics, backTitle: backTitle)
        case .dataHelpLegal:
            DataHelpLegalPage(backTitle: backTitle) { viewModel.open($0) }
        }
    }

    /// Zurück führt zur vorherigen Seite bzw. zum Profil.
    private func backTitle(for route: ProfileRoute) -> String {
        guard let index = viewModel.path.firstIndex(of: route), index > 0 else { return ProfileTexts.profileTitle }
        return viewModel.path[index - 1].title
    }

    /// Mit `sheet(item:)` behält SwiftUI den Inhalt während der Schließen-Animation.
    private var regionSheetBinding: Binding<RegionSearchViewModel?> {
        Binding(
            get: { [viewModel] in viewModel.regionSearch },
            set: { [viewModel] search in
                if search == nil { viewModel.cancelRegionChange() }
            }
        )
    }
}

/// Inhalt des Profil-Tabs (ohne Navigation und Scrollen).
struct ProfileContent: View {
    let viewModel: ProfileViewModel
    var onOpen: (ProfileRoute) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            header
            identityCard
            if viewModel.goalText != nil {
                activityCard
            }
            regionCard
            rankingsCard
            appearanceCard
            settingsSections
            footer
        }
    }

    // MARK: Kopf und Profil

    private var header: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
            PaceWordmark(height: 33)
            Text(ProfileTexts.profileTitle)
                .font(.system(.title, weight: .bold))
                .foregroundStyle(PaceColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, PaceSpacing.xs)
        .padding(.bottom, PaceSpacing.xxs)
    }

    private var identityCard: some View {
        PaceCard {
            HStack(alignment: .center, spacing: PaceSpacing.s) {
                Button {
                    onOpen(.account)
                } label: {
                    HStack(spacing: PaceSpacing.m) {
                        PaceAvatar(name: viewModel.displayName, seed: viewModel.avatarSeed, size: 68, image: viewModel.avatar)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.displayName)
                                .font(PaceFont.title)
                                .foregroundStyle(PaceColor.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            Text(viewModel.username)
                                .font(PaceFont.callout)
                                .foregroundStyle(PaceColor.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                .accessibilityElement(children: .combine)
                .accessibilityHint(PaceLocalization.text(
                    de: "Öffnet Konto & Profil",
                    en: "Opens account & profile",
                    ru: "Открывает аккаунт и профиль"
                ))

                ShareLink(
                    item: viewModel.share.url,
                    subject: Text(viewModel.share.subject),
                    message: Text(viewModel.share.message)
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(PaceIconButtonStyle(size: 40))
                .accessibilityLabel(ProfileTexts.shareProfile)
            }
        }
    }

    // MARK: Aktivität

    private var activityCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(PaceLocalization.text(de: "Deine Aktivität", en: "Your activity", ru: "Твоя активность"))

                Button {
                    viewModel.isEditingGoal = true
                } label: {
                    ActivityRow(
                        systemImage: "scope",
                        title: PaceLocalization.text(de: "Tagesziel", en: "Daily goal", ru: "Дневная цель"),
                        value: viewModel.goalText ?? ProfileTexts.placeholder,
                        showsChevron: true
                    )
                }
                .buttonStyle(.pacePressable)
                .accessibilityHint(PaceLocalization.text(de: "Tagesziel ändern", en: "Change daily goal", ru: "Изменить дневную цель"))

                PaceTile {
                    HStack(spacing: PaceSpacing.s) {
                        PaceStreakFlame(
                            isActive: (viewModel.streakSummary?.currentDays ?? 0) > 0,
                            isTodayReached: viewModel.streakSummary?.isTodayReached ?? false,
                            size: 36
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PaceLocalization.text(de: "Serie", en: "Streak", ru: "Серия")
                                + ": " + (viewModel.streakSummary?.currentText ?? ProfileTexts.placeholder))
                                .font(PaceFont.headline)
                                .foregroundStyle(PaceColor.textPrimary)
                            Text(viewModel.recordText)
                                .font(PaceFont.caption)
                                .foregroundStyle(PaceColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, PaceSpacing.xxs)
                }
                .accessibilityElement(children: .combine)

                if viewModel.showsStatistics {
                    Button {
                        onOpen(.statistics(StatisticsRoute(period: .week, metric: .steps)))
                    } label: {
                        ActivityRow(
                            systemImage: "chart.bar.xaxis",
                            title: PaceLocalization.text(de: "Statistik", en: "Statistics", ru: "Статистика"),
                            value: PaceLocalization.text(de: "Tag · Woche · Monat", en: "Day · Week · Month", ru: "День · Неделя · Месяц"),
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.pacePressable)
                }

                ProfileFootnote(text: PaceLocalization.text(
                    de: "Tagesziel und Serie bleiben auf deinem iPhone. Ein neues Ziel gilt ab heute.",
                    en: "Your daily goal and streak stay on your iPhone. A new goal applies from today.",
                    ru: "Дневная цель и серия хранятся на iPhone. Новая цель действует с сегодняшнего дня."
                ))
            }
        }
    }

    // MARK: Region und Rankings

    private var regionCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(PaceLocalization.text(de: "Deine Region", en: "Your region", ru: "Твой регион"))
                VStack(spacing: PaceSpacing.xs) {
                    ProfileInfoRow(
                        systemImage: "building.2",
                        title: PaceLocalization.text(de: "Gemeinde", en: "Municipality", ru: "Муниципалитет"),
                        value: viewModel.municipalityName ?? ProfileTexts.placeholder
                    )
                    ProfileInfoRow(
                        systemImage: "map",
                        title: PaceLocalization.text(de: "Kreis", en: "District", ru: "Район"),
                        value: viewModel.districtName ?? ProfileTexts.placeholder
                    )
                    ProfileInfoRow(
                        systemImage: "flag",
                        title: PaceLocalization.text(de: "Bundesland", en: "State", ru: "Земля"),
                        value: viewModel.stateName ?? ProfileTexts.placeholder
                    )
                }
                ProfileFootnote(text: viewModel.regionLoadFailed
                    ? PaceLocalization.text(
                        de: "Die Region konnte nicht geladen werden. Ziehe nach unten, um es erneut zu versuchen.",
                        en: "Your region couldn't be loaded. Pull down to try again.",
                        ru: "Не удалось загрузить регион. Потяни вниз, чтобы попробовать снова."
                    )
                    : PaceLocalization.text(
                        de: "Pace speichert nur deine Gemeinde, keinen Standort.",
                        en: "Pace only stores your municipality, never your location.",
                        ru: "Pace хранит только твой муниципалитет, а не местоположение."
                    ))
                Button(PaceLocalization.text(de: "Region ändern", en: "Change region", ru: "Изменить регион")) {
                    viewModel.beginRegionChange()
                }
                .buttonStyle(.paceSecondary)
            }
        }
    }

    private var rankingsCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(ProfileTexts.rankingVisibilityTitle)
                RankingVisibilityControl(viewModel: viewModel)
            }
        }
    }

    // MARK: Darstellung

    private var appearanceCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(ProfileRoute.appearance.title)
                AppearancePicker(viewModel: viewModel)
                Button {
                    onOpen(.appearance)
                } label: {
                    ActivityRow(
                        systemImage: "app.badge",
                        title: PaceLocalization.text(de: "App-Icon", en: "App icon", ru: "Значок приложения"),
                        value: viewModel.appIcon.title,
                        showsChevron: true
                    )
                }
                .buttonStyle(.pacePressable)
            }
        }
    }

    // MARK: Einstellungen

    /// Zentrale Einstellungen in sieben Kategorien (wie eine native iOS-Einstellungsseite). Jede Kategorie öffnet genau
    /// eine Seite; schon offene Seiten werden nicht erneut aufgelegt (``ProfileViewModel/open(_:)``).
    private var settingsSections: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            ProfileSectionTitle(PaceLocalization.text(de: "Einstellungen", en: "Settings", ru: "Настройки"))
            ProfileSettingsRow(
                systemImage: "person.crop.circle",
                title: ProfileRoute.account.title,
                subtitle: PaceLocalization.text(
                    de: "Name, Benutzername, Profilbild, Konto",
                    en: "Name, username, profile picture, account",
                    ru: "Имя, имя пользователя, фото, аккаунт"
                )
            ) { onOpen(.account) }
            ProfileSettingsRow(
                systemImage: "hand.raised",
                title: ProfileRoute.privacy.title,
                subtitle: PaceLocalization.text(
                    de: "Sichtbarkeit, Rankings, blockierte Personen",
                    en: "Visibility, rankings, blocked people",
                    ru: "Видимость, рейтинги, заблокированные"
                )
            ) { onOpen(.privacy) }
            ProfileSettingsRow(
                systemImage: "bell",
                title: ProfileRoute.notifications.title,
                subtitle: PaceLocalization.text(
                    de: "Tagesziel-Erinnerungen, Chat-Hinweise",
                    en: "Daily goal reminders, chat notices",
                    ru: "Напоминания о цели, уведомления чата"
                ),
                value: viewModel.notifications.reminderSummary
            ) { onOpen(.notifications) }
            ProfileSettingsRow(
                systemImage: "heart.text.square",
                title: ProfileRoute.activityHealth.title,
                subtitle: PaceLocalization.text(
                    de: "Apple Health, Tagesziel, Kalorienschätzung",
                    en: "Apple Health, daily goal, calorie estimate",
                    ru: "«Здоровье», цель на день, оценка калорий"
                )
            ) { onOpen(.activityHealth) }
            ProfileSettingsRow(
                systemImage: "paintpalette",
                title: ProfileRoute.appearance.title,
                subtitle: PaceLocalization.text(
                    de: "Hell, Dunkel, App-Icon, Sprache",
                    en: "Light, dark, app icon, language",
                    ru: "Светлая, тёмная, значок, язык"
                ),
                value: viewModel.languageSummary
            ) { onOpen(.appearance) }
            ProfileSettingsRow(
                systemImage: "person.2",
                title: ProfileRoute.social.title,
                subtitle: PaceLocalization.text(
                    de: "Anfragen, Einladungen, Chats, Gruppen",
                    en: "Requests, invitations, chats, groups",
                    ru: "Запросы, приглашения, чаты, группы"
                )
            ) { onOpen(.social) }
            ProfileSettingsRow(
                systemImage: "lock.shield",
                title: ProfileRoute.dataHelpLegal.title,
                subtitle: PaceLocalization.text(
                    de: "Datenexport, Konto löschen, Hilfe, Rechtliches",
                    en: "Data export, delete account, help, legal",
                    ru: "Экспорт, удаление аккаунта, помощь, право"
                )
            ) { onOpen(.dataHelpLegal) }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !viewModel.appVersion.isEmpty {
            Text(ProfileTexts.versionText(viewModel.appVersion))
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, PaceSpacing.s)
        }
    }
}

/// Schalter „In regionalen Rankings erscheinen“ mit Fehler und Erklärung (Profil und Privatsphäre).
struct RankingVisibilityControl: View {
    let viewModel: ProfileViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            ProfileToggleTile(
                title: PaceLocalization.text(
                    de: "In regionalen Rankings erscheinen",
                    en: "Appear in regional rankings",
                    ru: "Показывать меня в региональных рейтингах"
                ),
                isOn: viewModel.participationToggleValue,
                isHighlighted: viewModel.regionalLeaderboardEnabled,
                isDisabled: viewModel.isUpdatingParticipation
            ) { enabled in
                Task { await viewModel.setRegionalLeaderboardEnabled(enabled) }
            }
            if let errorMessage = viewModel.errorMessage {
                ProfileFootnote(text: errorMessage, isError: true)
            }
            ProfileFootnote(text: viewModel.regionalLeaderboardEnabled
                ? PaceLocalization.text(
                    de: "Andere sehen in den Rankings deiner Regionen deinen Anzeigenamen, deinen Benutzernamen und deine Wettbewerbsschritte.",
                    en: "Others see your display name, username and competition steps in the rankings of your regions.",
                    ru: "В рейтингах твоих регионов другие видят твоё отображаемое имя, имя пользователя и шаги для соревнований."
                )
                : PaceLocalization.text(
                    de: "Du siehst die Rankings, erscheinst selbst aber nicht darin.",
                    en: "You can see the rankings but don't appear in them yourself.",
                    ru: "Ты видишь рейтинги, но сам в них не отображаешься."
                ))
        }
    }
}

/// Auswahl Automatisch/Hell/Dunkel – wirkt sofort auf die ganze App.
struct AppearancePicker: View {
    let viewModel: ProfileViewModel

    var body: some View {
        PaceSegmentedControl(
            options: AppearancePreference.allCases.map { (value: $0, title: $0.title) },
            selection: Binding(
                get: { [appearance = viewModel.appearance] in appearance },
                set: { [viewModel] appearance in viewModel.setAppearance(appearance) }
            )
        )
    }
}

/// Antippbare Zeile mit Symbol, Bezeichnung und Wert.
struct ActivityRow: View {
    let systemImage: String
    let title: String
    let value: String
    var showsChevron = false

    var body: some View {
        PaceTile {
            HStack(spacing: PaceSpacing.s) {
                Image(systemName: systemImage)
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: PaceSpacing.xs)
                Text(value)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, PaceSpacing.xxs)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Neue Gemeinde suchen und speichern.
private struct RegionChangeSheet: View {
    let viewModel: ProfileViewModel
    let search: RegionSearchViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaceSpacing.l) {
                    RegionSearchView(viewModel: search)
                    if let error = viewModel.regionChangeError {
                        Text(error)
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.danger)
                    }
                    Text(viewModel.regionalLeaderboardEnabled
                        ? PaceLocalization.text(
                            de: "Du trittst danach in den Rankings der neuen Region an.",
                            en: "You'll then compete in the rankings of your new region.",
                            ru: "После этого ты будешь участвовать в рейтингах нового региона."
                        )
                        : PaceLocalization.text(
                            de: "Deine Einstellung zu regionalen Rankings bleibt unverändert.",
                            en: "Your regional ranking setting stays the same.",
                            ru: "Настройка региональных рейтингов не изменится."
                        ))
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                    RegionPrivacyNotice()
                }
                .padding(PaceSpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .paceScreenBackground()
            .navigationTitle(PaceLocalization.text(de: "Region ändern", en: "Change region", ru: "Изменить регион"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ProfileTexts.cancel) { viewModel.cancelRegionChange() }
                        .disabled(viewModel.isSavingRegion)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSavingRegion {
                        ProgressView()
                    } else {
                        Button(ProfileTexts.save) {
                            Task { await viewModel.saveRegionChange() }
                        }
                        .disabled(!viewModel.canSaveRegion)
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSavingRegion)
    }
}
