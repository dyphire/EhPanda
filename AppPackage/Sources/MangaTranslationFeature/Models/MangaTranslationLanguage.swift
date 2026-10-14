import Foundation

public enum MangaTranslationLanguage {
    public static let defaultSource = "ja"

    public static var systemTarget: String {
        let identifier = normalized(Locale.preferredLanguages.first ?? Locale.current.identifier) ?? "en"
        let components = identifier.split(separator: "-")
        guard let language = components.first else { return "en" }
        if components.count > 1, components[1].count == 4,
            components[1].allSatisfy({ $0.isLetter })
        {
            return "\(language)-\(components[1])"
        }
        return String(language)
    }

    public static func normalized(_ language: String?) -> String? {
        guard let language else { return nil }
        let value = language.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        return value.isEmpty ? nil : value
    }

    // Vertical typesetting reads naturally only for Chinese and Japanese;
    // other targets keep horizontal rendering even for vertical bubbles.
    public static func supportsVerticalLayout(_ language: String) -> Bool {
        language.hasPrefix("ja") || language.hasPrefix("zh")
    }

    /// Sameness for the no-op short-circuit, compared on the primary language subtag:
    /// script/region variants count as the same language (a `zh` gallery needs no
    /// translation into `zh-Hans`).
    public static func isSameLanguage(_ source: String, _ target: String) -> Bool {
        func baseSubtag(_ language: String) -> Substring? {
            language.split(separator: "-").first
        }
        guard let sourceBase = baseSubtag(source), let targetBase = baseSubtag(target)
        else { return source.caseInsensitiveCompare(target) == .orderedSame }
        return sourceBase.caseInsensitiveCompare(targetBase) == .orderedSame
    }

    public static func pickerCodes(including language: String? = nil) -> [String] {
        var codes = Set(LanguageCodeHelper.commonLanguageCodes)
        codes.insert(systemTarget)
        if let language = normalized(language) {
            codes.insert(language)
        }
        return codes.sorted {
            LanguageCodeHelper.displayName(for: $0).localizedStandardCompare(
                LanguageCodeHelper.displayName(for: $1)
            ) == .orderedAscending
        }
    }

    public static func promptName(for language: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: language) ?? language
    }
}

public enum LanguageCodeHelper {
    public static let commonLanguageCodes: [String] = [
        "en", "zh", "ja", "ko", "fr", "de", "es", "it", "pt", "ru",
        "ar", "th", "vi", "hi", "tr", "pl", "nl", "sv", "da", "fi",
        "no", "cs", "hu", "ro", "el", "he", "id", "ms", "uk", "bg",
        "hr", "sk", "sl", "et", "lv", "lt", "mt", "ga", "cy", "is"
    ]

    public static func displayName(for languageCode: String) -> String {
        if languageCode.isEmpty {
            return String(localized: .languageNone)
        }
        let identifier = languageCode.replacingOccurrences(of: "_", with: "-")
        if let displayName = Locale.current.localizedString(forIdentifier: identifier) {
            return displayName.capitalized
        }
        return identifier.uppercased()
    }
}
