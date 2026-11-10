import Foundation
import MetricKit
import UIKit

/// Launch-time logging and the facts shown on the Diagnostics screen.
enum AppDiagnostics {
    /// Called once when the app starts.
    @MainActor
    static func start() {
        AppLog.info("Launch: \(summary)")
        CrashReports.shared.start()
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { _ in
            AppLog.warning("Memory warning")
        }
        Task.detached(priority: .utility) {
            for check in await EntitlementCheck.runAll() {
                check.log()
            }
        }
    }

    /// One line about this build and device, e.g.
    /// `Danai's Calendar 0.1.0 (12) · commit 1a2b3c4 · iPadOS 26.1 · iPad16,6 · el_GR · Europe/Athens`.
    @MainActor
    static var summary: String {
        let device = UIDevice.current
        return [
            "Danai's Calendar \(AppInfo.versionAndBuild)",
            "commit \(AppInfo.commit)",
            "\(device.systemName) \(device.systemVersion)",
            modelIdentifier,
            AppLocale.current.identifier,
            TimeZone.current.identifier,
        ].joined(separator: " · ")
    }

    /// Hardware model, e.g. "iPad16,6". Simulators report the model they imitate.
    static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) simulator"
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}

/// Checks that the entitlements in the signature actually work on this device.
struct EntitlementCheck: Sendable, Identifiable {
    enum Kind: Sendable {
        case appGroup, iCloudAccount, iCloudFolder
    }

    let kind: Kind
    let ok: Bool

    var id: Kind { kind }

    var title: LocalizedStringResource {
        switch kind {
        case .appGroup: "App Group"
        case .iCloudAccount: "iCloud account"
        case .iCloudFolder: "iCloud folder"
        }
    }

    /// A real problem, not just a choice of the user (like not using iCloud).
    var isProblem: Bool { !ok && kind != .iCloudAccount }

    var status: LocalizedStringResource {
        if ok { return "OK" }
        return kind == .iCloudAccount ? "Not signed in" : "Unavailable"
    }

    /// English line for the log file.
    var logLine: String {
        let name = switch kind {
        case .appGroup: "App Group \(AppInfo.appGroup)"
        case .iCloudAccount: "iCloud account"
        case .iCloudFolder: "iCloud folder \(AppInfo.iCloudContainer)"
        }
        let result = ok ? "OK" : (kind == .iCloudAccount ? "not signed in" : "unavailable")
        return "Check: \(name): \(result)"
    }

    func log() {
        switch (kind, ok) {
        case (_, true), (.iCloudAccount, false):
            AppLog.info(logLine)
        case (.iCloudFolder, false):
            // Only checked when signed in to iCloud, so this points at the entitlement.
            AppLog.error(logLine)
        case (.appGroup, false):
            AppLog.error(logLine)
        }
    }

    static func runAll() async -> [EntitlementCheck] {
        let group = AppInfo.appGroup
        let container = AppInfo.iCloudContainer
        let fileManager = FileManager.default

        let groupOK = fileManager.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
        let signedIn = fileManager.ubiquityIdentityToken != nil
        var checks = [
            EntitlementCheck(kind: .appGroup, ok: groupOK),
            EntitlementCheck(kind: .iCloudAccount, ok: signedIn),
        ]
        if signedIn {
            // Can block for a while the first time, so never on the main thread.
            let folderOK = await Task.detached(priority: .utility) {
                FileManager.default.url(forUbiquityContainerIdentifier: container) != nil
            }.value
            checks.append(EntitlementCheck(kind: .iCloudFolder, ok: folderOK))
        }
        return checks
    }
}

/// Crash, hang and other diagnostic reports from iOS (MetricKit). iOS delivers them on
/// the next launch; they only ever go into the local log, nowhere else.
final class CrashReports: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashReports()

    @MainActor
    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let json = String(decoding: payload.jsonRepresentation(), as: UTF8.self)
            AppLog.error("Diagnostic report from iOS (crashes: \(crashes), hangs: \(hangs))\n\(json)")
        }
    }
}

/// What the Diagnostics screen shows, and the text file it shares.
struct DiagnosticsSnapshot: Sendable {
    let summary: String
    let checks: [EntitlementCheck]
    /// The newest part of the log, for the screen. The shared file has all of it.
    let logTail: String
    let shareURL: URL?

    @MainActor
    static func make() async -> DiagnosticsSnapshot {
        let summary = AppDiagnostics.summary
        let checks = await EntitlementCheck.runAll()
        let (logTail, shareURL) = await Task.detached(priority: .userInitiated) { () -> (String, URL?) in
            let log = AppLog.file.contents()
            let tail = log.split(separator: "\n", omittingEmptySubsequences: false)
                .suffix(300)
                .joined(separator: "\n")
            let report = (["Danai's Calendar diagnostics", summary] + checks.map(\.logLine) + ["", log])
                .joined(separator: "\n")
            let url = FileManager.default.temporaryDirectory.appending(path: "DanaisCalendar-diagnostics.txt")
            do {
                try Data(report.utf8).write(to: url, options: .atomic)
                return (tail, url)
            } catch {
                AppLog.error("Could not write the diagnostics file", error)
                return (tail, nil)
            }
        }.value
        return DiagnosticsSnapshot(summary: summary, checks: checks, logTail: logTail, shareURL: shareURL)
    }
}
