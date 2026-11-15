import PlannerCore
import SwiftUI
import UIKit

/// A new event of a day, or one of its events: title, all-day, start and end, repeat,
/// reminder (Apple Calendar's own alerts, so the system shows them) and calendar; and
/// deleting it. For a repeating event, saving or deleting asks whether for this one only
/// or the future ones too. Events of calendars that can't be changed are shown only.
struct EventEditorView: View {
    let book: CalendarBook
    /// `nil`: a new event.
    let event: CalendarEvent?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: EventDraft
    @State private var askSaveSpan = false
    @State private var confirmDelete = false
    @State private var failure: Failure?

    enum Failure: Identifiable {
        case save, delete
        var id: Self { self }
    }

    init(book: CalendarBook, day: PlannerDate, event: CalendarEvent?, now: Date) {
        self.book = book
        self.event = event
        let calendar = PlannerLocale.calendar(locale: AppLocale.current)
        _draft = State(initialValue: event.map { EventDraft($0, calendar: calendar) }
            ?? EventDraft.new(on: day, now: now, calendar: calendar, calendarID: book.defaultCalendarID))
    }

    private var readOnly: Bool { event.map { !$0.canEdit } ?? false }
    private var repeating: Bool { event.map { $0.repeats != .never } ?? false }

    var body: some View {
        let locale = AppLocale.current
        let calendar = pickerCalendar()
        Form {
            Section {
                TextField(text: $draft.title, prompt: Text("Title")) {
                    Text("Title")
                }
                .font(.inter(.regular, size: 19, relativeTo: .body))
                .foregroundStyle(Paper.ink)
                .submitLabel(.done)
                .accessibilityIdentifier("event.title")
            } footer: {
                if UIDevice.current.userInterfaceIdiom == .pad, !readOnly {
                    Text("You can also write the title with Apple Pencil: it turns into text.")
                        .font(.inter(.regular, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Paper.secondary)
                }
            }
            .listRowBackground(Paper.background)

            Section {
                Toggle(isOn: Binding(
                    get: { draft.isAllDay },
                    set: { draft.setAllDay($0, calendar: PlannerLocale.calendar(locale: locale)) }
                )) {
                    Text("All day")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                }
                .tint(Paper.ink)
                .accessibilityIdentifier("event.allDay")
                DatePicker(
                    selection: Binding(get: { draft.start }, set: { draft.moveStart(to: dayOnly($0)) }),
                    displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute]
                ) {
                    Text("Starts")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                }
                .accessibilityIdentifier("event.start")
                DatePicker(
                    selection: Binding(get: { draft.end }, set: { draft.setEnd(dayOnly($0)) }),
                    in: draft.start...,
                    displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute]
                ) {
                    Text("Ends")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                }
                .accessibilityIdentifier("event.end")
            }
            .environment(\.locale, locale)
            .environment(\.calendar, calendar)
            .listRowBackground(Paper.background)

            Section {
                Picker(selection: $draft.repeats) {
                    ForEach(repeatChoices, id: \.self) { choice in
                        Text(verbatim: EventTexts.repeats(choice)).tag(choice)
                    }
                } label: {
                    Text("Repeat")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                }
                .accessibilityIdentifier("event.repeat")
                Picker(selection: $draft.reminder) {
                    Text("None").tag(EventReminder?.none)
                    ForEach(reminderChoices, id: \.self) { choice in
                        Text(verbatim: EventTexts.reminder(choice, allDay: draft.isAllDay)).tag(EventReminder?.some(choice))
                    }
                } label: {
                    Text("Reminder")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                }
                .accessibilityIdentifier("event.reminder")
            } footer: {
                Text("Reminders are Apple Calendar's own: the iPad and the iPhone show them.")
                    .font(.inter(.regular, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Paper.secondary)
            }
            .listRowBackground(Paper.background)

            Section {
                if readOnly {
                    LabeledContent {
                        Text(verbatim: event?.calendarTitle ?? "")
                    } label: {
                        Text("Calendar")
                    }
                    .font(.inter(.regular, size: 17, relativeTo: .body))
                } else {
                    Picker(selection: $draft.calendarID) {
                        ForEach(book.writableCalendars) { choice in
                            Text(verbatim: EventTexts.calendarName(choice, among: book.writableCalendars)).tag(String?.some(choice.id))
                        }
                    } label: {
                        Text("Calendar")
                            .font(.inter(.regular, size: 17, relativeTo: .body))
                    }
                    .accessibilityIdentifier("event.calendar")
                }
            } footer: {
                if readOnly {
                    Text("This calendar can't be changed here.")
                        .font(.inter(.regular, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Paper.secondary)
                }
            }
            .listRowBackground(Paper.background)

            if event != nil, !readOnly {
                Section {
                    Button {
                        confirmDelete = true
                    } label: {
                        Text("Delete event")
                            .font(.inter(.regular, size: 17, relativeTo: .body))
                            .foregroundStyle(Paper.ink)
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("event.delete")
                    .confirmationDialog(
                        repeating ? Text("This is a repeating event.") : Text("Delete this event?"),
                        isPresented: $confirmDelete, titleVisibility: .visible
                    ) {
                        if repeating {
                            Button {
                                delete(.thisEvent)
                            } label: {
                                Text("Delete this event only")
                            }
                            .accessibilityIdentifier("event.confirmDelete")
                            Button {
                                delete(.futureEvents)
                            } label: {
                                Text("Delete all future events")
                            }
                        } else {
                            Button {
                                delete(.thisEvent)
                            } label: {
                                Text("Delete event")
                            }
                            .accessibilityIdentifier("event.confirmDelete")
                        }
                        Button(role: .cancel) {
                        } label: {
                            Text("Cancel")
                        }
                    } message: {
                        Text("It is deleted from Apple Calendar too.")
                    }
                    .listRowBackground(Paper.background)
                }
            }
        }
        .disabled(readOnly)
        .scrollContentBackground(.hidden)
        .background(Paper.fill)
        .navigationTitle(event == nil ? Text("New event") : Text("Event"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !readOnly {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if repeating {
                            askSaveSpan = true
                        } else {
                            save(.thisEvent)
                        }
                    } label: {
                        (event == nil ? Text("Add") : Text("Save"))
                            .font(.inter(.semibold, size: 17, relativeTo: .body))
                    }
                    .disabled(!draft.canSave)
                    .accessibilityIdentifier("event.save")
                    .confirmationDialog(Text("This is a repeating event."), isPresented: $askSaveSpan, titleVisibility: .visible) {
                        Button {
                            save(.thisEvent)
                        } label: {
                            Text("Save for this event only")
                        }
                        Button {
                            save(.futureEvents)
                        } label: {
                            Text("Save for future events")
                        }
                        Button(role: .cancel) {
                        } label: {
                            Text("Cancel")
                        }
                    }
                }
            }
        }
        .alert(
            failure == .delete ? Text("The event could not be deleted.") : Text("The event could not be saved."),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button {
            } label: {
                Text("OK")
            }
        }
        .tint(Paper.ink)
    }

    private var repeatChoices: [EventRepeat] {
        EventRepeat.choices + (draft.repeats == .custom ? [.custom] : [])
    }

    private var reminderChoices: [EventReminder] {
        let choices = EventReminder.choices(allDay: draft.isAllDay)
        guard let reminder = draft.reminder, !choices.contains(reminder) else { return choices }
        return choices + [reminder]
    }

    /// All-day events keep midnight: the pickers show days only.
    private func dayOnly(_ date: Date) -> Date {
        guard draft.isAllDay else { return date }
        let calendar = PlannerLocale.calendar(locale: AppLocale.current)
        return PlannerDate(date: date, calendar: calendar).midnight(in: calendar)
    }

    private func save(_ span: EventSpan) {
        do {
            try book.save(draft, replacing: event, span: span)
            dismiss()
        } catch {
            failure = .save
        }
    }

    private func delete(_ span: EventSpan) {
        guard let event else { return }
        do {
            try book.delete(event, span: span)
            dismiss()
        } catch {
            failure = .delete
        }
    }
}

/// Texts of the event form in the app's language.
enum EventTexts {
    static func repeats(_ choice: EventRepeat) -> String {
        switch choice {
        case .never: String(localized: "Never", comment: "Repeat of an event: it does not repeat.")
        case .daily: String(localized: "Every day", comment: "Repeat of an event.")
        case .weekly: String(localized: "Every week", comment: "Repeat of an event.")
        case .biweekly: String(localized: "Every 2 weeks", comment: "Repeat of an event.")
        case .monthly: String(localized: "Every month", comment: "Repeat of an event.")
        case .yearly: String(localized: "Every year", comment: "Repeat of an event.")
        case .custom: String(localized: "Custom", comment: "Repeat of an event made in Apple Calendar that the form can't show (e.g. every weekday). It stays as it is.")
        }
    }

    /// "15 minutes before", "1 day before at 9:00"…
    @MainActor
    static func reminder(_ reminder: EventReminder, allDay: Bool) -> String {
        let offset = Int(reminder.offset.rounded())
        if allDay {
            // Counted from midnight of the event's day: 9:00 on the day is +9 h.
            let dayLength = 86_400
            let daysBefore = offset >= 0 ? 0 : (-offset + dayLength - 1) / dayLength
            let secondsInDay = offset + daysBefore * dayLength
            let time = EventClock.current.time(hour: secondsInDay / 3600, minute: (secondsInDay % 3600) / 60)
            switch daysBefore {
            case 0: return String(localized: "On the day at \(time)", comment: "Reminder of an all-day event, e.g. 'On the day at 9:00'.")
            case 1: return String(localized: "1 day before at \(time)", comment: "Reminder of an all-day event, e.g. '1 day before at 9:00'.")
            case 7: return String(localized: "1 week before at \(time)", comment: "Reminder of an all-day event, e.g. '1 week before at 9:00'.")
            default: return String(localized: "\(daysBefore) days before at \(time)", comment: "Reminder of an all-day event, e.g. '2 days before at 9:00'.")
            }
        }
        let before = -offset
        switch before {
        case 0:
            return String(localized: "At time of event", comment: "Reminder of an event: when it starts.")
        case 1..<3600 where before % 60 == 0:
            return String(localized: "\(before / 60) minutes before", comment: "Reminder of an event, e.g. '15 minutes before'.")
        case 3600:
            return String(localized: "1 hour before", comment: "Reminder of an event.")
        case 3601..<86_400 where before % 3600 == 0:
            return String(localized: "\(before / 3600) hours before", comment: "Reminder of an event, e.g. '2 hours before'.")
        case 86_400:
            return String(localized: "1 day before", comment: "Reminder of an event.")
        case 604_800:
            return String(localized: "1 week before", comment: "Reminder of an event.")
        case 86_401... where before % 86_400 == 0:
            return String(localized: "\(before / 86_400) days before", comment: "Reminder of an event, e.g. '2 days before'.")
        default:
            return String(localized: "Other", comment: "A reminder set in Apple Calendar that the form doesn't offer. It stays as it is.")
        }
    }

    /// The calendar's name, with its account when another calendar has the same name.
    static func calendarName(_ calendar: EventCalendar, among all: [EventCalendar]) -> String {
        let same = all.filter { $0.title == calendar.title }.count > 1
        return same && !calendar.source.isEmpty ? "\(calendar.title) (\(calendar.source))" : calendar.title
    }
}
