import SwiftUI

/// Inter weights bundled with the app (see `UIAppFonts` in project.yml).
enum InterWeight: String, CaseIterable, Sendable {
    case regular = "Inter-Regular"
    case medium = "Inter-Medium"
    case semibold = "Inter-SemiBold"
    case bold = "Inter-Bold"

    var postScriptName: String { rawValue }
}

extension Font {
    /// Inter at a fixed size. Page content uses fixed sizes because the whole page
    /// scales with the screen; Dynamic Type applies to non-page screens only.
    static func inter(_ weight: InterWeight, size: CGFloat) -> Font {
        .custom(weight.postScriptName, fixedSize: size)
    }
}
