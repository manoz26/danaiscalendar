import SwiftUI

@main
struct DanaisCalendarApp: App {
    /// The writing engine, one for the whole app.
    @State private var ink: InkController
    /// Friends' birthdays, shown on the month pages.
    @State private var birthdays: BirthdayBook
    /// The journal's pages, the sketches and the typed lists.
    @State private var journal: JournalBook
    @State private var sketches: SketchBook
    @State private var lists: ListBook

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
        let journal = JournalBook()
        let sketches = SketchBook()
        let lists = ListBook()
        #if DEBUG
        journal.addSamplesIfRequested()
        sketches.addSamplesIfRequested()
        lists.addSamplesIfRequested()
        #endif
        _journal = State(initialValue: journal)
        _sketches = State(initialValue: sketches)
        _lists = State(initialValue: lists)
    }

    var body: some Scene {
        WindowGroup {
            RootView(ink: ink, birthdays: birthdays, journal: journal, sketches: sketches, lists: lists)
        }
    }
}
