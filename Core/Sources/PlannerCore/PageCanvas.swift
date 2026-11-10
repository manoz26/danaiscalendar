import CoreGraphics

/// The fixed logical canvas every page is drawn on (portrait, 1000 x 1400 units).
///
/// Templates and ink both live in these coordinates, so a page looks identical on
/// every device and orientation; the view only scales it to the screen width.
public enum PageCanvas {
    public static let size = CGSize(width: 1000, height: 1400)

    /// Outer margin of printed content.
    public static let margin: CGFloat = 56

    /// Month title: top-left corner of its line box, and font size in canvas units.
    public static let titleOrigin = CGPoint(x: margin, y: margin)
    public static let titleFontSize: CGFloat = 40

    /// Scale that fits the page to a given view width.
    public static func scale(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return width / size.width
    }
}
