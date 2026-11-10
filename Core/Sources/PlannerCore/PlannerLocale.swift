import Foundation

/// Locale and calendar used for everything the planner prints.
public enum PlannerLocale {
    /// Languages the app is translated into. The first one is the fallback.
    public static let supportedLanguages = ["en", "el"]

    /// Builds the locale for dates and names from the language iOS picked for the app
    /// (`Bundle.main.preferredLocalizations.first`) and the device region.
    ///
    /// Using the app's language instead of `Locale.current` keeps month and day names
    /// in the same language as the rest of the UI: a French device gets English everywhere.
    public static func resolve(preferredLocalization: String?, region: String?) -> Locale {
        let requested = preferredLocalization.map { Locale(identifier: $0).language.languageCode?.identifier ?? $0 }
        let language = requested.flatMap { supportedLanguages.contains($0) ? $0 : nil } ?? supportedLanguages[0]
        guard let region, !region.isEmpty else { return Locale(identifier: language) }
        return Locale(identifier: "\(language)_\(region)")
    }

    /// Gregorian calendar in the given locale and time zone, whatever the device calendar is.
    public static func calendar(locale: Locale, timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        return calendar
    }
}
