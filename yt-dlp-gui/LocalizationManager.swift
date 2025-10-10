import Foundation
import SwiftUI

/// Centralizes app-specific localization overrides.
final class LocalizationManager {
    static let shared = LocalizationManager()

    struct LanguageOption: Identifiable, Equatable {
        let code: String
        let labelKey: LocalizedStringKey

        var id: String {
            code.isEmpty ? "system" : code
        }
    }

    private let appleLanguagesKey = "AppleLanguages"
    private let originalLanguagesKey = "OriginalAppleLanguages"
    private let customLanguageKey = "YtDlpPreferredLanguage"

    private init() {}

    /// Languages surfaced to the user. Empty code follows the system setting.
    let supportedLanguages: [LanguageOption] = [
        LanguageOption(code: "", labelKey: "settings_language_option_system"),
        LanguageOption(code: "en", labelKey: "settings_language_option_english"),
        LanguageOption(code: "zh-Hans", labelKey: "settings_language_option_chinese_simplified")
    ]

    /// Ensures the provided code maps to one of the supported options.
    func normalized(code: String) -> String {
        supportedLanguages.contains(where: { $0.code == code }) ? code : ""
    }

    /// Returns the stored override or an empty string if following the system language.
    func storedLanguageCode() -> String {
        UserDefaults.standard.string(forKey: customLanguageKey) ?? ""
    }

    /// Applies the preferred localization and persists the override.
    func apply(languageCode rawCode: String) {
        let code = normalized(code: rawCode)
        let defaults = UserDefaults.standard

        if code.isEmpty {
            if let original = defaults.array(forKey: originalLanguagesKey) {
                defaults.set(original, forKey: appleLanguagesKey)
                defaults.removeObject(forKey: originalLanguagesKey)
            } else if let developmentRegion = Bundle.main.infoDictionary?["CFBundleDevelopmentRegion"] as? String {
                defaults.set([developmentRegion], forKey: appleLanguagesKey)
            } else {
                defaults.removeObject(forKey: appleLanguagesKey)
            }
            defaults.removeObject(forKey: customLanguageKey)
            defaults.synchronize()
            return
        }

        if defaults.array(forKey: originalLanguagesKey) == nil,
           let current = defaults.array(forKey: appleLanguagesKey) {
            defaults.set(current, forKey: originalLanguagesKey)
        }

        let available = Bundle.main.localizations.filter { !$0.isEmpty }
        var languages = [code]
        languages.append(contentsOf: available.filter { $0 != code })

        defaults.set(languages, forKey: appleLanguagesKey)
        defaults.set(code, forKey: customLanguageKey)
        defaults.synchronize()
    }
}
