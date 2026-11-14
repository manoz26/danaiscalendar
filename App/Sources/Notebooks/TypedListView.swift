import SwiftUI
import PlannerCore

/// Typed items of a list (the printed + of the month's to-do list or of the To Buy page):
/// type a new one, tick, change or swipe to delete. Each new item takes the first line of
/// the page that has neither an item nor handwriting, and is printed there under the ink.
struct TypedListView: View {
    let lists: ListBook
    let kind: TypedListKind
    /// Lines of the page that already have handwriting.
    let inkedLines: Set<Int>
    /// Opened from the +: the keyboard is ready for a new item.
    let focusNew: Bool
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var newText = ""
    @FocusState private var newFieldFocused: Bool

    var body: some View {
        let items = lists.items(kind)
        NavigationStack {
            List {
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            TypedItemRow(
                                item: item, kind: kind,
                                text: Binding(
                                    get: { lists.items(kind).first { $0.id == item.id }?.text ?? item.text },
                                    set: { lists.setText(item.id, $0, in: kind) }
                                ),
                                onToggle: { lists.setDone(item.id, !item.done, in: kind) }
                            )
                            .listRowBackground(Paper.background)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                lists.delete(items[index].id, from: kind)
                            }
                        }
                    }
                }
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Paper.ink)
                            .frame(width: 26)
                        TextField(text: $newText, prompt: Text("New item")) {
                            Text("New item")
                        }
                        .font(.inter(.regular, size: 18, relativeTo: .body))
                        .foregroundStyle(Paper.ink)
                        .focused($newFieldFocused)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .accessibilityIdentifier("list.new")
                    }
                    .frame(minHeight: 36)
                    .listRowBackground(Paper.background)
                } footer: {
                    (items.isEmpty
                        ? Text("Typed items are printed on the page's lines, under your handwriting. Tap the circle or box on the page to tick one.")
                        : Text("Swipe an item to delete it."))
                        .font(.inter(.regular, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Paper.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Paper.fill)
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        add()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.inter(.semibold, size: 17, relativeTo: .body))
                    }
                    .accessibilityIdentifier("list.done")
                }
            }
        }
        .tint(Paper.ink)
        .task {
            guard focusNew else { return }
            // The field exists once the sheet is on screen.
            try? await Task.sleep(for: .milliseconds(350))
            newFieldFocused = true
        }
        .onDisappear {
            lists.removeEmptyItems(in: kind)
        }
    }

    private func add() {
        guard !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lists.add(newText, to: kind, inkedLines: inkedLines)
        newText = ""
        newFieldFocused = true
    }
}

/// One typed item: its circle (to-do) or box (to buy), and its text, which can be changed.
private struct TypedItemRow: View {
    let item: ListItem
    let kind: TypedListKind
    @Binding var text: String
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(Paper.ink)
                    .frame(width: 26, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? Text("Ticked") : Text("Not ticked"))
            .accessibilityIdentifier("list.item.toggle")

            VStack(alignment: .leading, spacing: 2) {
                TextField(text: $text, prompt: Text("Item")) {
                    Text("Item")
                }
                .font(.inter(.regular, size: 18, relativeTo: .body))
                .foregroundStyle(item.done ? Paper.secondary : Paper.ink)
                .strikethrough(item.done, color: Paper.secondary)
                .accessibilityIdentifier("list.item")
                if item.line == nil {
                    Text("No free line on the page")
                        .font(.inter(.regular, size: 12, relativeTo: .caption))
                        .foregroundStyle(Paper.secondary)
                }
            }
        }
        .frame(minHeight: 36)
    }

    private var symbol: String {
        switch kind {
        case .todo: item.done ? "checkmark.circle.fill" : "circle"
        case .toBuy: item.done ? "checkmark.square.fill" : "square"
        }
    }
}
