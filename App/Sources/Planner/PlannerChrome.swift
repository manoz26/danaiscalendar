import SwiftUI
import PlannerCore

/// The thin bar above the page: back (to the year on a month, to the page she came from
/// on the To Buy page), Birthdays (gift) and To Buy (bag), previous/next, Today and
/// Settings. White and black like the paper.
struct PlannerTopBar: View {
    let page: PlannerPage
    /// The year or month page the To Buy page goes back to.
    let calendarPage: PlannerPage
    let locale: Locale
    let compact: Bool
    let onOpen: (PlannerPage) -> Void
    let onToday: () -> Void
    let onBirthdays: () -> Void
    let onToBuy: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            switch page {
            case .month(let month):
                BackButton(label: String(month.year), identifier: "nav.year") {
                    onOpen(.year(month.year))
                }
                .accessibilityLabel(Text("Back to the year"))
                .accessibilityValue(Text(verbatim: String(month.year)))
            case .toBuy:
                BackButton(label: backLabel, identifier: "nav.back") {
                    onOpen(calendarPage)
                }
                .accessibilityLabel(Text("Back"))
                .accessibilityValue(Text(verbatim: backLabel))
            case .year:
                EmptyView()
            }

            Spacer(minLength: 4)

            BarIconButton(systemName: "gift", identifier: "nav.birthdays", compact: compact, action: onBirthdays)
                .accessibilityLabel(Text("Birthdays"))

            BarIconButton(systemName: page == .toBuy ? "bag.fill" : "bag", identifier: "nav.tobuy", compact: compact, action: onToBuy)
                .accessibilityLabel(Text("To buy"))
                .accessibilityAddTraits(page == .toBuy ? .isSelected : [])

            if page.isCalendarPage {
                BarIconButton(systemName: "chevron.left", identifier: "nav.previous", compact: compact) {
                    onOpen(page.previous)
                }
                .accessibilityLabel(page.isYear ? Text("Previous year") : Text("Previous month"))

                BarIconButton(systemName: "chevron.right", identifier: "nav.next", compact: compact) {
                    onOpen(page.next)
                }
                .accessibilityLabel(page.isYear ? Text("Next year") : Text("Next month"))
            }

            Button(action: onToday) {
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

            SettingsButton(compact: compact, action: onSettings)
        }
        .padding(.horizontal, compact ? 4 : 8)
        .frame(height: 52)
        .background(Paper.background)
    }

    /// Where the To Buy page goes back to: the month's name, or the year.
    private var backLabel: String {
        switch calendarPage {
        case .month(let month): CalendarNames.monthName(month.month, locale: locale)
        case .year(let year): String(year)
        case .toBuy: ""
        }
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
/// On the To Buy page they show the year she came from, with no tab open.
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
