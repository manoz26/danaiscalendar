import PlannerCore
import SwiftUI
import UIKit

/// The two notebooks of the iPhone's Journal tab.
enum PhoneNotebook: String, CaseIterable, Identifiable {
    case journal, sketches

    var id: String { rawValue }

    var title: String {
        switch self {
        case .journal: String(localized: "Journal", comment: "The journal ('Τετράδιο'): free pages to write on. Top bar button, printed in capitals.")
        case .sketches: String(localized: "Sketches", comment: "The sketches: top bar button (printed in capitals) and title of their grid.")
        }
    }
}

/// The iPhone's Journal tab: the journal's pages and the sketches as small pictures. A tap
/// opens one in full, to read and zoom. They are written on the iPad.
struct PhoneNotebooksView: View {
    let journal: JournalBook
    let sketches: SketchBook
    let today: PlannerDate
    let onOpen: (PlannerPage) -> Void
    let onSettings: () -> Void

    @AppStorage(PhoneDefaults.notebook) private var selectedName = PhoneNotebook.journal.rawValue
    /// Drawn again every time the tab's grid appears, so the pictures are never stale.
    @State private var thumbnails: PageThumbnails

    init(
        journal: JournalBook, sketches: SketchBook, ink: InkController, today: PlannerDate,
        onOpen: @escaping (PlannerPage) -> Void, onSettings: @escaping () -> Void
    ) {
        self.journal = journal
        self.sketches = sketches
        self.today = today
        self.onOpen = onOpen
        self.onSettings = onSettings
        _thumbnails = State(initialValue: PageThumbnails(ink: ink))
    }

    private static let columns = [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 16, alignment: .top)]

    var body: some View {
        let locale = AppLocale.current
        let selected = PhoneNotebook(rawValue: selectedName) ?? .journal
        VStack(spacing: 0) {
            PhoneSegments(
                items: PhoneNotebook.allCases.map { notebook in
                    PhoneSegments<PhoneNotebook>.Item(
                        value: notebook, title: notebook.title, identifier: "phone.notebooks.\(notebook.rawValue)"
                    )
                },
                selection: selected,
                onSelect: { selectedName = $0.rawValue },
                onSettings: onSettings
            )
            ScrollView {
                switch selected {
                case .journal:
                    journalGrid(locale: locale)
                case .sketches:
                    sketchGrid(locale: locale)
                }
            }
            .background(Paper.fill)
        }
    }

    @ViewBuilder
    private func journalGrid(locale: Locale) -> some View {
        let pages = journal.pages
        let data = PlannerData(journal: journal.journal)
        if pages.isEmpty {
            EmptyGrid(
                systemName: "book.closed",
                title: Text("No pages yet"),
                message: Text("Pages written on the iPad appear here."),
                identifier: "journal.empty"
            )
        }
        LazyVGrid(columns: Self.columns, spacing: 22) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                let content = PlannerPageContent(page: page.page, today: today, locale: locale, data: data)
                let caption = JournalPagesView.caption(page, number: index + 1, locale: locale)
                Button {
                    onOpen(page.page)
                } label: {
                    VStack(spacing: 6) {
                        PageThumbnail(image: thumbnails.image(for: content), isCurrent: false)
                        Text(verbatim: caption)
                            .font(.inter(.semibold, size: 13, relativeTo: .footnote))
                            .foregroundStyle(Paper.ink)
                            .lineLimit(1)
                        Text(verbatim: String(index + 1))
                            .font(.inter(.regular, size: 11, relativeTo: .caption2))
                            .foregroundStyle(Paper.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "\(index + 1). \(caption)"))
                .accessibilityIdentifier("journal.pages.cell")
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func sketchGrid(locale: Locale) -> some View {
        let all = sketches.sorted
        let calendar = PlannerLocale.calendar(locale: locale)
        if all.isEmpty {
            EmptyGrid(
                systemName: "scribble",
                title: Text("No sketches yet"),
                message: Text("Sketches drawn on the iPad appear here."),
                identifier: "sketches.empty"
            )
        }
        LazyVGrid(columns: Self.columns, spacing: 22) {
            ForEach(all) { sketch in
                let content = PlannerPageContent(page: sketch.page, today: today, locale: locale)
                let created = JournalHeading.shortDate(PlannerDate(date: sketch.created, calendar: calendar), locale: locale)
                let pinned = sketch.day.map { JournalHeading.shortDate($0, locale: locale) }
                Button {
                    onOpen(sketch.page)
                } label: {
                    VStack(spacing: 6) {
                        PageThumbnail(image: thumbnails.image(for: content), isCurrent: false)
                        Text(verbatim: created)
                            .font(.inter(.semibold, size: 13, relativeTo: .footnote))
                            .foregroundStyle(Paper.ink)
                            .lineLimit(1)
                        if let pinned {
                            Label {
                                Text(verbatim: pinned)
                            } icon: {
                                Image(systemName: "pin.fill")
                            }
                            .font(.inter(.regular, size: 11, relativeTo: .caption2))
                            .foregroundStyle(Paper.secondary)
                            .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: [created, pinned].compactMap { $0 }.joined(separator: ", ")))
                .accessibilityIdentifier("sketches.cell")
            }
        }
        .padding(16)
    }
}
