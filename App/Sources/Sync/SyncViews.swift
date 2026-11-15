import SwiftUI
import UniformTypeIdentifiers
import PlannerCore

/// The discreet iCloud mark in a corner of the page: "Downloading from iCloud…" while the
/// open page is still on its way, a small cloud while a sync takes a while, and a cloud
/// with a "!" if files did not sync. Nothing when all is well, or without iCloud.
struct SyncBadge: View {
    let sync: CloudSync
    let page: PlannerPage
    @State private var showsActivity = false

    var body: some View {
        content
            .task(id: sync.status) {
                showsActivity = false
                guard sync.status == .syncing else { return }
                try? await Task.sleep(for: .seconds(1.5))
                if !Task.isCancelled, sync.status == .syncing {
                    showsActivity = true
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if sync.isDownloading(page) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Paper.secondary)
                Text("Downloading from iCloud…")
                    .font(.inter(.medium, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Paper.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Paper.background))
            .overlay(Capsule().stroke(Paper.hairline, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sync.downloading")
        } else if sync.status == .problem {
            mark("exclamationmark.icloud", label: Text("Some files did not sync with iCloud"))
        } else if showsActivity {
            mark("arrow.triangle.2.circlepath.icloud", label: Text("Syncing with iCloud"))
        }
    }

    private func mark(_ systemName: String, label: Text) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Paper.secondary)
            .padding(6)
            .background(Circle().fill(Paper.background.opacity(0.9)))
            .accessibilityLabel(label)
            .accessibilityIdentifier("sync.status")
    }
}

/// Settings → iCloud: whether the pages sync, and when they last did.
struct ICloudSection: View {
    let sync: CloudSync

    var body: some View {
        Section {
            LabeledContent {
                statusText
                    .foregroundStyle(sync.status == .problem ? Paper.ink : Paper.secondary)
                    .accessibilityIdentifier("settings.iCloudStatus")
            } label: {
                Text("Sync")
                    .foregroundStyle(Paper.ink)
            }
            .font(.inter(.regular, size: 17, relativeTo: .body))
            .listRowBackground(Paper.background)
            if let lastSync = sync.lastSync, sync.status != .off, sync.status != .unavailable {
                LabeledContent {
                    Text(lastSync, format: .dateTime.hour().minute())
                        .foregroundStyle(Paper.secondary)
                } label: {
                    Text("Last sync")
                        .foregroundStyle(Paper.ink)
                }
                .font(.inter(.regular, size: 17, relativeTo: .body))
                .listRowBackground(Paper.background)
                Button {
                    sync.syncAll()
                } label: {
                    Text("Sync now")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.ink)
                }
                .disabled(sync.status == .syncing)
                .accessibilityIdentifier("settings.syncNow")
                .listRowBackground(Paper.background)
            }
        } header: {
            CapsLabel("iCloud")
        } footer: {
            footer
                .font(.inter(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(Paper.secondary)
        }
    }

    private var statusText: Text {
        switch sync.status {
        case .off: Text("Off")
        case .unavailable: Text("Not available")
        case .starting, .syncing: Text("Syncing…")
        case .upToDate: Text("Up to date")
        case .problem: Text("Some files did not sync")
        }
    }

    private var footer: Text {
        switch sync.status {
        case .off:
            Text("To see the same pages on your iPad and iPhone, sign in to iCloud with iCloud Drive on, in the Settings app. Until then everything stays on this device.")
        case .unavailable:
            Text("iCloud Drive is off for this app, or iCloud cannot be reached. Everything stays on this device.")
        case .problem:
            Text("They are tried again in a while. Nothing is lost: everything is also kept on this device.")
        case .starting, .syncing, .upToDate:
            Text("What you write here shows on your other devices with the same iCloud account. Everything is also kept on this device.")
        }
    }
}

/// Settings → Backup: all the data in one file (to keep in Files, or anywhere), and back.
struct BackupSection: View {
    let sync: CloudSync

    @State private var working = false
    @State private var choosingFile = false
    @State private var chosen: URL?
    @State private var message: BackupMessage?
    #if DEBUG
    @State private var lastBackup = "-"
    #endif

    private enum BackupMessage: Identifiable {
        case restored, notABackup, exportFailed

        var id: Self { self }
    }

    var body: some View {
        Section {
            Button(action: export) {
                Text("Export all data")
                    .font(.inter(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Paper.ink)
            }
            .disabled(working)
            .accessibilityIdentifier("settings.exportBackup")
            .listRowBackground(Paper.background)
            Button {
                choosingFile = true
            } label: {
                Text("Restore from a backup…")
                    .font(.inter(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Paper.ink)
            }
            .disabled(working)
            .accessibilityIdentifier("settings.restoreBackup")
            .listRowBackground(Paper.background)
        } header: {
            CapsLabel("Backup")
        } footer: {
            Text("One file with all your pages, lists, birthdays and photos. Restoring adds back what the backup has; nothing you have now is deleted.")
                .font(.inter(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(Paper.secondary)
            #if DEBUG
            Text(verbatim: lastBackup)
                .font(.system(size: 2))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("debug.lastBackup")
            #endif
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                chosen = url
            case .failure(let error):
                AppLog.error("Could not pick a backup file", error)
            }
        }
        .alert(Text("Restore this backup?"), isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } })) {
            Button {
                if let url = chosen {
                    restore(url)
                }
                chosen = nil
            } label: {
                Text("Restore")
            }
            Button(role: .cancel) {
                chosen = nil
            } label: {
                Text("Cancel")
            }
        } message: {
            Text("The pages, lists, birthdays and photos of the backup come back. Nothing you have now is deleted.")
        }
        .alert(item: $message) { message in
            switch message {
            case .restored:
                Alert(title: Text("Backup restored"), message: Text("The backup's pages, lists and photos are back."), dismissButton: .default(Text("OK")))
            case .notABackup:
                Alert(title: Text("Not a backup"), message: Text("This file is not a backup of Danai's Calendar."), dismissButton: .default(Text("OK")))
            case .exportFailed:
                Alert(title: Text("No backup"), message: Text("The backup could not be made."), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func export() {
        working = true
        Task {
            defer { working = false }
            do {
                let url = try await sync.exportBackup()
                #if DEBUG
                let size = (try? Data(contentsOf: url).count) ?? 0
                lastBackup = "\(url.pathExtension) \(size)"
                #endif
                SharePresenter.present(url)
            } catch {
                AppLog.error("Could not make a backup", error)
                message = .exportFailed
            }
        }
    }

    private func restore(_ url: URL) {
        working = true
        Task {
            defer { working = false }
            do {
                _ = try await sync.restoreBackup(from: url)
                message = .restored
            } catch {
                AppLog.error("Could not restore a backup", error)
                message = .notABackup
            }
        }
    }
}
