import SwiftUI

/// Settings sheet. For now only the version; tapping it 5 times opens Diagnostics.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var versionTaps = 0
    @State private var lastVersionTap = Date.distantPast
    @State private var showDiagnostics = false

    var body: some View {
        NavigationStack {
            List {
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
                            .foregroundStyle(check.ok ? Paper.secondary : Paper.ink)
                    }
                    .font(.inter(check.ok ? .regular : .semibold, size: 15, relativeTo: .subheadline))
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
