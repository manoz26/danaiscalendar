import PlannerCore
import SwiftUI
import UIKit

/// A day on the iPhone (a tap on it): its box cut out of the page and enlarged, to read what
/// was written in it on the iPad; its events of the Apple Calendar, with + for a new one;
/// and the ways to its week page and to its journal page.
struct PhoneDayView: View {
    let book: CalendarBook
    let day: PlannerDate
    let now: Date
    /// The day's box of the page with its handwriting; `nil` when nothing is written in it.
    let handwriting: UIImage?
    let hasJournalPage: Bool
    /// Opened from the month page: the day's week page is one tap away.
    let showsWeek: Bool
    let onOpenWeek: () -> Void
    let onOpenJournalPage: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editing: EventEditorTarget?

    var body: some View {
        let locale = AppLocale.current
        NavigationStack {
            List {
                if let handwriting {
                    Section {
                        Image(uiImage: handwriting)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 300)
                            .overlay(Rectangle().stroke(Paper.hairline, lineWidth: 1))
                            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                            .listRowBackground(Paper.background)
                            .accessibilityLabel(Text("Handwriting of this day"))
                            .accessibilityIdentifier("day.handwriting")
                    } header: {
                        CapsLabel("Handwriting")
                    }
                }

                Section {
                    events
                } header: {
                    CapsLabel("Events")
                } footer: {
                    eventsFooter
                        .font(.inter(.regular, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Paper.secondary)
                }

                if showsWeek || hasJournalPage {
                    Section {
                        if showsWeek {
                            link(symbol: "rectangle.split.2x2", text: Text("Week page"), identifier: "day.week", action: onOpenWeek)
                        }
                        if hasJournalPage {
                            link(symbol: "book.closed", text: Text("Journal page"), identifier: "day.journal", action: onOpenJournalPage)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .textCase(nil)
            .scrollContentBackground(.hidden)
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

    // MARK: - Parts

    /// The day's events; before access is given, the button that asks for it; when it was
    /// refused, the way to the Settings app.
    @ViewBuilder
    private var events: some View {
        switch book.access {
        case .allowed:
            let dayEvents = book.events(on: day)
            let clock = EventClock.current
            if dayEvents.isEmpty {
                Text("No events on this day.")
                    .font(.inter(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Paper.secondary)
                    .listRowBackground(Paper.background)
                    .accessibilityIdentifier("events.empty")
            }
            ForEach(dayEvents) { event in
                Button {
                    editing = .event(event)
                } label: {
                    EventRow(event: event, day: day, clock: clock)
                }
                .buttonStyle(.plain)
                .listRowBackground(Paper.background)
                .accessibilityIdentifier("events.row")
            }
        case .notAsked:
            Button {
                Task {
                    await book.requestAccess()
                }
            } label: {
                Text("Connect Apple Calendar")
                    .font(.inter(.semibold, size: 17, relativeTo: .body))
                    .foregroundStyle(Paper.ink)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Paper.background)
            .accessibilityIdentifier("events.connect")
        case .writeOnly, .denied, .restricted:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.inter(.semibold, size: 17, relativeTo: .body))
                    .foregroundStyle(Paper.ink)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Paper.background)
            .accessibilityIdentifier("events.openSettings")
        }
    }

    private var eventsFooter: Text {
        switch book.access {
        case .allowed:
            book.writableCalendars.isEmpty
                ? Text("None of your calendars can be changed here.")
                : Text("Events are kept in Apple Calendar: a change here shows there too, and the other way round.")
        case .notAsked:
            Text("The events of Apple Calendar (and of Google or Outlook accounts on this device) are printed in the day cells, under your handwriting.")
        case .writeOnly, .denied, .restricted:
            Text("To see your events here, allow full access to Danai's Calendar in the Settings app, under Privacy & Security → Calendars.")
        }
    }

    private func link(symbol: String, text: Text, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 26)
                text
                    .font(.inter(.regular, size: 17, relativeTo: .body))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Paper.secondary)
            }
            .foregroundStyle(Paper.ink)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Paper.background)
        .accessibilityIdentifier(identifier)
    }
}
