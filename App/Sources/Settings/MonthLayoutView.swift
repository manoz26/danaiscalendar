import PlannerCore
import SwiftUI

/// Settings → Month page: which box is above the days and which two are under them (or
/// none), her titles, and how many lines the lists have, with this month's page as it will
/// look. It is used for this month and the next ones, or for every month. The handwriting
/// moves with its box, day or line (`LayoutMigration`); a hidden box keeps its handwriting.
struct MonthLayoutSettingsView: View {
    let settings: SettingsBook

    @Environment(\.dismiss) private var dismiss
    @State private var draft: MonthLayout
    @State private var confirmStandard = false
    private let month: YearMonth
    private let today: PlannerDate

    init(settings: SettingsBook) {
        self.settings = settings
        let calendar = PlannerLocale.calendar(locale: AppLocale.current)
        let today = PlannerDate(date: AppClock.now, calendar: calendar)
        self.today = today
        month = today.yearMonth
        _draft = State(initialValue: settings.settings.monthLayouts.layout(for: today.yearMonth))
    }

    var body: some View {
        let labels = PlannerPageContent.labels
        List {
            Section {
                PrintedPage(
                    template: MonthPageTemplate.make(month: month, layout: draft, locale: AppLocale.current, labels: labels, today: today),
                    look: settings.settings.look, width: 230
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Preview of the month page"))
                .accessibilityIdentifier("month.preview")
                .listRowBackground(Paper.fill)
            }

            Section {
                slotPicker(.top, choices: [.goals, .memo, .custom, nil], label: Text("Box"))
            } header: {
                CapsLabel("Above the days")
            }

            Section {
                slotPicker(.left, choices: [.todo, .memo, .goals, .custom, nil], label: Text("Left"))
                slotPicker(.right, choices: [.todo, .memo, .goals, .custom, nil], label: Text("Right"))
                Stepper(value: Binding(get: { draft.rows }, set: { draft.rows = $0; draft = draft.validated }), in: MonthLayout.rowRange) {
                    Text("Lines: \(draft.rows)", comment: "Settings → Month page: how many ruled lines the lists under the days have.")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.ink)
                }
                .accessibilityIdentifier("month.rows")
                .listRowBackground(Paper.background)
            } header: {
                CapsLabel("Under the days")
            }

            Section {
                ForEach(MonthBoxKind.allCases.filter { draft.slot(of: $0) != nil }, id: \.self) { kind in
                    TextField(text: titleBinding(kind), prompt: Text(verbatim: labels.label(of: kind, in: .standard))) {
                        Self.name(of: kind)
                    }
                    .font(.inter(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Paper.ink)
                    .submitLabel(.done)
                    .accessibilityIdentifier("month.title.\(kind.rawValue)")
                    .listRowBackground(Paper.background)
                }
            } header: {
                CapsLabel("Titles")
            } footer: {
                footnote(Text("Empty: the usual name."))
            }

            Section {
                applyButton(Text("This month and the next ones"), identifier: "month.applyFromHere") {
                    apply(from: month)
                }
                applyButton(Text("All months"), identifier: "month.applyAll") {
                    apply(from: nil)
                }
            } header: {
                CapsLabel("Use it for")
            } footer: {
                footnote(Text("Your handwriting moves with its box, day or line. A box you hide keeps its handwriting and gets it back when you show it again."))
            }

            Section {
                applyButton(Text("Back to the usual page"), identifier: "month.standard") {
                    confirmStandard = true
                }
            }
        }
        .listStyle(.insetGrouped)
        .textCase(nil)
        .scrollContentBackground(.hidden)
        .background(Paper.fill)
        .navigationTitle(Text("Month page"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(Text("Back to the usual page?"), isPresented: $confirmStandard, titleVisibility: .visible) {
            Button {
                draft = .standard
                apply(from: nil)
            } label: {
                Text("All months")
            }
            .accessibilityIdentifier("month.confirmStandard")
            Button(role: .cancel) {} label: { Text("Cancel") }
        } message: {
            Text("Goals above the days, the to-do list and the notes under them with 9 lines, for every month.")
        }
    }

    private func slotPicker(_ slot: MonthSlot, choices: [MonthBoxKind?], label: Text) -> some View {
        Picker(selection: Binding(get: { draft.kind(in: slot) }, set: { draft.set($0, in: slot) })) {
            ForEach(choices, id: \.self) { kind in
                Group {
                    if let kind {
                        Self.name(of: kind)
                    } else {
                        Text("Nothing")
                    }
                }
                .tag(kind)
            }
        } label: {
            label
                .font(.inter(.regular, size: 17, relativeTo: .body))
                .foregroundStyle(Paper.ink)
        }
        .accessibilityIdentifier("month.slot.\(slot.rawValue)")
        .listRowBackground(Paper.background)
    }

    private func titleBinding(_ kind: MonthBoxKind) -> Binding<String> {
        Binding(
            get: { draft.titles[kind.rawValue] ?? "" },
            set: { draft.titles[kind.rawValue] = String($0.prefix(MonthLayout.maxTitleLength)) }
        )
    }

    private func applyButton(_ title: Text, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(.inter(.regular, size: 17, relativeTo: .body))
                .foregroundStyle(Paper.ink)
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier(identifier)
        .listRowBackground(Paper.background)
    }

    private func footnote(_ text: Text) -> some View {
        text
            .font(.inter(.regular, size: 13, relativeTo: .footnote))
            .foregroundStyle(Paper.secondary)
    }

    private func apply(from first: YearMonth?) {
        var layouts = settings.settings.monthLayouts
        layouts.set(draft.validated, from: first)
        settings.setMonthLayouts(layouts)
        AppLog.info("Month page layout chosen \(first == nil ? "for every month" : "from \(first!)")")
        dismiss()
    }

    static func name(of kind: MonthBoxKind) -> Text {
        switch kind {
        case .goals: Text("Goals")
        case .todo: Text("To do list")
        case .memo: Text("Memo")
        case .custom: Text("Own box")
        }
    }
}
