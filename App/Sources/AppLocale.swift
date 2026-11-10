import Foundation
import PlannerCore

enum AppLocale {
    /// Locale for printed dates and names: the language iOS chose for the app,
    /// with the device region.
    static var current: Locale {
        PlannerLocale.resolve(
            preferredLocalization: Bundle.main.preferredLocalizations.first,
            region: Locale.current.region?.identifier
        )
    }
}
