import SocialFeature
import Testing

@MainActor
struct SocialViewModelTests {
    @Test func preparesAllSocialAreasWithoutFakeData() {
        let viewModel = SocialViewModel()

        #expect(viewModel.sections.map(\.id) == ["friends", "requests", "groups", "invites"])
        #expect(viewModel.sections.allSatisfy { $0.availability == .comingSoon })
        #expect(Set(viewModel.sections.map(\.id)).count == viewModel.sections.count)
    }
}
