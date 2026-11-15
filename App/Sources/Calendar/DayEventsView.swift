import PlannerCore
import SwiftUI
import UIKit

/// A day's sheet (a finger on a day of the month or week page): its events of the Apple
/// Calendar, and + for a new one; tap one to change or delete it. Before access is given,
/// it explains and has the button that asks for it; when access was refused, how to allow it.
struct DayEventsView: View {
    let book: CalendarBook
    let day: PlannerDate
    let now: Date

    @Environment(\.dismiss) private var dismiss
    @State private var editing: EventEditorTarget?

    var body: some View {
        let locale = AppLocale.current
        NavigationStack {
            Group {
                switch book.access {
                case .allowed:
                    eventList
                case .notAsked:
                    CalendarConnectPrompt(book: book)
                case .writeOnly, .denied, .restricted:
                    CalendarNotAllowed()
                }
            }
            .background(Paper.fill)
            .navigationTitle(Text(verbatim: DayNames(locale: locale).name(of: day)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if book.isAllowed, !book.writableCalendars.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            editing = .new
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 19, weight: .semibold))
                        }
                        .accessibilityLabel(Text("New event"))
                        .accessibilityIdentifier("events.add")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.inter(.semibold, size: 17, relativeTo: .body))
                    }
                    .accessibilityIdentifier("events.done")
                }
            }
            .navigationDestination(item: $editing) { target in
                EventEditorView(book: book, day: day, event: target.event, now: now)
            }
        }
        .tint(Paper.ink)
    }

    private var eventList: some View {
        let events = book.events(on: day)
        let clock = EventClock.current
        return List {
            Section {
                if events.isEmpty {
                    Text("No events on this day.")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.secondary)
                        .listRowBackground(Paper.background)
                        .accessibilityIdentifier("events.empty")
                }
                ForEach(events) { event in
                    Button {
                        editing = .event(event)
                    } label: {
                        EventRow(event: event, day: day, clock: clock)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Paper.background)
                    .accessibilityIdentifier("events.row")
                }
            } footer: {
                (book.writableCalendars.isEmpty
                    ? Text("None of your calendars can be changed here.")
                    : Text("Events are kept in Apple Calendar: a change here shows there too, and the other way round."))
                    .font(.inter(.regular, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Paper.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

/// What the editor opens: a new event of the day, or an existing one.
enum EventEditorTarget: Hashable, Identifiable {
    case new
    case event(CalendarEvent)

    var id: String {
        switch self {
        case .new: "new"
        case .event(let event): event.id
        }
    }

    var event: CalendarEvent? {
        if case .event(let event) = self { return event }
        return nil
    }
}

/// One event in a day's list: its time (or "All day") on the left, the title and the
/// calendar's name.
private struct EventRow: View {
    let event: CalendarEvent
    let day: PlannerDate
    let clock: EventClock

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                if event.isLong {
                    Text("All day")
                        .font(.inter(.semibold, size: 14, relativeTo: .subheadline))
                        .foregroundStyle(Paper.ink)
                } else {
                    Text(verbatim: clock.time(event.start))
                        .font(.inter(.semibold, size: 15, relativeTo: .subheadline))
                        .foregroundStyle(Paper.ink)
                    Text(verbatim: clock.time(event.end))
                        .font(.inter(.regular, size: 14, relativeTo: .subheadline))
                        .foregroundStyle(Paper.secondary)
                }
            }
            .frame(width: 78, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: event.trimmedTitle.isEmpty ? " " : event.trimmedTitle)
                    .font(.inter(.semibold, size: 17, relativeTo: .body))
                    .foregroundStyle(Paper.ink)
                    .multilineTextAlignment(.leading)
                Text(verbatim: event.calendarTitle)
                    .font(.inter(.regular, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Paper.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Paper.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Before access: what connecting does, and the button that asks for it.
struct CalendarConnectPrompt: View {
    let book: CalendarBook

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "calendar")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Paper.ink)
                    .padding(.bottom, 4)
                Text("Your Apple Calendar in the planner")
                    .font(.inter(.semibold, size: 19, relativeTo: .headline))
                    .foregroundStyle(Paper.ink)
                    .multilineTextAlignment(.center)
                Text("The events of Apple Calendar (and of Google or Outlook accounts on this device) are printed in the day cells, under your handwriting. Here you can add, change and delete them.")
                    .font(.inter(.regular, size: 16, relativeTo: .body))
                    .foregroundStyle(Paper.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task {
                        await book.requestAccess()
                    }
                } label: {
                    Text("Connect Apple Calendar")
                        .font(.inter(.semibold, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.background)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Paper.ink))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityIdentifier("events.connect")
                Text("The app keeps no copy of your events. Without access it works as before, as a handwritten planner.")
                    .font(.inter(.regular, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Paper.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Access was refused (or only adding events was allowed): how to allow it.
struct CalendarNotAllowed: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Paper.ink)
                Text("No access to your calendar")
                    .font(.inter(.semibold, size: 19, relativeTo: .headline))
                    .foregroundStyle(Paper.ink)
                Text("To see your events here, allow full access to Danai's Calendar in the Settings app, under Privacy & Security → Calendars.")
                    .font(.inter(.regular, size: 16, relativeTo: .body))
                    .foregroundStyle(Paper.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.inter(.semibold, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.ink)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .overlay(Capsule().stroke(Paper.ink, lineWidth: 1.4))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("events.openSettings")
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
    }
}
