import Foundation
import WhisperKit

/// Languages Whisper can recognise, with localized names for the picker.
enum WhisperLanguages {
    /// Whisper codes, sorted by the localized name.
    static let all: [(code: String, name: String)] = {
        Set(Constants.languages.values).map { ($0, name(for: $0)) }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }()

    static func name(for code: String) -> String {
        if let n = uiLocale.localizedString(forLanguageCode: code), n != code { return n.prefix(1).uppercased() + n.dropFirst() }
        return Constants.languages.first { $0.value == code }.map { $0.key.capitalized } ?? code
    }

    /// Whisper code of the first macOS preferred language, or nil when Whisper does not support it.
    static func systemCode() -> String? {
        for id in systemLanguages() {
            let code = Locale(identifier: id).language.languageCode?.identifier ?? ""
            let mapped = ["nb": "no", "nn": "no", "iw": "he"][code] ?? code
            if Constants.languageCodes.contains(mapped) { return mapped }
            return nil   // the first language decides; an unsupported one means auto-detect
        }
        return nil
    }

    /// "system" -> the macOS language (or "auto" if unsupported), anything else is returned as is.
    static func resolve(_ pref: String) -> String {
        pref == "system" ? (systemCode() ?? "auto") : pref
    }
}

/// macOS preferred languages. `Locale.preferredLanguages` is narrowed to the app's localizations, so the global list is read directly.
func systemLanguages() -> [String] {
    if let l = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String], !l.isEmpty { return l }
    return Locale.preferredLanguages
}

let uiLocale = Locale(identifier: systemLanguages().first ?? "en")
