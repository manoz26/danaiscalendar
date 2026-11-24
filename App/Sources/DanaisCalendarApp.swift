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
    /// Her palette, pens, paper and lock (prompt 9), the same on every device.
    @State private var settings: SettingsBook
    /// Face ID / Touch ID / passcode, when she turned it on.
    @State private var lock: AppLock

    init() {
        Chrome.apply()
        AppDiagnostics.start()
        #if DEBUG
        LaunchOptions.prepareTestData()
        #endif
        let settings = SettingsBook()
        #if DEBUG
        settings.applyTestSettingsIfRequested()
        #endif
        let ink = InkController()
        ink.settingsBook = settings
        ink.apply(settings.settings)
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
        journal.newPaper = settings.settings.paper
        let lock = AppLock(mode: settings.settings.lock)
        settings.onChange = { [weak ink, weak journal, weak lock] new in
            ink?.apply(new)
            journal?.newPaper = new.paper
            lock?.mode = new.lock
        }
        _settings = State(initialValue: settings)
        _lock = State(initialValue: lock)
        _journal = State(initialValue: journal)
        _sketches = State(initialValue: sketches)
        _lists = State(initialValue: lists)
        _wishlist = State(initialValue: wishlist)
        _appleCalendar = State(initialValue: CalendarBook())
        let sync = CloudSync(owner: AppSyncOwner(
            ink: ink, birthdays: birthdays, journal: journal, sketches: sketches, lists: lists, wishlist: wishlist,
            settings: settings
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
                    wishlist: wishlist, appleCalendar: appleCalendar, sync: sync, settings: settings, lock: lock
                )
                .lockCover(lock)
            } else {
                RootView(
                    ink: ink, birthdays: birthdays, journal: journal, sketches: sketches, lists: lists,
                    wishlist: wishlist, appleCalendar: appleCalendar, sync: sync, settings: settings, lock: lock
                )
                .lockCover(lock)
            }
        }
    }
}
