import SwiftUI
import UIKit
import PlannerCore

extension PlannerDate {
    /// Midday of this day, for date pickers.
    func noon(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }
}

/// A page picture with a thin frame (black and thicker for the open page).
private struct PageThumbnail: View {
    let image: UIImage
    let isCurrent: Bool

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(PageCanvas.size.width / PageCanvas.size.height, contentMode: .fit)
            .overlay(
                Rectangle().stroke(isCurrent ? Paper.ink : Paper.hairline, lineWidth: isCurrent ? 2 : 1)
            )
            .accessibilityHidden(true)
    }
}

/// Big icon, a title and a line of text, for an empty grid.
private struct EmptyGrid: View {
    let systemName: String
    let title: Text
    let message: Text
    let identifier: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Paper.ink)
                .padding(.bottom, 6)
            title
                .font(.inter(.semibold, size: 17, relativeTo: .headline))
                .foregroundStyle(Paper.ink)
            message
                .font(.inter(.regular, size: 15, relativeTo: .subheadline))
                .foregroundStyle(Paper.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 420)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private var gridColumns: [GridItem] {
    [GridItem(.adaptive(minimum: 140, maximum: 210), spacing: 24)]
}

// MARK: - Journal pages

/// All the journal's pages as small pictures, in order: tap one to open it; hold one for
/// Duplicate, Move earlier/later and Delete; or drag it to another place.
struct JournalPagesView: View {
    let journal: JournalBook
    let currentPage: UUID?
    let canDraw: Bool
    let today: PlannerDate
    let onOpen: (UUID) -> Void
    let onAdd: () -> Void
    let onDuplicate: (UUID) -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var thumbnails: PageThumbnails
    @State private var pendingDelete: JournalPage?

    init(
        journal: JournalBook, ink: InkController, currentPage: UUID?, canDraw: Bool, today: PlannerDate,
        onOpen: @escaping (UUID) -> Void, onAdd: @escaping () -> Void,
        onDuplicate: @escaping (UUID) -> Void, onDelete: @escaping (UUID) -> Void
    ) {
        self.journal = journal
        self.currentPage = currentPage
        self.canDraw = canDraw
        self.today = today
        self.onOpen = onOpen
        self.onAdd = onAdd
        self.onDuplicate = onDuplicate
        self.onDelete = onDelete
        _thumbnails = State(initialValue: PageThumbnails(ink: ink))
    }

    var body: some View {
        let locale = AppLocale.current
        let data = PlannerData(journal: journal.journal)
        let pages = journal.pages
        NavigationStack {
            ScrollView {
                if pages.isEmpty {
                    EmptyGrid(
                        systemName: "book.closed",
                        title: Text("No pages yet"),
                        message: canDraw ? Text("Tap + for a new page.") : Text("Pages written on the iPad appear here."),
                        identifier: "journal.empty"
                    )
                }
                LazyVGrid(columns: gridColumns, spacing: 28) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        let content = PlannerPageContent(page: page.page, today: today, locale: locale, data: data)
                        cell(page, number: index + 1, count: pages.count, image: thumbnails.image(for: content), locale: locale)
                    }
                }
                .padding(24)
            }
            .background(Paper.fill)
            .navigationTitle(Text("Journal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canDraw {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onAdd) {
                            Image(systemName: "plus")
                                .font(.system(size: 19, weight: .semibold))
                        }
                        .accessibilityLabel(Text("New page"))
                        .accessibilityIdentifier("journal.add")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.inter(.semibold, size: 17, relativeTo: .body))
                    }
                    .accessibilityIdentifier("journal.done")
                }
            }
            .confirmationDialog(
                Text("Delete this page?"),
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { page in
                Button {
                    onDelete(page.id)
                } label: {
                    Text("Delete")
                }
                .accessibilityIdentifier("journal.confirmDelete")
                Button(role: .cancel) {
                } label: {
                    Text("Cancel")
                }
            } message: { _ in
                Text("Its handwriting is deleted too.")
            }
        }
        .tint(Paper.ink)
    }

    private func cell(_ page: JournalPage, number: Int, count: Int, image: UIImage, locale: Locale) -> some View {
        let caption = Self.caption(page, number: number, locale: locale)
        return Button {
            onOpen(page.id)
        } label: {
            VStack(spacing: 6) {
                PageThumbnail(image: image, isCurrent: page.id == currentPage)
                Text(verbatim: caption)
                    .font(.inter(.semibold, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
                Text(verbatim: String(number))
                    .font(.inter(.regular, size: 12, relativeTo: .caption))
                    .foregroundStyle(Paper.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(number). \(caption)"))
        .accessibilityIdentifier("journal.pages.cell")
        .contextMenu {
            if canDraw {
                Button {
                    onDuplicate(page.id)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
            }
            Button {
                journal.move(page.id, by: -1)
            } label: {
                Label("Move earlier", systemImage: "arrow.left")
            }
            .disabled(number == 1)
            Button {
                journal.move(page.id, by: 1)
            } label: {
                Label("Move later", systemImage: "arrow.right")
            }
            .disabled(number == count)
            Button {
                pendingDelete = page
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .draggable(page.id.uuidString) {
            PageThumbnail(image: image, isCurrent: false)
                .frame(width: 120)
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let text = ids.first, let id = UUID(uuidString: text), id != page.id else { return false }
            journal.move(id, to: number - 1)
            return true
        }
    }

    /// The title, or the day, or "Page 3".
    static func caption(_ page: JournalPage, number: Int, locale: Locale) -> String {
        if !page.trimmedTitle.isEmpty { return page.trimmedTitle }
        if let date = page.date { return JournalHeading.shortDate(date, locale: locale) }
        return String(localized: "Page \(number)", comment: "Caption of a journal page without title or date in the pages grid, e.g. 'Page 3'.")
    }
}

// MARK: - One journal page's details

/// Title, paper and date of a journal page, and deleting it. Changes show at once.
struct JournalPageSettingsView: View {
    let journal: JournalBook
    let id: UUID
    let today: PlannerDate
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        let locale = AppLocale.current
        let calendar = PlannerLocale.calendar(locale: locale)
        NavigationStack {
            Form {
                if let page = journal.page(id) {
                    Section {
                        TextField(text: binding(page, \.title), prompt: Text("Optional")) {
                            Text("Title")
                        }
                        .font(.inter(.regular, size: 19, relativeTo: .body))
                        .foregroundStyle(Paper.ink)
                        .submitLabel(.done)
                        .accessibilityIdentifier("journal.title")
                        .listRowBackground(Paper.background)
                    } header: {
                        CapsLabel("Title")
                    } footer: {
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            Text("You can also write the title with Apple Pencil: it turns into text.")
                                .font(.inter(.regular, size: 13, relativeTo: .footnote))
                                .foregroundStyle(Paper.secondary)
                        }
                    }

                    Section {
                        HStack(spacing: 14) {
                            ForEach(PaperStyle.allCases, id: \.self) { style in
                                PaperChoice(style: style, isSelected: page.paper == style) {
                                    var changed = page
                                    changed.paper = style
                                    journal.update(changed)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .listRowBackground(Paper.background)
                    } header: {
                        CapsLabel("Paper")
                    } footer: {
                        Text("The handwriting stays where it is when the paper changes.")
                            .font(.inter(.regular, size: 13, relativeTo: .footnote))
                            .foregroundStyle(Paper.secondary)
                    }

                    Section {
                        Toggle(isOn: Binding(
                            get: { page.date != nil },
                            set: { on in
                                var changed = page
                                changed.date = on ? (page.date ?? today) : nil
                                journal.update(changed)
                            }
                        )) {
                            Text("Date")
                                .font(.inter(.regular, size: 17, relativeTo: .body))
                        }
                        .tint(Paper.ink)
                        .accessibilityIdentifier("journal.hasDate")
                        if let date = page.date {
                            DatePicker(
                                selection: Binding(
                                    get: { date.noon(in: calendar) },
                                    set: { newValue in
                                        var changed = page
                                        changed.date = PlannerDate(date: newValue, calendar: calendar)
                                        journal.update(changed)
                                    }
                                ),
                                displayedComponents: .date
                            ) {
                                Text("Day")
                            }
                            .datePickerStyle(.graphical)
                            .environment(\.locale, locale)
                            .environment(\.calendar, calendar)
                            .accessibilityIdentifier("journal.date")
                        }
                    } header: {
                        CapsLabel("Date")
                    } footer: {
                        Text("A day with a page gets a small dot on the month page. Hold a finger on a day to open its page.")
                            .font(.inter(.regular, size: 13, relativeTo: .footnote))
                            .foregroundStyle(Paper.secondary)
                    }
                    .listRowBackground(Paper.background)

                    Section {
                        Button {
                            confirmDelete = true
                        } label: {
                            Text("Delete page")
                                .font(.inter(.regular, size: 17, relativeTo: .body))
                                .foregroundStyle(Paper.ink)
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("journal.delete")
                        .listRowBackground(Paper.background)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Paper.fill)
            .navigationTitle(Text("Page"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.inter(.semibold, size: 17, relativeTo: .body))
                    }
                    .accessibilityIdentifier("journal.settings.done")
                }
            }
            .confirmationDialog(Text("Delete this page?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button {
                    dismiss()
                    onDelete()
                } label: {
                    Text("Delete")
                }
                .accessibilityIdentifier("journal.confirmDelete")
                Button(role: .cancel) {
                } label: {
                    Text("Cancel")
                }
            } message: {
                Text("Its handwriting is deleted too.")
            }
        }
        .tint(Paper.ink)
    }

    private func binding(_ page: JournalPage, _ keyPath: WritableKeyPath<JournalPage, String>) -> Binding<String> {
        Binding(
            get: { journal.page(id)?[keyPath: keyPath] ?? page[keyPath: keyPath] },
            set: { newValue in
                guard var changed = journal.page(id) else { return }
                changed[keyPath: keyPath] = newValue
                journal.update(changed)
            }
        )
    }
}

/// One kind of paper: a small sample and its name; the chosen one has a black frame.
private struct PaperChoice: View {
    let style: PaperStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                PaperSwatch(style: style)
                    .frame(width: 58, height: 80)
                    .overlay(Rectangle().stroke(isSelected ? Paper.ink : Paper.hairline, lineWidth: isSelected ? 2.5 : 1))
                name
                    .font(.inter(isSelected ? .semibold : .regular, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Paper.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("journal.paper.\(style.rawValue)")
    }

    private var name: Text {
        switch style {
        case .blank: Text("Blank")
        case .lined: Text("Lined")
        case .grid: Text("Grid")
        case .dotted: Text("Dotted")
        }
    }
}

/// A tiny sample of a paper.
private struct PaperSwatch: View {
    let style: PaperStyle

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let step = size.width / 6
            let grey = Color(white: 0.75)
            switch style {
            case .blank:
                break
            case .lined:
                var y = step
                while y < size.height {
                    context.stroke(Path { $0.move(to: CGPoint(x: 4, y: y)); $0.addLine(to: CGPoint(x: size.width - 4, y: y)) }, with: .color(grey), lineWidth: 0.8)
                    y += step
                }
            case .grid:
                var y = step
                while y < size.height {
                    context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(grey), lineWidth: 0.6)
                    y += step
                }
                var x = step
                while x < size.width {
                    context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(grey), lineWidth: 0.6)
                    x += step
                }
            case .dotted:
                var y = step
                while y < size.height {
                    var x = step
                    while x < size.width {
                        context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(Color(white: 0.55)))
                        x += step
                    }
                    y += step
                }
            }
        }
    }
}

// MARK: - Sketches

/// The sketches as small pictures, newest first (or only those pinned to one day): tap one
/// to open it; hold one to pin it to a day, unpin it or delete it.
struct SketchesView: View {
    let book: SketchBook
    let filterDay: PlannerDate?
    let canDraw: Bool
    let today: PlannerDate
    let onOpen: (UUID) -> Void
    let onNew: () -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var thumbnails: PageThumbnails
    @State private var pinning: Sketch?
    @State private var pendingDelete: Sketch?

    init(
        book: SketchBook, ink: InkController, filterDay: PlannerDate?, canDraw: Bool, today: PlannerDate,
        onOpen: @escaping (UUID) -> Void, onNew: @escaping () -> Void, onDelete: @escaping (UUID) -> Void
    ) {
        self.book = book
        self.filterDay = filterDay
        self.canDraw = canDraw
        self.today = today
        self.onOpen = onOpen
        self.onNew = onNew
        self.onDelete = onDelete
        _thumbnails = State(initialValue: PageThumbnails(ink: ink))
    }

    var body: some View {
        let locale = AppLocale.current
        let sketches = book.sorted.filter { filterDay == nil || $0.day == filterDay }
        NavigationStack {
            ScrollView {
                if sketches.isEmpty {
                    EmptyGrid(
                        systemName: "scribble",
                        title: Text("No sketches yet"),
                        message: canDraw ? Text("Tap + (or the sketch button in the top bar) for a blank page.") : Text("Sketches drawn on the iPad appear here."),
                        identifier: "sketches.empty"
                    )
                }
                LazyVGrid(columns: gridColumns, spacing: 28) {
                    ForEach(sketches) { sketch in
                        let content = PlannerPageContent(page: sketch.page, today: today, locale: locale)
                        cell(sketch, image: thumbnails.image(for: content), locale: locale)
                    }
                }
                .padding(24)
            }
            .background(Paper.fill)
            .navigationTitle(title(locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canDraw {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onNew) {
                            Image(systemName: "plus")
                                .font(.system(size: 19, weight: .semibold))
                        }
                        .accessibilityLabel(Text("New sketch"))
                        .accessibilityIdentifier("sketches.add")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.inter(.semibold, size: 17, relativeTo: .body))
                    }
                    .accessibilityIdentifier("sketches.done")
                }
            }
            .sheet(item: $pinning) { sketch in
                SketchPinView(book: book, id: sketch.id, today: today)
            }
            .confirmationDialog(
                Text("Delete this sketch?"),
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { sketch in
                Button {
                    onDelete(sketch.id)
                } label: {
                    Text("Delete")
                }
                .accessibilityIdentifier("sketches.confirmDelete")
                Button(role: .cancel) {
                } label: {
                    Text("Cancel")
                }
            }
        }
        .tint(Paper.ink)
    }

    private func title(locale: Locale) -> Text {
        guard let filterDay else { return Text("Sketches") }
        let day = JournalHeading.shortDate(filterDay, locale: locale)
        return Text("Sketches of \(day)")
    }

    private func cell(_ sketch: Sketch, image: UIImage, locale: Locale) -> some View {
        let calendar = PlannerLocale.calendar(locale: locale)
        let created = JournalHeading.shortDate(PlannerDate(date: sketch.created, calendar: calendar), locale: locale)
        let pinned = sketch.day.map { JournalHeading.shortDate($0, locale: locale) }
        return Button {
            onOpen(sketch.id)
        } label: {
            VStack(spacing: 6) {
                PageThumbnail(image: image, isCurrent: false)
                Text(verbatim: created)
                    .font(.inter(.semibold, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
                if let pinned {
                    Label {
                        Text(verbatim: pinned)
                    } icon: {
                        Image(systemName: "pin.fill")
                    }
                    .font(.inter(.regular, size: 12, relativeTo: .caption))
                    .foregroundStyle(Paper.secondary)
                    .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: [created, pinned].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityIdentifier("sketches.cell")
        .contextMenu {
            Button {
                pinning = sketch
            } label: {
                Label("Pin to a day", systemImage: "pin")
            }
            if sketch.day != nil {
                Button {
                    book.pin(sketch.id, to: nil)
                } label: {
                    Label("Unpin", systemImage: "pin.slash")
                }
            }
            Button {
                pendingDelete = sketch
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Pins a sketch to a day (its mark then shows in that day on the month page), or unpins it.
struct SketchPinView: View {
    let book: SketchBook
    let id: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(book: SketchBook, id: UUID, today: PlannerDate) {
        self.book = book
        self.id = id
        let calendar = PlannerLocale.calendar(locale: AppLocale.current)
        _date = State(initialValue: (book.sketch(id)?.day ?? today).noon(in: calendar))
    }

    var body: some View {
        let locale = AppLocale.current
        let calendar = PlannerLocale.calendar(locale: locale)
        NavigationStack {
            Form {
                Section {
                    DatePicker(selection: $date, displayedComponents: .date) {
                        Text("Day")
                    }
                    .datePickerStyle(.graphical)
                    .environment(\.locale, locale)
                    .environment(\.calendar, calendar)
                    .accessibilityIdentifier("pin.date")
                } footer: {
                    Text("The day gets a small sketch mark on the month page. Tap the mark to open the sketch.")
                        .font(.inter(.regular, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Paper.secondary)
                }
                .listRowBackground(Paper.background)

                if book.sketch(id)?.day != nil {
                    Section {
                        Button {
                            book.pin(id, to: nil)
                            dismiss()
                        } label: {
                            Text("Unpin")
                                .font(.inter(.regular, size: 17, relativeTo: .body))
                                .foregroundStyle(Paper.ink)
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("pin.remove")
                        .listRowBackground(Paper.background)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Paper.fill)
            .navigationTitle(Text("Pin to a day"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.inter(.regular, size: 17, relativeTo: .body))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        book.pin(id, to: PlannerDate(date: date, calendar: calendar))
                        dismiss()
                    } label: {
                        Text("Pin")
                            .font(.inter(.semibold, size: 17, relativeTo: .body))
                    }
                    .accessibilityIdentifier("pin.save")
                }
            }
        }
        .tint(Paper.ink)
    }
}
