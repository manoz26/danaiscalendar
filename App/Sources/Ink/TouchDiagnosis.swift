import Foundation

/// Temporary switches (Debug builds only) to find which part of the page makes UIKit
/// crash when a finger touches it in the simulator (`DiagnosticTouchTests`).
enum TouchDiagnosis {
    #if DEBUG
    private static func flag(_ name: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(name)
    }

    static var noTap: Bool { flag("-DCDiagNoTap") }
    static var noToolbar: Bool { flag("-DCDiagNoToolbar") }
    static var noContentDelay: Bool { flag("-DCDiagNoDelay") }
    static var noDrawing: Bool { flag("-DCDiagNoDrawing") }
    static var noOverrides: Bool { flag("-DCDiagNoOverrides") }
    static var noPencilInteraction: Bool { flag("-DCDiagNoPencil") }
    static var noTemplateView: Bool { flag("-DCDiagNoTemplate") }
    #else
    static let noTap = false
    static let noToolbar = false
    static let noContentDelay = false
    static let noDrawing = false
    static let noOverrides = false
    static let noPencilInteraction = false
    static let noTemplateView = false
    #endif
}
