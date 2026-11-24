import SwiftUI
import UIKit
import PlannerCore

/// Settings sheet: drawing with a finger and the pens and colours (iPad), the paper, the
/// lock, the Apple Calendar (events in the cells, which calendars), iCloud, the backup, and
/// the version; tapping the version 5 times opens Diagnostics.
struct SettingsView: View {
    let calendar: CalendarBook
    let sync: CloudSync
    let settings: SettingsBook
    let ink: InkController
    let lock: AppLock

    @Environment(\.dismiss) private var dismiss
    @AppStorage(InkDefaults.drawWithFinger) private var drawWithFinger = false
    @State private var versionTaps = 0
    @State private var lastVersionTap = Date.distantPast
    @State private var showDiagnostics = false

    var body: some View {
        NavigationStack {
            List {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Section {
                        NavigationLink {
                            PensSettingsView(settings: settings, ink: ink)
                        } label: {
                            Text("Pens and colours")
                                .font(.inter(.regular, size: 17, relativeTo: .body))
                                .foregroundStyle(Paper.ink)
                        }
                        .accessibilityIdentifier("settings.pens")
                        .listRowBackground(Paper.background)
                        Toggle(isOn: $drawWithFinger) {
                            Text("Draw with finger too")
                                .font(.inter(.regular, size: 17, relativeTo: .body))
                                .foregroundStyle(Paper.ink)
                        }
                        .tint(Paper.ink)
                        .accessibilityIdentifier("settings.drawWithFinger")
                        .listRowBackground(Paper.background)
                    } header: {
                        CapsLabel("Apple Pencil")
                    } footer: {
                        Text("When this is off, only Apple Pencil writes and one finger moves the page. When it is on, your finger writes too and two fingers move the page.")
                            .font(.inter(.regular, size: 13, relativeTo: .footnote))
                            .foregroundStyle(Paper.secondary)
                    }
                }

                Section {
                    NavigationLink {
                        PaperSettingsView(settings: settings)
                    } label: {
                        LabeledContent {
                            Group {
                                if settings.settings.paper.dark {
                                    Text("Dark")
                                } else {
                                    Text("White")
                                }
                            }
                            .foregroundStyle(Paper.secondary)
                        } label: {
                            Text("Paper")
                                .foregroundStyle(Paper.ink)
                        }
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                    }
                    .accessibilityIdentifier("settings.paper")
                    .listRowBackground(Paper.background)
                } header: {
                    CapsLabel("Pages")
                }

                LockSection(settings: settings, lock: lock)

                calendarSection

                ICloudSection(sync: sync)

                BackupSection(sync: sync)

                Section {
                    Button(action: versionTapped) {
                        HStack {
                            Text("Version")
                                .font(.inter(.regular, size: 17, relativeTo: .body))
                                .foregroundStyle(Paper.ink)
                            Spacer()
                            Text(verbatim: AppInfo.versionAndBuild)
                                .font(.inter(.regular, size: 17, relativeTo: .body))
                                .foregroundStyle(Paper.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.version")
                    .listRowBackground(Paper.background)
                } header: {
                    CapsLabel("About")
                }
            }
            .listStyle(.insetGrouped)
            .textCase(nil)
            .scrollContentBackground(.hidden)
            .background(Paper.fill)
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.inter(.semibold, size: 17, relativeTo: .body))
                    }
                    .accessibilityIdentifier("settings.done")
                }
            }
            .navigationDestination(isPresented: $showDiagnostics) {
                DiagnosticsView()
            }
        }
        .tint(Paper.ink)
        #if DEBUG
        .overlay(alignment: .topLeading) {
            // The last backup made, for the UI tests.
            Text(verbatim: sync.debugLastBackup)
                .font(.system(size: 2))
                .foregroundStyle(.clear)
                .allowsHitTesting(false)
                .accessibilityIdentifier("debug.lastBackup")
        }
        #endif
    }

    /// Apple Calendar: connect it; then events in the cells (on or off) and which calendars.
    @ViewBuilder
    private var calendarSection: some View {
        Section {
            switch calendar.access {
            case .allowed:
                Toggle(isOn: Binding(get: { calendar.showInCells }, set: { calendar.showInCells = $0 })) {
                    Text("Show events in the cells")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.ink)
                }
                .tint(Paper.ink)
                .accessibilityIdentifier("settings.showEvents")
                .listRowBackground(Paper.background)
                NavigationLink {
                    CalendarChoiceView(book: calendar)
                } label: {
                    LabeledContent {
                        Text(verbatim: "\(calendar.calendars.filter { calendar.isShown($0.id) }.count) / \(calendar.calendars.count)")
                            .foregroundStyle(Paper.secondary)
                    } label: {
                        Text("Calendars")
                            .foregroundStyle(Paper.ink)
                    }
                    .font(.inter(.regular, size: 17, relativeTo: .body))
                }
                .accessibilityIdentifier("settings.calendars")
                .listRowBackground(Paper.background)
            case .notAsked:
                Button {
                    Task {
                        await calendar.requestAccess()
                    }
                } label: {
                    Text("Connect Apple Calendar")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.ink)
                }
                .accessibilityIdentifier("settings.connectCalendar")
                .listRowBackground(Paper.background)
            case .writeOnly, .denied, .restricted:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.ink)
                }
                .accessibilityIdentifier("settings.openSettings")
                .listRowBackground(Paper.background)
            }
        } header: {
            CapsLabel("Apple Calendar")
        } footer: {
            Group {
                switch calendar.access {
                case .allowed:
                    Text("Events are printed in the day cells, under your handwriting. Turn this off for purely handwritten pages; the day's list still shows them.")
                case .notAsked:
                    Text("The events of Apple Calendar (and of Google or Outlook accounts on this device) are printed in the day cells, under your handwriting.")
                case .writeOnly, .denied, .restricted:
                    Text("To see your events here, allow full access to Danai's Calendar in the Settings app, under Privacy & Security → Calendars.")
                }
            }
            .font(.inter(.regular, size: 13, relativeTo: .footnote))
            .foregroundStyle(Paper.secondary)
        }
    }

    /// Five taps, each within a few seconds of the last, open the hidden Diagnostics screen.
    private func versionTapped() {
        let now = Date()
        versionTaps = now.timeIntervalSince(lastVersionTap) < 4 ? versionTaps + 1 : 1
        lastVersionTap = now
        if versionTaps >= 5 {
            versionTaps = 0
            AppLog.info("Diagnostics opened")
            showDiagnostics = true
        }
    }
}

/// Which calendars' events the pages print, grouped by account; a tick for each shown one.
struct CalendarChoiceView: View {
    let book: CalendarBook

    private struct Account: Identifiable {
        let source: String
        let calendars: [EventCalendar]
        var id: String { source }
    }

    var body: some View {
        let groups = Dictionary(grouping: book.calendars, by: \.source)
            .map { Account(source: $0.key, calendars: $0.value) }
            .sorted { $0.source.localizedStandardCompare($1.source) == .orderedAscending }
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.calendars.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { item in
                        Button {
                            book.setShown(!book.isShown(item.id), calendar: item.id)
                        } label: {
                            HStack {
                                Text(verbatim: item.title)
                                    .font(.inter(.regular, size: 17, relativeTo: .body))
                                    .foregroundStyle(Paper.ink)
                                Spacer()
                                if book.isShown(item.id) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Paper.ink)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(book.isShown(item.id) ? .isSelected : [])
                        .accessibilityIdentifier("calendars.row")
                        .listRowBackground(Paper.background)
                    }
                } header: {
                    CapsLabel(verbatim: group.source)
                }
            }
        }
        .listStyle(.insetGrouped)
        .textCase(nil)
        .scrollContentBackground(.hidden)
        .background(Paper.fill)
        .navigationTitle(Text("Calendars"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Text("The pages print the events of the ticked calendars.")
                .font(.inter(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(Paper.secondary)
                .padding()
        }
    }
}

/// Hidden screen with the local log, so problems on a real iPad can be seen without a Mac.
struct DiagnosticsView: View {
    @State private var snapshot: DiagnosticsSnapshot?

    var body: some View {
        List {
            Section {
                Text(verbatim: snapshot?.summary ?? "")
                    .font(.inter(.regular, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Paper.ink)
                    .textSelection(.enabled)
                    .listRowBackground(Paper.background)
                    .accessibilityIdentifier("diagnostics.summary")
            } header: {
                CapsLabel("This device")
            }

            Section {
                ForEach(snapshot?.checks ?? []) { check in
                    HStack {
                        Text(check.title)
                            .foregroundStyle(Paper.ink)
                        Spacer()
                        Text(check.status)
                            .foregroundStyle(check.isProblem ? Paper.ink : Paper.secondary)
                    }
                    .font(.inter(check.isProblem ? .semibold : .regular, size: 15, relativeTo: .subheadline))
                    .listRowBackground(Paper.background)
                }
            } header: {
                CapsLabel("Checks")
            }

            Section {
                if let url = snapshot?.shareURL {
                    ShareLink(item: url) {
                        Label {
                            Text("Share log")
                                .font(.inter(.medium, size: 17, relativeTo: .body))
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(Paper.ink)
                    }
                    .accessibilityIdentifier("diagnostics.share")
                    .listRowBackground(Paper.background)
                }
                logText
                    .font(.inter(.regular, size: 12, relativeTo: .caption))
                    .foregroundStyle(Paper.ink)
                    .textSelection(.enabled)
                    .listRowBackground(Paper.background)
                    .accessibilityIdentifier("diagnostics.log")
            } header: {
                CapsLabel("Log")
            }
        }
        .listStyle(.insetGrouped)
        .textCase(nil)
        .scrollContentBackground(.hidden)
        .background(Paper.fill)
        .navigationTitle(Text("Diagnostics"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            snapshot = await DiagnosticsSnapshot.make()
        }
        .refreshable {
            snapshot = await DiagnosticsSnapshot.make()
        }
    }

    private var logText: Text {
        guard let snapshot else { return Text("Loading…") }
        if snapshot.logTail.isEmpty { return Text("The log is empty.") }
        return Text(verbatim: snapshot.logTail)
    }
}
