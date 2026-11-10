import Foundation
import OSLog
import PlannerCore

/// The app's log. Every significant error goes here: it ends up in the file the user
/// can share from Settings → Diagnostics (tap the version 5 times), and in the system
/// log for when a Mac is connected.
enum AppLog {
    static let file = DiagnosticsLog(
        fileURL: URL.applicationSupportDirectory
            .appending(path: "Diagnostics", directoryHint: .isDirectory)
            .appending(path: "DanaisCalendar-log.txt")
    )

    private static let system = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DanaisCalendar",
        category: "app"
    )

    static func info(_ message: String) {
        system.info("\(message, privacy: .public)")
        file.info(message)
    }

    static func warning(_ message: String) {
        system.warning("\(message, privacy: .public)")
        file.warning(message)
    }

    static func error(_ message: String) {
        system.error("\(message, privacy: .public)")
        file.error(message)
    }

    /// Logs an error with its type and description, e.g. `Could not save page: CocoaError(...)`.
    static func error(_ message: String, _ error: any Error) {
        Self.error("\(message): \(String(reflecting: error))")
    }
}

/// Facts about this build, read from Info.plist (see `info:` in project.yml).
enum AppInfo {
    static var version: String { string("CFBundleShortVersionString") }
    static var build: String { string("CFBundleVersion") }
    /// Short git commit the build was made from ("dev" for local and CI test builds).
    static var commit: String { string("DCGitCommit") }
    static var appGroup: String { string("DCAppGroup") }
    static var iCloudContainer: String { string("DCICloudContainer") }

    /// e.g. "0.1.0 (12)".
    static var versionAndBuild: String { "\(version) (\(build))" }

    private static func string(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "?"
    }
}
