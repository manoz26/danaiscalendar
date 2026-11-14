import SwiftUI
import PlannerCore

/// What the buttons of the top bar do.
struct PlannerBarActions {
    var open: (PlannerPage) -> Void
    var previous: () -> Void
    var next: () -> Void
    var today: () -> Void
    var birthdays: () -> Void
    var toBuy: () -> Void
    var journal: () -> Void
    var sketches: () -> Void
    var newSketch: () -> Void
    var newJournalPage: () -> Void
    var journalPageSettings: () -> Void
    var journalPages: () -> Void
    var pinSketch: () -> Void
    var share: (PageExportFormat) -> Void
    var settings: () -> Void
}

/// The thin bar above the page, white and black like the paper:
/// - back (to the year on a month; to the year or month she came from elsewhere),
/// - JOURNAL and SKETCHES, the notebooks outside the planner (the year and months are the
///   tabs on the right),
/// - the open page's own tools (journal: new page, page details, all pages; sketch: pin to a day),
/// - New sketch (always there on iPad), Birthdays (gift), To Buy (bag),
/// - previous/next, Today, Share and Settings.
///
/// When it does not fit (iPhone, narrow Split View), JOURNAL and SKETCHES become icons,
/// and then the rarer buttons move into a "…" menu.
struct PlannerTopBar: View {
    enum Style { case full, icons, minimal }

    let page: PlannerPage
    /// The year or month page that "back" returns to from other pages.
    let calendarPage: PlannerPage
    let locale: Locale
    let compact: Bool
    /// iPad: there is something to draw with.
    let canDraw: Bool
    let hasPrevious: Bool
    let hasNext: Bool
    let actions: PlannerBarActions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !compact {
                bar(.full)
                bar(.icons)
            }
            bar(.minimal)
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(Paper.background)
    }

    private func bar(_ style: Style) -> some View {
        HStack(spacing: 2) {
            backButton(style)
            if style != .minimal {
                sectionButtons(style)
            }

            Spacer(minLength: 4)

            if style != .minimal {
                pageTools
                if canDraw {
                    BarIconButton(systemName: "pencil.tip.crop.circle.badge.plus", identifier: "nav.newSketch", compact: compact, action: actions.newSketch)
                        .accessibilityLabel(Text("New sketch"))
                }
            }

            BarIconButton(systemName: "gift", identifier: "nav.birthdays", compact: compact, action: actions.birthdays)
                .accessibilityLabel(Text("Birthdays"))

            BarIconButton(systemName: page == .toBuy ? "bag.fill" : "bag", identifier: "nav.tobuy", compact: compact, action: actions.toBuy)
                .accessibilityLabel(Text("To buy"))
                .accessibilityAddTraits(page == .toBuy ? .isSelected : [])

            if showsArrows {
                BarIconButton(systemName: "chevron.left", identifier: "nav.previous", compact: compact, action: actions.previous)
                    .disabled(!hasPrevious)
                    .opacity(hasPrevious ? 1 : 0.3)
                    .accessibilityLabel(previousLabel)

                BarIconButton(systemName: "chevron.right", identifier: "nav.next", compact: compact, action: actions.next)
                    .disabled(!hasNext)
                    .opacity(hasNext ? 1 : 0.3)
                    .accessibilityLabel(nextLabel)
            }

            Button(action: actions.today) {
                Text("Today")
                    .font(.inter(.semibold, size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, compact ? 8 : 12)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Paper.ink, lineWidth: 1.2))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, compact ? 2 : 6)
            .accessibilityIdentifier("nav.today")

            if style == .minimal {
                moreMenu
            } else {
                shareMenu
                SettingsButton(compact: compact, action: actions.settings)
            }
        }
        .padding(.horizontal, compact ? 4 : 8)
    }

    // MARK: - Parts

    @ViewBuilder
    private func backButton(_ style: Style) -> some View {
        switch page {
        case .month(let month):
            BackButton(label: String(month.year), identifier: "nav.year") {
                actions.open(.year(month.year))
            }
            .accessibilityLabel(Text("Back to the year"))
            .accessibilityValue(Text(verbatim: String(month.year)))
        case .toBuy, .journal, .sketch:
            // On narrow bars journal pages and sketches (which also have arrows or tools) keep only the chevron.
            BackButton(label: style == .minimal && page.isNotebookPage ? "" : backLabel, identifier: "nav.back") {
                actions.open(calendarPage)
            }
            .accessibilityLabel(Text("Back"))
            .accessibilityValue(Text(verbatim: backLabel))
        case .year:
            EmptyView()
        }
    }

    /// JOURNAL and SKETCHES: words when there is room, icons otherwise. The open one is
    /// black and underlined.
    @ViewBuilder
    private func sectionButtons(_ style: Style) -> some View {
        let journalOpen = if case .journal = page { true } else { false }
        let sketchOpen = if case .sketch = page { true } else { false }
        HStack(spacing: style == .full ? 6 : 2) {
            SectionButton(
                title: String(localized: "Journal", comment: "The journal ('Τετράδιο'): free pages to write on. Top bar button, printed in capitals."),
                systemName: "book.closed", identifier: "nav.journal",
                isOpen: journalOpen, asIcon: style == .icons, compact: compact, action: actions.journal
            )
            SectionButton(
                title: String(localized: "Sketches", comment: "The sketches: top bar button (printed in capitals) and title of their grid."),
                systemName: "scribble", identifier: "nav.sketches",
                isOpen: sketchOpen, asIcon: style == .icons, compact: compact, action: actions.sketches
            )
        }
        .padding(.leading, 6)
    }

    /// The open page's own tools.
    @ViewBuilder
    private var pageTools: some View {
        switch page {
        case .journal:
            if canDraw {
                BarIconButton(systemName: "plus.rectangle.portrait", identifier: "nav.journal.new", compact: compact, action: actions.newJournalPage)
                    .accessibilityLabel(Text("New page"))
            }
            BarIconButton(systemName: "doc.badge.gearshape", identifier: "nav.journal.settings", compact: compact, action: actions.journalPageSettings)
                .accessibilityLabel(Text("Page title, paper and date"))
            BarIconButton(systemName: "square.grid.2x2", identifier: "nav.journal.pages", compact: compact, action: actions.journalPages)
                .accessibilityLabel(Text("All pages"))
        case .sketch:
            BarIconButton(systemName: "pin", identifier: "nav.sketch.pin", compact: compact, action: actions.pinSketch)
                .accessibilityLabel(Text("Pin to a day"))
        default:
            EmptyView()
        }
    }

    private var shareMenu: some View {
        Menu {
            shareButtons
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Paper.ink)
                .frame(width: compact ? 38 : 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Share page"))
        .accessibilityIdentifier("nav.share")
    }

    @ViewBuilder
    private var shareButtons: some View {
        Button {
            actions.share(.pdf)
        } label: {
            Label {
                Text("PDF")
            } icon: {
                Image(systemName: "doc.richtext")
            }
        }
        .accessibilityIdentifier("share.pdf")
        Button {
            actions.share(.image)
        } label: {
            Label {
                Text("Image")
            } icon: {
                Image(systemName: "photo")
            }
        }
        .accessibilityIdentifier("share.image")
    }

    /// Narrow bars: the notebooks, the page's tools, Share and Settings.
    private var moreMenu: some View {
        Menu {
            Button(action: actions.journal) {
                Label("Journal", systemImage: "book.closed")
            }
            .accessibilityIdentifier("nav.journal")
            Button(action: actions.sketches) {
                Label("Sketches", systemImage: "scribble")
            }
            .accessibilityIdentifier("nav.sketches")
            if canDraw {
                Button(action: actions.newSketch) {
                    Label("New sketch", systemImage: "pencil.tip.crop.circle.badge.plus")
                }
                .accessibilityIdentifier("nav.newSketch")
            }
            switch page {
            case .journal:
                Section {
                    if canDraw {
                        Button(action: actions.newJournalPage) {
                            Label("New page", systemImage: "plus.rectangle.portrait")
                        }
                    }
                    Button(action: actions.journalPageSettings) {
                        Label("Page title, paper and date", systemImage: "doc.badge.gearshape")
                    }
                    Button(action: actions.journalPages) {
                        Label("All pages", systemImage: "square.grid.2x2")
                    }
                }
            case .sketch:
                Button(action: actions.pinSketch) {
                    Label("Pin to a day", systemImage: "pin")
                }
            default:
                EmptyView()
            }
            Menu {
                shareButtons
            } label: {
                Label("Share page", systemImage: "square.and.arrow.up")
            }
            Button(action: actions.settings) {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("settings.button")
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Paper.ink)
                .frame(width: compact ? 38 : 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("More"))
        .accessibilityIdentifier("nav.more")
    }

    // MARK: - Texts

    private var showsArrows: Bool {
        if case .journal = page { return true }
        return page.isCalendarPage
    }

    private var previousLabel: Text {
        switch page {
        case .year: Text("Previous year")
        case .month: Text("Previous month")
        default: Text("Previous page")
        }
    }

    private var nextLabel: Text {
        switch page {
        case .year: Text("Next year")
        case .month: Text("Next month")
        default: Text("Next page")
        }
    }

    /// Where "back" goes from the To Buy page, journal pages and sketches: the month's name, or the year.
    private var backLabel: String {
        switch calendarPage {
        case .month(let month): CalendarNames.monthName(month.month, locale: locale)
        case .year(let year): String(year)
        default: ""
        }
    }
}

/// JOURNAL or SKETCHES in the top bar: small capitals with letter-spacing like the printed
/// labels, grey when closed, black and underlined when open. As an icon when space is short.
private struct SectionButton: View {
    let title: String
    let systemName: String
    let identifier: String
    let isOpen: Bool
    let asIcon: Bool
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if asIcon {
                    Image(systemName: systemName)
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: compact ? 38 : 44, height: 44)
                } else {
                    Text(verbatim: PlannerText.uppercased(title, locale: AppLocale.current))
                        .font(.inter(isOpen ? .bold : .semibold, size: 13, relativeTo: .subheadline))
                        .tracking(1.4)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) {
                            if isOpen {
                                Rectangle()
                                    .fill(Paper.ink)
                                    .frame(height: 2)
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 8)
                            }
                        }
                }
            }
            .foregroundStyle(isOpen ? Paper.ink : Paper.tabLabel)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// A chevron and a name, e.g. back to "2026".
private struct BackButton: View {
    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                Text(verbatim: label)
                    .font(.inter(.semibold, size: 18, relativeTo: .headline))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(Paper.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

private struct BarIconButton: View {
    let systemName: String
    let identifier: String
    /// Narrower on iPhone, where the bar has less room.
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Paper.ink)
                .frame(width: compact ? 38 : 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// Small gear that opens Settings.
struct SettingsButton: View {
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(Paper.ink)
                .frame(width: compact ? 38 : 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Settings"))
        .accessibilityIdentifier("settings.button")
    }
}

/// Vertical tabs on the right edge, like the coloured tabs of a paper planner but in
/// greys: the year, then its 12 months. The open page's tab is white, as if part of it.
///
/// On the To Buy page they show the year she came from, with no tab open. Journal pages
/// and sketches have no tabs: they are notebooks of their own and get the whole width.
struct PlannerTabs: View {
    let page: PlannerPage
    /// The year whose tabs are shown.
    let year: Int
    let locale: Locale
    let compact: Bool
    let onOpen: (PlannerPage) -> Void

    static func width(compact: Bool) -> CGFloat { compact ? 26 : 34 }

    var body: some View {
        VStack(spacing: 2) {
            tab(
                label: String(year), spoken: String(year),
                target: .year(year), identifier: "tab.year"
            )
            ForEach(1...12, id: \.self) { number in
                tab(
                    label: CalendarNames.shortMonth(number, locale: locale),
                    spoken: CalendarNames.monthName(number, locale: locale),
                    target: .month(YearMonth(year: year, month: number)),
                    identifier: "tab.month.\(number)"
                )
            }
        }
        .padding(.vertical, 2)
        .frame(width: Self.width(compact: compact))
        .background(Paper.background)
    }

    private func tab(label: String, spoken: String, target: PlannerPage, identifier: String) -> some View {
        let isOpen = page == target
        return Button {
            onOpen(target)
        } label: {
            ZStack {
                isOpen ? Paper.background : Paper.tab
                Text(verbatim: label)
                    .font(.inter(isOpen ? .bold : .semibold, size: compact ? 9 : 11))
                    .tracking(compact ? 0.6 : 1)
                    .foregroundStyle(isOpen ? Paper.ink : Paper.tabLabel)
                    .lineLimit(1)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: spoken))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

extension PlannerPage {
    var isYear: Bool {
        if case .year = self { true } else { false }
    }
}
