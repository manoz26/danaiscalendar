import SwiftUI

/// The only UI colours: paper, ink and greys. Colour belongs to the user's ink alone.
enum Paper {
    static let background = Color.white
    static let ink = Color.black
    /// Secondary text: Sundays, days of other months.
    static let secondary = Color(white: 0.55)
    /// Box fills, like the grey GOALS and notes boxes.
    static let fill = Color(white: 0.95)
}
