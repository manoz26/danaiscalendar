import SwiftUI
import PlannerCore

/// The thin bar above the page: back to the year (on a month), previous/next,
/// Today, and Settings. White and black like the paper.
struct PlannerTopBar: View {
    let page: PlannerPage
    let onOpen: (PlannerPage) -> Void
    let onToday: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            if case .month(let month) = page {
                Button {
                    onOpen(page.yearPage)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                        Text(verbatim: String(month.year))
                            .font(.inter(.semibold, size: 18, relativeTo: .headline))
                    }
                    .foregroundStyle(Paper.ink)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back to the year"))
                .accessibilityValue(Text(verbatim: String(month.year)))
                .accessibilityIdentifier("nav.year")
            }

            Spacer(minLength: 8)

            BarIconButton(systemName: "chevron.left", identifier: "nav.previous") {
                onOpen(page.previous)
            }
            .accessibilityLabel(page.isYear ? Text("Previous year") : Text("Previous month"))

            BarIconButton(systemName: "chevron.right", identifier: "nav.next") {
                onOpen(page.next)
            }
            .accessibilityLabel(page.isYear ? Text("Next year") : Text("Next month"))

            Button(action: onToday) {
                Text("Today")
                    .font(.inter(.semibold, size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Paper.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Paper.ink, lineWidth: 1.2))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .accessibilityIdentifier("nav.today")

            SettingsButton(action: onSettings)
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .background(Paper.background)
    }
}

private struct BarIconButton: View {
    let systemName: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Paper.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// Small gear that opens Settings.
struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(Paper.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Settings"))
        .accessibilityIdentifier("settings.button")
    }
}

/// Vertical tabs on the right edge, like the coloured tabs of a paper planner but in
/// greys: the year, then its 12 months. The open page's tab is white, as if part of it.
struct PlannerTabs: View {
    let page: PlannerPage
    let locale: Locale
    let compact: Bool
    let onOpen: (PlannerPage) -> Void

    static func width(compact: Bool) -> CGFloat { compact ? 26 : 34 }

    var body: some View {
        let year = page.year
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
