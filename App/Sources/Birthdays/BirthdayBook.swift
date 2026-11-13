import Foundation
import Observation
import PlannerCore

/// Friends' birthdays (the gift in the top bar). Kept in memory and saved to
/// `Application Support/Lists/birthdays.json` right after each change, off the main
/// thread, one save at a time; each save replaces the file in one step. The month pages
/// mark the days and write them in their notes.
///
/// Names are the user's personal content: they are never written to the log.
@MainActor
@Observable
final class BirthdayBook {
    private(set) var birthdays: [Birthday]

    @ObservationIgnored private let store: LocalBirthdayStore
    @ObservationIgnored private let queue = DispatchQueue(label: "DanaisCalendar.Birthdays", qos: .userInitiated)

    nonisolated static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Lists", directoryHint: .isDirectory)
    }

    init(folder: URL = BirthdayBook.defaultFolder) {
        let store = LocalBirthdayStore(folder: folder)
        self.store = store
        birthdays = Self.read(from: store)
    }

    /// Adds a birthday, or replaces the one with the same id. Names are trimmed; a
    /// birthday without a name or with an impossible day is ignored.
    func save(_ birthday: Birthday) {
        var birthday = birthday
        birthday.name = birthday.trimmedName
        guard birthday.isValid else {
            AppLog.warning("Ignored an incomplete birthday")
            return
        }
        if let index = birthdays.firstIndex(where: { $0.id == birthday.id }) {
            birthdays[index] = birthday
        } else {
            birthdays.append(birthday)
        }
        persist()
    }

    func delete(_ id: UUID) {
        guard birthdays.contains(where: { $0.id == id }) else { return }
        birthdays.removeAll { $0.id == id }
        persist()
    }

    /// Waits until every change so far is on disk (the app is going to the background).
    func waitUntilSaved() {
        queue.sync {}
    }

    private func persist() {
        let snapshot = birthdays
        let store = store
        queue.async {
            do {
                try store.save(snapshot)
            } catch {
                AppLog.error("Could not save the birthdays", error)
            }
        }
    }

    /// Never fails: an unreadable file is logged and set aside (kept, not deleted), and
    /// the list starts empty.
    private static func read(from store: LocalBirthdayStore) -> [Birthday] {
        do {
            let birthdays = try store.load()
            AppLog.info("Birthdays: \(birthdays.count)")
            return birthdays
        } catch {
            AppLog.error("Could not read the birthdays", error)
            do {
                if let kept = try store.setAside() {
                    AppLog.warning("Kept the unreadable birthdays file as \(kept.lastPathComponent); the list starts empty")
                }
            } catch {
                AppLog.error("Could not set aside the birthdays file", error)
            }
            return []
        }
    }

    #if DEBUG
    /// `-DCSampleBirthdays YES`: a few made-up birthdays for the UI tests, if there are none.
    func addSamplesIfRequested() {
        guard LaunchOptions.sampleBirthdays, birthdays.isEmpty else { return }
        let greek = AppLocale.current.language.languageCode?.identifier == "el"
        let samples: [(String, String, Int, Int)] = [
            ("Ελένη", "Helen", 3, 7),
            ("Νίκος", "Nick", 3, 21),
            ("Μαρία", "Mary", 3, 21),
            ("Μάνος", "Manos", 11, 13),
            ("Άννα", "Anna", 2, 29),
        ]
        for (greekName, englishName, month, day) in samples {
            birthdays.append(Birthday(name: greek ? greekName : englishName, month: month, day: day))
        }
        persist()
        AppLog.info("Sample birthdays added")
    }
    #endif
}
