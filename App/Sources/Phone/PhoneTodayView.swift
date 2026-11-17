import PlannerCore
import SwiftUI

/// The iPhone's Today tab: today's events and birthdays, the next days', the month's typed
/// to-dos, and a + that adds an event, a to-do or a thing to buy.
struct PhoneTodayView: View {
    let appleCalendar: CalendarBook
    let lists: ListBook
    let birthdays: BirthdayBook
    let today: PlannerDate
    let now: Date
    /// Opens a typed list with the keyboard ready for a new item.
    let onAdd: (TypedListKind) -> Void
    let onSettings: () -> Void

    /// How many days after today the tab looks ahead.
    static let daysAhead = 7

    @State private var editing: EventEditorTarget?

    var body: some View {
        let locale = AppLocale.current
        let calendar = PlannerLocale.calendar(locale: locale)
        let clock = EventClock.current
        let month = today.yearMonth
        let todos = TypedLists.openThenTicked(lists.items(.todo(month)))
        let toBuy = lists.toBuy.filter { !$0.done }.count
        NavigationStack {
            List {
                Section {
                    heading(locale: locale)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 0, trailing: 4))
                }

                Section {
                    if appleCalendar.access == .notAsked {
                        Button {
                            Task {
                                await appleCalendar.requestAccess()
                            }
                        } label: {
                            row(symbol: "calendar", text: Text("Connect Apple Calendar"))
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Paper.background)
                        .accessibilityIdentifier("today.connect")
                    }
                    dayRows(today, clock: clock)
                    if isEmpty(today) {
                        Text("Nothing planned for today.")
                            .font(.inter(.regular, size: 17, relativeTo: .body))
                            .foregroundStyle(Paper.secondary)
                            .listRowBackground(Paper.background)
                            .accessibilityIdentifier("today.empty")
                    }
                } header: {
                    CapsLabel("Today")
                }

                ForEach(upcomingDays, id: \.self) { day in
                    Section {
                        dayRows(day, clock: clock)
                    } header: {
                        CapsLabel(verbatim: JournalHeading.format(day, locale: locale))
                    }
                }

                Section {
                    // The whole row ticks (as in the Lists tab), not only its circle and text.
                    ForEach(todos.open + todos.ticked) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .regular))
                                .frame(width: 26)
                            Text(verbatim: item.trimmedText)
                                .font(.inter(.regular, size: 17, relativeTo: .body))
                                .strikethrough(item.done, color: Paper.secondary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(item.done ? Paper.secondary : Paper.ink)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            lists.setDone(item.id, !item.done, in: .todo(month))
                        }
                        .listRowBackground(Paper.background)
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(Text(verbatim: item.trimmedText))
                        .accessibilityValue(item.done ? Text("Ticked") : Text("Not ticked"))
                        .accessibilityIdentifier("today.todo")
                        .accessibilityAction {
                            lists.setDone(item.id, !item.done, in: .todo(month))
                        }
                    }
                    Button {
                        onAdd(.todo(month))
                    } label: {
                        row(symbol: "plus", text: Text("New to-do"))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Paper.background)
                    .accessibilityIdentifier("today.addTodo")
                } header: {
                    CapsLabel(verbatim: "\(PlannerPageContent.labels.todo) · \(CalendarNames.monthName(month.month, locale: locale))")
                }

                Section {
                    Button {
                        onAdd(.toBuy)
                    } label: {
                        row(symbol: "plus", text: Text("New thing to buy"))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Paper.background)
                    .accessibilityIdentifier("today.addToBuy")
                } header: {
                    CapsLabel(verbatim: PlannerPageContent.toBuyTitle)
                } footer: {
                    Text("Things still to buy: \(toBuy)")
                        .font(.inter(.regular, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Paper.secondary)
                        .accessibilityIdentifier("today.toBuyCount")
                }
            }
            .listStyle(.insetGrouped)
            .textCase(nil)
            .scrollContentBackground(.hidden)
            .background(Paper.fill)
            .navigationTitle(Text("Today"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if appleCalendar.isAllowed, !appleCalendar.writableCalendars.isEmpty {
                            Button {
                                editing = .new
                            } label: {
                                Label("New event", systemImage: "calendar.badge.plus")
                            }
                            .accessibilityIdentifier("today.newEvent")
                        }
                        Button {
                            onAdd(.todo(month))
                        } label: {
                            Label("New to-do", systemImage: "circle")
                        }
                        Button {
                            onAdd(.toBuy)
                        } label: {
                            Label("New thing to buy", systemImage: "bag")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .semibold))
                    }
                    .accessibilityLabel(Text("Add"))
                    .accessibilityIdentifier("today.add")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .regular))
                    }
                    .accessibilityLabel(Text("Settings"))
                    .accessibilityIdentifier("settings.button")
                }
            }
            .navigationDestination(item: $editing) { target in
                EventEditorView(
                    book: appleCalendar,
                    day: target.event?.firstDay(in: calendar) ?? today,
                    event: target.event, now: now
                )
            }
        }
        .tint(Paper.ink)
    }

    // MARK: - Parts

    /// The year small and the day big, like the top of a page: "2026", "MONDAY, NOVEMBER 16".
    private func heading(locale: Locale) -> some View {
        let texts = JournalHeading.texts(title: "", date: today, locale: locale)
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: texts.label)
                .font(.inter(.semibold, size: 12, relativeTo: .caption))
                .tracking(2)
                .foregroundStyle(Paper.tabLabel)
            Text(verbatim: texts.heading)
                .font(.inter(.bold, size: 26, relativeTo: .title))
                .foregroundStyle(Paper.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("today.heading")
    }

    private func row(symbol: String, text: Text) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 26)
            text
                .font(.inter(.regular, size: 17, relativeTo: .body))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Paper.ink)
        .frame(minHeight: 36)
        .contentShape(Rectangle())
    }

    /// A day's birthdays, then its events of the Apple Calendar (tap one to change it).
    @ViewBuilder
    private func dayRows(_ day: PlannerDate, clock: EventClock) -> some View {
        ForEach(birthdayTexts(on: day), id: \.self) { text in
            HStack(spacing: 12) {
                Image(systemName: "gift")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 26)
                Text(verbatim: text)
                    .font(.inter(.regular, size: 17, relativeTo: .body))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Paper.ink)
            .frame(minHeight: 36)
            .listRowBackground(Paper.background)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today.birthday")
        }
        ForEach(appleCalendar.events(on: day)) { event in
            Button {
                editing = .event(event)
            } label: {
                EventRow(event: event, day: day, clock: clock)
            }
            .buttonStyle(.plain)
            .listRowBackground(Paper.background)
            .accessibilityIdentifier("today.event")
        }
    }

    private func birthdayTexts(on day: PlannerDate) -> [String] {
        PlannerPageContent.birthdayNotes(for: day.yearMonth, in: birthdays.birthdays)
            .filter { $0.date == day }
            .map(\.text)
    }

    private func isEmpty(_ day: PlannerDate) -> Bool {
        birthdayTexts(on: day).isEmpty && appleCalendar.events(on: day).isEmpty
    }

    /// The next days that have an event or a birthday.
    private var upcomingDays: [PlannerDate] {
        (1...Self.daysAhead).map { today.adding(days: $0) }.filter { !isEmpty($0) }
    }
}

extension JournalHeading {
    /// A day as the header of a list: "Tuesday, November 17" / "Τρίτη 17 Νοεμβρίου".
    static func format(_ date: PlannerDate, locale: Locale) -> String {
        let calendar = PlannerLocale.calendar(locale: locale)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        let components = DateComponents(year: date.year, month: date.month, day: date.day, hour: 12)
        guard let day = calendar.date(from: components) else { return date.description }
        return formatter.string(from: day)
    }
}
