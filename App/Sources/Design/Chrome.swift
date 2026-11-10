import SwiftUI
import UIKit
import PlannerCore

extension Font {
    /// Inter for app screens around the page (settings, diagnostics). Unlike page
    /// content, these follow Dynamic Type.
    static func inter(_ weight: InterWeight, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(weight.postScriptName, size: size, relativeTo: style)
    }
}

/// System bars in the planner's style: white, black, Inter.
enum Chrome {
    @MainActor
    static func apply() {
        let ink = UIColor.black
        let title = UIFont(name: InterWeight.semibold.postScriptName, size: 17)
            ?? .systemFont(ofSize: 17, weight: .semibold)
        let largeTitle = UIFont(name: InterWeight.bold.postScriptName, size: 34)
            ?? .systemFont(ofSize: 34, weight: .bold)
        let button = UIFont(name: InterWeight.medium.postScriptName, size: 17)
            ?? .systemFont(ofSize: 17, weight: .medium)

        let buttons = UIBarButtonItemAppearance(style: .plain)
        buttons.normal.titleTextAttributes = [.font: button, .foregroundColor: ink]
        let doneButtons = UIBarButtonItemAppearance(style: .done)
        doneButtons.normal.titleTextAttributes = [.font: title, .foregroundColor: ink]

        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = .white
        bar.shadowColor = UIColor(white: 0, alpha: 0.12)
        bar.titleTextAttributes = [.font: title, .foregroundColor: ink]
        bar.largeTitleTextAttributes = [.font: largeTitle, .foregroundColor: ink]
        bar.buttonAppearance = buttons
        bar.backButtonAppearance = buttons
        bar.doneButtonAppearance = doneButtons

        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = bar
        proxy.compactAppearance = bar
        proxy.scrollEdgeAppearance = bar
        proxy.compactScrollEdgeAppearance = bar
        proxy.tintColor = ink
    }
}

/// A small capitalised label with letter-spacing, like "GOALS" on the printed page.
struct CapsLabel: View {
    private let text: String

    init(_ key: String.LocalizationValue) {
        text = PlannerText.uppercased(String(localized: key), locale: AppLocale.current)
    }

    var body: some View {
        Text(verbatim: text)
            .font(.inter(.semibold, size: 12, relativeTo: .caption))
            .tracking(1.4)
            .foregroundStyle(Paper.ink)
    }
}
