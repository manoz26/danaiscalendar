import SwiftUI
import UIKit

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
    /// The photos of things she would like to buy.
    @State private var wishlist: WishlistBook
    /// The events of the Apple Calendar (read, never copied).
    @State private var appleCalendar: CalendarBook
    /// iCloud: the same pages, lists and photos on every device.
    @State private var sync: CloudSync

    init() {
        Chrome.apply()
        AppDiagnostics.start()
        #if DEBUG
        LaunchOptions.prepareTestData()
        #endif
        let ink = InkController()
        _ink = State(initialValue: ink)
        let birthdays = BirthdayBook()
        #if DEBUG
        birthdays.addSamplesIfRequested()
        #endif
        _birthdays = State(initialValue: birthdays)
        let journal = JournalBook()
        let sketches = SketchBook()
        let lists = ListBook()
        let wishlist = WishlistBook()
        #if DEBUG
        journal.addSamplesIfRequested()
        sketches.addSamplesIfRequested()
        lists.addSamplesIfRequested()
        wishlist.addSamplesIfRequested()
        #endif
        _journal = State(initialValue: journal)
        _sketches = State(initialValue: sketches)
        _lists = State(initialValue: lists)
        _wishlist = State(initialValue: wishlist)
        _appleCalendar = State(initialValue: CalendarBook())
        let sync = CloudSync(owner: AppSyncOwner(
            ink: ink, birthdays: birthdays, journal: journal, sketches: sketches, lists: lists, wishlist: wishlist
        ))
        sync.start()
        _sync = State(initialValue: sync)
    }

    var body: some Scene {
        WindowGroup {
            // The iPad writes; the iPhone shows what was written and adds typed things.
            if UIDevice.current.userInterfaceIdiom == .phone {
                PhoneRootView(
                    ink: ink, birthdays: birthdays, journal: journal, sketches: sketches, lists: lists,
                    wishlist: wishlist, appleCalendar: appleCalendar, sync: sync
                )
            } else {
                RootView(
                    ink: ink, birthdays: birthdays, journal: journal, sketches: sketches, lists: lists,
                    wishlist: wishlist, appleCalendar: appleCalendar, sync: sync
                )
            }
        }
    }
}
