import SwiftUI
import UIKit
import PlannerCore

/// The birthdays sheet (the gift in the top bar): friends' birthdays by month, with +
/// to add one, a tap to change it and a swipe to delete it. Each birthday gets a small
/// gift on its day in the month page and a line in that month's notes.
struct BirthdaysView: View {
    let book: BirthdayBook
    @Environment(\.dismiss) private var dismiss
    @State private var editing: BirthdayDraft?

    var body: some View {
        let locale = AppLocale.current
        NavigationStack {
            List {
                if book.birthdays.isEmpty {
                    Section {
                        emptyState
                    }
                }
                ForEach(months, id: \.self) { month in
                    Section {
                        let inMonth = birthdays(in: month)
                        ForEach(inMonth) { birthday in
                            Button {
                                editing = BirthdayDraft(birthday)
                            } label: {
                                BirthdayRow(birthday: birthday)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("birthday.row")
                            .listRowBackground(Paper.background)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                book.delete(inMonth[index].id)
                            }
                        }
                    } header: {
                        CapsLabel(verbatim: CalendarNames.monthName(month, locale: locale))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .textCase(nil)
            .scrollContentBackground(.hidden)
            .background(Paper.fill)
            .navigationTitle(Text("Birthdays"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        editing = BirthdayDraft.new(on: Date())
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .semibold))
                    }
                    .accessibilityLabel(Text("Add birthday"))
                    .accessibilityIdentifier("birthdays.add")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.inter(.semibold, size: 17, relativeTo: .body))
                    }
                    .accessibilityIdentifier("birthdays.done")
                }
            }
            .navigationDestination(item: $editing) { draft in
                BirthdayForm(
                    draft: draft,
                    onSave: { birthday in
                        book.save(birthday)
                        editing = nil
                    },
                    onDelete: { id in
                        book.delete(id)
                        editing = nil
                    }
                )
            }
        }
        .tint(Paper.ink)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "gift")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Paper.ink)
                .padding(.bottom, 4)
            Text("No birthdays yet")
                .font(.inter(.semibold, size: 17, relativeTo: .headline))
                .foregroundStyle(Paper.ink)
            Text("Tap + to add a friend's name and birthday. Its day gets a small gift on the month page, with a line in the notes.")
                .font(.inter(.regular, size: 15, relativeTo: .subheadline))
                .foregroundStyle(Paper.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("birthdays.empty")
        .listRowBackground(Paper.background)
    }

    /// Months that have birthdays, January first.
    private var months: [Int] {
        Array(Set(book.birthdays.map(\.month))).sorted()
    }

    private func birthdays(in month: Int) -> [Birthday] {
        Birthday.sortedByDate(book.birthdays.filter { $0.month == month })
    }
}

/// One line of the list: the day, then the name.
private struct BirthdayRow: View {
    let birthday: Birthday

    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: String(birthday.day))
                .font(.inter(.semibold, size: 17, relativeTo: .body))
                .monospacedDigit()
                .frame(minWidth: 26, alignment: .trailing)
            Text(verbatim: birthday.name)
                .font(.inter(.regular, size: 17, relativeTo: .body))
                .lineLimit(2)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Paper.secondary)
        }
        .foregroundStyle(Paper.ink)
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }
}

/// A birthday being added or changed.
struct BirthdayDraft: Hashable, Identifiable {
    var id: UUID
    var name: String
    var month: Int
    var day: Int
    var isNew: Bool

    init(_ birthday: Birthday) {
        id = birthday.id
        name = birthday.name
        month = birthday.month
        day = birthday.day
        isNew = false
    }

    private init(id: UUID, name: String, month: Int, day: Int, isNew: Bool) {
        self.id = id
        self.name = name
        self.month = month
        self.day = day
        self.isNew = isNew
    }

    /// A new birthday, on today's date until changed.
    static func new(on date: Date) -> BirthdayDraft {
        let today = PlannerDate(date: date, calendar: PlannerLocale.calendar(locale: AppLocale.current))
        return BirthdayDraft(id: UUID(), name: "", month: today.month, day: today.day, isNew: true)
    }
}

/// Name, day and month of one birthday. On iPad the name can be written with Apple
/// Pencil (Scribble turns it into text).
struct BirthdayForm: View {
    let draft: BirthdayDraft
    let onSave: (Birthday) -> Void
    let onDelete: (UUID) -> Void

    @State private var name: String
    @State private var month: Int
    @State private var day: Int
    @State private var confirmDelete = false

    init(draft: BirthdayDraft, onSave: @escaping (Birthday) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.draft = draft
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: draft.name)
        _month = State(initialValue: draft.month)
        _day = State(initialValue: draft.day)
    }

    private var birthday: Birthday {
        Birthday(id: draft.id, name: name, month: month, day: day)
    }

    var body: some View {
        let locale = AppLocale.current
        Form {
            Section {
                TextField(text: $name, prompt: Text("Name")) {
                    Text("Name")
                }
                .font(.inter(.regular, size: 19, relativeTo: .body))
                .foregroundStyle(Paper.ink)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .accessibilityIdentifier("birthday.name")
                .listRowBackground(Paper.background)
            } header: {
                CapsLabel("Name")
            } footer: {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Text("You can also write the name with Apple Pencil: it turns into text.")
                        .font(.inter(.regular, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Paper.secondary)
                }
            }

            Section {
                HStack(spacing: 0) {
                    Picker(selection: $day) {
                        ForEach(1...Birthday.dayCount(ofMonth: month), id: \.self) { number in
                            Text(verbatim: String(number))
                                .font(.inter(.medium, size: 21, relativeTo: .title3))
                                .tag(number)
                        }
                    } label: {
                        Text("Day")
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: 110)
                    .clipped()
                    .accessibilityIdentifier("birthday.day")

                    Picker(selection: $month) {
                        ForEach(1...12, id: \.self) { number in
                            Text(verbatim: CalendarNames.monthName(number, locale: locale))
                                .font(.inter(.medium, size: 21, relativeTo: .title3))
                                .tag(number)
                        }
                    } label: {
                        Text("Month")
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityIdentifier("birthday.month")
                }
                .listRowBackground(Paper.background)
            } header: {
                CapsLabel("Date")
            }

            if !draft.isNew {
                Section {
                    Button {
                        confirmDelete = true
                    } label: {
                        Text("Delete birthday")
                            .font(.inter(.regular, size: 17, relativeTo: .body))
                            .foregroundStyle(Paper.ink)
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("birthday.delete")
                    .listRowBackground(Paper.background)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Paper.fill)
        .navigationTitle(draft.isNew ? Text("New birthday") : Text("Edit birthday"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    onSave(birthday)
                } label: {
                    Text("Save")
                        .font(.inter(.semibold, size: 17, relativeTo: .body))
                }
                .disabled(!birthday.isValid)
                .accessibilityIdentifier("birthday.save")
            }
        }
        .onChange(of: month) { _, newMonth in
            day = min(day, Birthday.dayCount(ofMonth: newMonth))
        }
        .confirmationDialog(Text("Delete this birthday?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button {
                onDelete(draft.id)
            } label: {
                Text("Delete")
            }
            .accessibilityIdentifier("birthday.confirmDelete")
            Button(role: .cancel) {
            } label: {
                Text("Cancel")
            }
        }
    }
}
