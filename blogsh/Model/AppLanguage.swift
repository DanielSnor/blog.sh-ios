import Foundation

/// The language the app speaks: the system's, or one of the three it is
/// written in. It is kept where the system itself keeps an app's own
/// language, so a choice made in the system's settings shows here and one
/// made here shows there -- and, like there, it is taken up when the app
/// is next started, not in the middle of a screen.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, cs, de, en

    /// The system's own key for the languages an app prefers.
    static let key = "AppleLanguages"

    var id: String { rawValue }

    /// Its name in itself, the way a list of languages says them; the
    /// system's has none of its own.
    var name: String? {
        switch self {
        case .system: nil
        case .cs: "Čeština"
        case .de: "Deutsch"
        case .en: "English"
        }
    }

    /// What is kept, read back: the first language of the list, whatever
    /// region it carries. No list, or a language the app is not written
    /// in, is the system's.
    init(kept: [String]?) {
        let code = kept?.first?.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { $0.lowercased() } ?? ""
        switch code {
        case "cs": self = .cs
        case "de": self = .de
        case "en": self = .en
        default: self = .system
        }
    }

    /// What is written down for it; nothing for the system's.
    var kept: [String]? { self == .system ? nil : [rawValue] }

    /// The app's own choice -- not what the system would hand it anyway.
    static func read(from defaults: UserDefaults = .standard, domain: String? = Bundle.main.bundleIdentifier) -> AppLanguage {
        let own = domain.flatMap { defaults.persistentDomain(forName: $0) }
        return AppLanguage(kept: own?[key] as? [String])
    }

    func write(to defaults: UserDefaults = .standard) {
        if let kept {
            defaults.set(kept, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
