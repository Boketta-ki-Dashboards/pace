import AppFeature
import SwiftUI

@main
struct PaceApp: App {
    @State private var router = AppRouter(dependencies: .live())

    var body: some Scene {
        WindowGroup {
            RootView(router: router)
        }
    }
}
