import PlannerCore
import SwiftUI

/// The lists of the iPhone's Lists tab.
enum PhoneList: String, CaseIterable, Identifiable {
    case toBuy, toDo, birthdays, wishlist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toBuy: PlannerPageContent.toBuyTitle
        case .toDo: String(localized: "To do", comment: "iPhone, Lists tab: the typed to-dos of a month.")
        case .birthdays: String(localized: "Birthdays")
        case .wishlist: PlannerTopBar.wishlistTitle
        }
    }
}

/// The iPhone's Lists tab: things to buy, the month's to-dos, birthdays and the wishlist.
/// To Buy is made for one hand in the shop: big rows, a tap anywhere ticks, and what is
/// ticked falls to the bottom.
struct PhoneListsView: View {
    let lists: ListBook
    let birthdays: BirthdayBook
    let wishlist: WishlistBook
    let ink: InkController
    let today: PlannerDate
    /// Opens the handwritten To Buy page (written on the iPad), to look at.
    let onOpenToBuyPage: () -> Void
    let onSettings: () -> Void

    @AppStorage(PhoneDefaults.list) private var selectedName = PhoneList.toBuy.rawValue
    /// The month whose to-dos are shown.
    @State private var todoMonth: YearMonth?

    var body: some View {
        let locale = AppLocale.current
        let selected = PhoneList(rawValue: selectedName) ?? .toBuy
        let month = todoMonth ?? today.yearMonth
        VStack(spacing: 0) {
            PhoneSegments(
                items: PhoneList.allCases.map { list in
                    PhoneSegments<PhoneList>.Item(value: list, title: list.title, identifier: "phone.lists.\(list.rawValue)")
                },
                selection: selected,
                onSelect: { selectedName = $0.rawValue },
                onSettings: onSettings
            )
            switch selected {
            case .toBuy:
                PhoneTypedList(
                    lists: lists, kind: .toBuy,
                    inkedLines: { ink.inkedLines(of: .toBuy, today: today, locale: locale) },
                    onOpenPage: onOpenToBuyPage
                )
            case .toDo:
                monthStepper(month, locale: locale)
                PhoneTypedList(
                    lists: lists, kind: .todo(month),
                    inkedLines: { ink.inkedLines(of: .todo(month), today: today, locale: locale) }
                )
                .id(month)
            case .birthdays:
                BirthdaysView(book: birthdays, embedded: true)
            case .wishlist:
                WishlistView(book: wishlist, embedded: true)
            }
        }
        .background(Paper.fill)
    }

    /// "‹ November 2026 ›": the to-dos are the month's, as on its page.
    private func monthStepper(_ month: YearMonth, locale: Locale) -> some View {
        HStack(spacing: 0) {
            BarIconButton(systemName: "chevron.left", identifier: "phone.todo.previous", compact: true) {
                todoMonth = month.previous
            }
            .accessibilityLabel(Text("Previous month"))
            Spacer(minLength: 4)
            Text(verbatim: "\(CalendarNames.monthName(month.month, locale: locale)) \(month.year)")
                .font(.inter(.semibold, size: 16, relativeTo: .headline))
                .foregroundStyle(Paper.ink)
                .lineLimit(1)
                .accessibilityIdentifier("phone.todo.month")
            Spacer(minLength: 4)
            BarIconButton(systemName: "chevron.right", identifier: "phone.todo.next", compact: true) {
                todoMonth = month.next
            }
            .accessibilityLabel(Text("Next month"))
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(Paper.background)
    }
}

/// A typed list on the iPhone: big rows (a tap ticks or unticks), the open items first in
/// the order she arranged them and the ticked ones below; swipe a row to delete or change
/// it, hold and drag (or the arrange button) to move it; the field at the bottom, within
/// reach of the thumb, adds items one after the other.
///
/// The same items are printed on the iPad's page, each on its own line under the ink.
struct PhoneTypedList: View {
    let lists: ListBook
    let kind: TypedListKind
    /// The page's lines with handwriting, asked for when an item is added.
    let inkedLines: () -> Set<Int>
    /// Opens the handwritten page of the list, if it has one to show.
    var onOpenPage: (() -> Void)?

    @State private var newText = ""
    @State private var renaming: ListItem?
    @State private var renamed = ""
    @State private var confirmDeleteTicked = false
    @State private var editMode = EditMode.inactive
    @FocusState private var newFieldFocused: Bool

    var body: some View {
        let items = TypedLists.openThenTicked(lists.items(kind))
        List {
            if let onOpenPage {
                Section {
                    Button(action: onOpenPage) {
                        HStack(spacing: 14) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 20, weight: .regular))
                                .frame(width: 30)
                            Text("Handwritten page")
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
                    .accessibilityIdentifier("phone.list.page")
                }
            }

            Section {
                if items.open.isEmpty {
                    (items.ticked.isEmpty ? Text("Nothing here yet. Type below to add.") : Text("Everything is ticked."))
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.secondary)
                        .frame(minHeight: 44)
                        .listRowBackground(Paper.background)
                        .accessibilityIdentifier("phone.list.empty")
                }
                ForEach(items.open) { item in
                    row(item)
                }
                .onMove { source, destination in
                    move(source, to: destination, in: items.open)
                }
            }

            if !items.ticked.isEmpty {
                Section {
                    ForEach(items.ticked) { item in
                        row(item)
                    }
                    Button {
                        confirmDeleteTicked = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "trash")
                                .font(.system(size: 19, weight: .regular))
                                .frame(width: 30)
                            Text("Delete ticked items")
                                .font(.inter(.regular, size: 17, relativeTo: .body))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Paper.ink)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Paper.background)
                    .accessibilityIdentifier("phone.list.deleteTicked")
                } header: {
                    CapsLabel("Ticked")
                }
            }
        }
        .listStyle(.insetGrouped)
        .textCase(nil)
        .scrollContentBackground(.hidden)
        .background(Paper.fill)
        .environment(\.editMode, $editMode)
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            addBar(canArrange: items.open.count > 1)
        }
        .alert(
            Text("Change item"),
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField(text: $renamed) {
                Text("Item")
            }
            .accessibilityIdentifier("phone.list.rename")
            Button {
                if let item = renaming {
                    lists.setText(item.id, renamed, in: kind)
                    lists.removeEmptyItems(in: kind)
                }
                renaming = nil
            } label: {
                Text("Save")
            }
            Button(role: .cancel) {
                renaming = nil
            } label: {
                Text("Cancel")
            }
        }
        .confirmationDialog(Text("Delete the ticked items?"), isPresented: $confirmDeleteTicked, titleVisibility: .visible) {
            Button {
                lists.deleteTicked(in: kind)
            } label: {
                Text("Delete")
            }
            .accessibilityIdentifier("phone.list.confirmDeleteTicked")
            Button(role: .cancel) {
            } label: {
                Text("Cancel")
            }
        }
    }

    // MARK: - Parts

    private func row(_ item: ListItem) -> some View {
        Button {
            lists.setDone(item.id, !item.done, in: kind)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol(item))
                    .font(.system(size: 27, weight: .regular))
                    .frame(width: 30)
                Text(verbatim: item.trimmedText)
                    .font(.inter(.regular, size: 20, relativeTo: .title3))
                    .strikethrough(item.done, color: Paper.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(item.done ? Paper.secondary : Paper.ink)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Paper.background)
        .accessibilityLabel(Text(verbatim: item.trimmedText))
        .accessibilityValue(item.done ? Text("Ticked") : Text("Not ticked"))
        .accessibilityIdentifier("phone.list.item")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                lists.delete(item.id, from: kind)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Paper.ink)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                renamed = item.text
                renaming = item
            } label: {
                Label("Change", systemImage: "pencil")
            }
            .tint(Paper.tabLabel)
        }
    }

    /// The field at the bottom: Return (or the +) adds the item and keeps the keyboard up
    /// for the next one. On its left, the button that shows the handles for moving items.
    private func addBar(canArrange: Bool) -> some View {
        HStack(spacing: 10) {
            if canArrange || editMode == .active {
                Button {
                    withAnimation {
                        editMode = editMode == .active ? .inactive : .active
                    }
                } label: {
                    Image(systemName: editMode == .active ? "checkmark" : "arrow.up.arrow.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Paper.ink)
                        .frame(width: 44, height: 46)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(editMode == .active ? Text("Done") : Text("Arrange items"))
                .accessibilityIdentifier("phone.list.arrange")
            }
            TextField(text: $newText, prompt: Text("New item")) {
                Text("New item")
            }
            .font(.inter(.regular, size: 19, relativeTo: .body))
            .foregroundStyle(Paper.ink)
            .focused($newFieldFocused)
            .submitLabel(.done)
            .onSubmit(add)
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Paper.fill))
            .accessibilityIdentifier("phone.list.new")
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Paper.background)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Paper.ink))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Add"))
            .accessibilityIdentifier("phone.list.add")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Paper.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Paper.hairline)
                .frame(height: 1)
        }
    }

    private func symbol(_ item: ListItem) -> String {
        switch kind {
        case .todo: item.done ? "checkmark.circle.fill" : "circle"
        case .toBuy: item.done ? "checkmark.square.fill" : "square"
        }
    }

    private func add() {
        guard !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lists.add(newText, to: kind, inkedLines: inkedLines())
        newText = ""
        newFieldFocused = true
    }

    /// A row dragged among the open items (SwiftUI's source and destination of `onMove`).
    private func move(_ source: IndexSet, to destination: Int, in open: [ListItem]) {
        guard let from = source.first, open.indices.contains(from) else { return }
        let item = open[from]
        let others = open.filter { $0.id != item.id }
        lists.move(item.id, to: destination > from ? destination - 1 : destination, among: others, in: kind)
    }
}
