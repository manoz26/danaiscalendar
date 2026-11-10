import SwiftUI

/// The only UI colours: paper, ink and greys. Colour belongs to the user's ink alone.
enum Paper {
    static let background = Color.white
    static let ink = Color.black
    /// Secondary text: Sundays, days of other months.
    static let secondary = Color(white: 0.55)
    /// Box fills, like the grey GOALS and notes boxes.
    static let fill = Color(white: 0.95)
    /// Month tabs that are not the open page.
    static let tab = Color(white: 0.92)
    /// Labels of those tabs.
    static let tabLabel = Color(white: 0.4)
    /// Hairlines of the app's own bars.
    static let hairline = Color(white: 0.85)
}
