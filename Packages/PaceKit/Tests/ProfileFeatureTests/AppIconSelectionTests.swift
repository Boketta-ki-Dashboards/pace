import Foundation
import PaceCore
import PaceTestSupport
import ProfileFeature
import Testing

@MainActor
struct AppIconSelectionTests {
    private func makeViewModel(icons: AppIconSettingStub) -> ProfileViewModel {
        let profile = Fixtures.profile()
        let regions = RegionRepositoryStub()
        let store = ProfileStore(
            profile: profile,
            profiles: ProfileRepositoryStub { $0.profiles[profile.id] = profile },
            regions: regions,
            cache: InMemoryProfileCache()
        )
        return ProfileViewModel(store: store, regions: regions, appIcons: icons, searchDebounce: .zero)
    }

    @Test func startsWithTheIconThatIsCurrentlySet() {
        #expect(makeViewModel(icons: AppIconSettingStub()).appIcon == .automatic)
        #expect(makeViewModel(icons: AppIconSettingStub { $0.currentAlternateIconName = "AppIconDark" }).appIcon == .dark)
        #expect(makeViewModel(icons: AppIconSettingStub { $0.currentAlternateIconName = "AppIconLight" }).appIcon == .light)
        // Ein unbekannter Name (z. B. aus einer älteren Version) gilt als primäres Icon.
        #expect(makeViewModel(icons: AppIconSettingStub { $0.currentAlternateIconName = "Old" }).appIcon == .automatic)
    }

    @Test func selectingAnIconSetsTheMatchingAlternateIcon() async {
        let icons = AppIconSettingStub()
        let viewModel = makeViewModel(icons: icons)

        await viewModel.selectAppIcon(.dark)
        await viewModel.selectAppIcon(.light)
        await viewModel.selectAppIcon(.automatic)

        #expect(icons.state.current.requestedNames == ["AppIconDark", "AppIconLight", nil])
        #expect(viewModel.appIcon == .automatic)
        #expect(viewModel.appIconError == nil)
        #expect(!viewModel.isChangingAppIcon)
    }

    @Test func selectingTheCurrentIconDoesNotTriggerTheSystemNotice() async {
        let icons = AppIconSettingStub { $0.currentAlternateIconName = "AppIconDark" }
        let viewModel = makeViewModel(icons: icons)

        await viewModel.selectAppIcon(.dark)

        #expect(icons.state.current.requestedNames.isEmpty)
    }

    @Test func failureKeepsTheActualIconAndShowsAnError() async {
        let icons = AppIconSettingStub { $0.error = CocoaError(.featureUnsupported) }
        let viewModel = makeViewModel(icons: icons)

        await viewModel.selectAppIcon(.dark)

        #expect(viewModel.appIcon == .automatic)
        #expect(viewModel.appIconError != nil)

        icons.state.withLock { $0.error = nil }
        await viewModel.selectAppIcon(.dark)
        #expect(viewModel.appIcon == .dark)
        #expect(viewModel.appIconError == nil)
    }

    @Test func unsupportedDevicesDoNotChangeTheIcon() async {
        let icons = AppIconSettingStub { $0.supportsAlternateIcons = false }
        let viewModel = makeViewModel(icons: icons)

        await viewModel.selectAppIcon(.light)

        #expect(!viewModel.supportsAppIconChange)
        #expect(icons.state.current.requestedNames.isEmpty)
        #expect(viewModel.appIcon == .automatic)
    }

    @Test func choicesMapToTheAssetCatalogNames() {
        #expect(AppIconChoice.allCases.map(\.alternateIconName) == [nil, "AppIconLight", "AppIconDark"])
        #expect(AppIconChoice.allCases.map(\.title) == ["Automatisch", "Hell", "Dunkel"])
    }
}
