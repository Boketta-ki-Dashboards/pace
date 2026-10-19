import Foundation
import PaceCore
import Testing

struct PaceLinkTests {
    @Test func profileLinkRoundTrips() throws {
        let link = PaceLink.profile(username: "Niklas_7")
        #expect(link.url.absoluteString == "pace://u/Niklas_7")
        #expect(PaceLink(url: link.url) == link)
    }

    @Test func rejectsForeignAndInvalidLinks() throws {
        #expect(PaceLink(url: try #require(URL(string: "https://example.com/u/niklas"))) == nil)
        #expect(PaceLink(url: try #require(URL(string: "pace://x/niklas"))) == nil)
        #expect(PaceLink(url: try #require(URL(string: "pace://u/"))) == nil)
        #expect(PaceLink(url: try #require(URL(string: "pace://u/ni"))) == nil)
        #expect(PaceLink(url: try #require(URL(string: "pace://u/niklas/extra"))) == nil)
        #expect(PaceLink(url: try #require(URL(string: "pace://u/n%C3%A4me"))) == nil)
    }

    @Test func schemeAndHostAreCaseInsensitive() throws {
        #expect(PaceLink(url: try #require(URL(string: "PACE://U/niklas"))) == .profile(username: "niklas"))
    }
}
