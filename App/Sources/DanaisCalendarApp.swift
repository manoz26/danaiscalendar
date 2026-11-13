import SwiftUI

@main
struct DanaisCalendarApp: App {
    /// The writing engine, one for the whole app.
    @State private var ink: InkController
    /// Friends' birthdays, shown on the month pages.
    @State private var birthdays: BirthdayBook

    init() {
        Chrome.apply()
        AppDiagnostics.start()
        #if DEBUG
        LaunchOptions.prepareTestData()
        #endif
        _ink = State(initialValue: InkController())
        let birthdays = BirthdayBook()
        #if DEBUG
        birthdays.addSamplesIfRequested()
        #endif
        _birthdays = State(initialValue: birthdays)
    }

    var body: some Scene {
        WindowGroup {
            RootView(ink: ink, birthdays: birthdays)
        }
    }
}
