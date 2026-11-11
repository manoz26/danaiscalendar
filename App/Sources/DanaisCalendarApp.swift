import SwiftUI

@main
struct DanaisCalendarApp: App {
    /// The writing engine, one for the whole app.
    @State private var ink: InkController

    init() {
        Chrome.apply()
        AppDiagnostics.start()
        #if DEBUG
        LaunchOptions.prepareTestData()
        #endif
        _ink = State(initialValue: InkController())
    }

    var body: some Scene {
        WindowGroup {
            RootView(ink: ink)
        }
    }
}
