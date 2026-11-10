import SwiftUI

@main
struct DanaisCalendarApp: App {
    init() {
        Chrome.apply()
        AppDiagnostics.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
