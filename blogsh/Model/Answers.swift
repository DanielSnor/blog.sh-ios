import Foundation

// The engine's `--json` answers, as Swift sees them. Each type mirrors
// one promise the engine makes in scripts/manage_post.rb: every key is
// always present, so nothing here is optional unless the engine itself
// sends null for it (a draft's date, a post with no title or series).
//
// A refusal is an object too -- `{"ok": false, "error": ..., "message":
// ...}` with a zero exit -- so every answer is decoded as either its own
// shape or a Refusal, never as "the command failed".

/// What the engine says when it will not do something: a code a program
/// can switch on, and a sentence a person can read.
nonisolated struct Refusal: Decodable, Error, Equatable, Sendable {
    let ok: Bool
    let error: String
    let message: String
}

/// `version --json`: the identity block the terminal shows above every
/// screen -- which engine, which site, where it is.
nonisolated struct VersionAnswer: Decodable, Equatable, Sendable {
    let ok: Bool
    let engine: String
    /// The receiver's ceiling on a delivery, measured on the encoded stream.
    let maxMb: Int
    let site: Site

    enum CodingKeys: String, CodingKey {
        case ok, engine, site
        case maxMb = "max_mb"
    }

    struct Site: Decodable, Equatable, Sendable {
        let name: String
        let claim: String
        let url: String
        let lang: String
        let locales: [String]
        /// The palette's accent, per scheme; nil from an engine before it said so.
        let accent: Accent?

        enum CodingKeys: String, CodingKey {
            case name, claim, url, lang, locales, accent
        }

        /// The claim is markdown in the site's configuration, and a blog may
        /// break it over two lines the markdown way -- a backslash, or two
        /// spaces, at the end of the first. Here it is the lines themselves.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            url = try c.decode(String.self, forKey: .url)
            lang = try c.decode(String.self, forKey: .lang)
            locales = try c.decode([String].self, forKey: .locales)
            accent = try c.decodeIfPresent(Accent.self, forKey: .accent)
            claim = try c.decode(String.self, forKey: .claim)
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { line in
                    var line = line.trimmingCharacters(in: .whitespaces)
                    if line.hasSuffix("\\") { line = String(line.dropLast()).trimmingCharacters(in: .whitespaces) }
                    return line
                }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
    }

    struct Accent: Decodable, Equatable, Sendable {
        let light: String
        let dark: String
    }
}

nonisolated enum PostState: String, Decodable, Sendable {
    case draft, published
}

/// One row of `list --json`.
nonisolated struct PostRow: Decodable, Identifiable, Equatable, Sendable {
    let slug: String
    let year: String
    let date: String?
    let title: String?
    let type: String
    let tags: [String]
    let state: PostState
    let scheduled: Bool
    let series: String?
    let pinned: Bool
    /// The line of the text a search matched on; nil without a search, on
    /// a hit in the title or a tag, and from an engine before `--search`.
    var match: String? = nil

    /// Slug and year together: the same slug can live in two years, and
    /// the engine refuses to guess between them, so neither does this.
    var id: String { "\(year)/\(slug)" }

    /// The day the row shows, or nothing for a plain draft -- whose
    /// timestamp is bookkeeping, not a fact about the post, which is why
    /// the terminal shows dashes for it.
    var day: Date? {
        guard !(state == .draft && !scheduled), let date else { return nil }
        return ISO8601DateFormatter.engine.date(from: date)
    }
}

/// `list --json`.
nonisolated struct ListAnswer: Decodable, Sendable {
    let ok: Bool
    let posts: [PostRow]
    let count: Int
    let drafts: Int
    /// The query said back; nil when there was none, and from an engine
    /// that does not know `--search` and answered with everything.
    let search: String?
}

/// `props <slug> --json`.
nonisolated struct PropsAnswer: Decodable, Sendable {
    let ok: Bool
    let slug: String
    let year: String
    let path: String
    let title: String
    let state: PostState
    let scheduled: Bool
    let date: String?
    let url: String
    let address: String
    let type: String
    /// The type the post says for itself; nil when the content decides.
    let typeSet: String?
    /// The two three-state flags, in the words --set takes: yes, no, default.
    let hero: String
    let toc: String
    let tags: [String]
    let series: String?
    let seriesPart: String?
    let pinned: Bool
    let unlisted: Bool
    let languages: Languages
    let announced: String?
    let announces: Announces
    /// Which network [t] announces on: "mastodon", "bluesky", or none.
    let network: String?
    /// The time the schedule dialog would offer a plain draft, or none.
    let slot: String?
    let addresses: [OldAddress]
    let actions: [PostAction]
    /// Present on the answer to a write (`--set`, `--rename`...), absent on a read.
    let deploy: String?
    let warnings: [String]?

    struct Languages: Decodable, Equatable, Sendable {
        let own: String
        let others: [String: String]
    }

    struct OldAddress: Decodable, Equatable, Sendable {
        let kind: String
        let value: String
    }

    /// Which of the six cases the announcement is in -- the ladder the
    /// properties screen climbs, as a word.
    enum Announces: String, Decodable, Sendable {
        case announced, onPublish = "on_publish", nowhere
        case neverUnlisted = "never_unlisted", noSecret = "no_secret", notAnnounced = "not_announced"
    }

    enum CodingKeys: String, CodingKey {
        case ok, slug, year, path, title, state, scheduled, date, url, address, type, tags, series, hero, toc
        case typeSet = "type_set"
        case seriesPart = "series_part"
        case pinned, unlisted, languages, announced, announces, network, slot, addresses, actions, deploy, warnings
    }
}

/// The keys the properties screen would offer a post, by name. The
/// engine decides which apply; the app only draws the ones it is handed.
nonisolated enum PostAction: String, Decodable, CaseIterable, Sendable {
    case publish, schedule, unschedule, unpublish, announce, pin
    case properties, rename, addresses, versions, delete
}

/// What an action says about the post it acted on: the keys `add --json`
/// and `publish --json` answer with, and the ones `delete` adds. All but
/// the slug are optional here because the shapes differ by action.
nonisolated struct ActionAnswer: Decodable, Sendable {
    let ok: Bool?
    let slug: String
    let state: PostState?
    let url: String?
    let deploy: String?
    let warnings: [String]?
    let compacted: Int?
    let trash: String?
}

/// `stats --json`: the archive counted. Only what the first screen says.
nonisolated struct StatsAnswer: Decodable, Sendable {
    struct Posts: Decodable, Sendable { let total: Int }
    struct Span: Decodable, Sendable { let first: String? }
    struct Words: Decodable, Sendable {
        let total: Int
        let readingHours: Double
        enum CodingKeys: String, CodingKey {
            case total
            case readingHours = "reading_hours"
        }
    }
    struct Tags: Decodable, Sendable { let unique: Int }
    struct Media: Decodable, Sendable {
        let files: Int
        let bytes: Int
    }

    let posts: Posts
    let span: Span
    let words: Words
    let tags: Tags
    let media: Media
}

/// `empty trash --json` and `empty versions --json`, asked without `--yes`:
/// how much there is, and nothing is touched.
nonisolated struct HeldAnswer: Decodable, Sendable {
    let count: Int
    let bytes: Int
    /// With `--yes`: whether anything was removed.
    var emptied: Bool? = nil
}

/// `props <slug> --versions --json`.
nonisolated struct VersionsAnswer: Decodable, Sendable {
    let ok: Bool
    let slug: String
    let versions: [Version]

    struct Version: Decodable, Identifiable, Sendable {
        let name: String
        let date: String?
        let label: String

        var id: String { name }
    }
}

/// `rebuild --json`.
nonisolated struct RebuildAnswer: Decodable, Sendable {
    let ok: Bool
    let deploy: String
    let warnings: [String]
}

/// `edit <slug> --json`: one post with what it takes to edit its text
/// elsewhere -- the same entry `drafts --json` hands out for a draft.
nonisolated struct EditAnswer: Decodable, Sendable {
    let ok: Bool
    let post: EditEntry
}

nonisolated struct EditEntry: Decodable, Sendable {
    let slug: String
    let title: String
    let date: String
    let scheduled: Bool
    /// False when the text holds something markdown cannot carry; the
    /// engine names the reason, and the save would lose it.
    let editable: Bool
    let problem: String?
    /// The text as the editor opens it, pictures by bare name.
    let text: String?
    /// The pictures the post has, by name.
    let media: [String]
    let preview: String
    /// The digest the save hands back as `base:`.
    let base: String
}

/// `translate <slug> --lang <code> --json`: one language of a post, with
/// the original beside it, to be written elsewhere.
nonisolated struct TranslationAnswer: Decodable, Sendable {
    let ok: Bool
    let post: TranslationEntry
}

nonisolated struct TranslationEntry: Decodable, Sendable {
    let slug: String
    let lang: String
    let title: String
    /// Whether the language has words yet.
    let written: Bool
    /// The translation as the editor opens it: a header of its title and
    /// its address, then its words -- empty when there are none yet.
    let text: String
    /// The post's own text, pictures by bare name, to translate from.
    let original: String
    let media: [String]
    let preview: String
    let base: String
}

/// `restore --json`: what the trash holds.
nonisolated struct TrashAnswer: Decodable, Sendable {
    let ok: Bool
    let trash: [TrashRow]
}

nonisolated struct TrashRow: Decodable, Identifiable, Equatable, Sendable {
    let slug: String
    let year: String?
    let date: String?
    let title: String?
    let type: String?
    let tags: [String]
    let state: String?
    let mediaOnly: Bool

    var id: String { "\(year ?? "-")/\(slug)" }

    enum CodingKeys: String, CodingKey {
        case slug, year, date, title, type, tags, state
        case mediaOnly = "media_only"
    }
}

/// `queue --json`.
nonisolated struct QueueAnswer: Decodable, Sendable {
    let ok: Bool
    let queue: [QueueRow]
}

nonisolated struct QueueRow: Decodable, Identifiable, Equatable, Sendable {
    let position: Int
    let date: String
    let slug: String
    let year: String
    let title: String
    let overdue: Bool

    var id: String { "\(year)/\(slug)" }
}

nonisolated extension ISO8601DateFormatter {
    /// The engine writes `2026-05-01T10:00:00+02:00`: no fractional
    /// seconds, an offset rather than Z.
    // Read-only after it is made; the formatter is not Sendable by type.
    nonisolated(unsafe) static let engine: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

nonisolated extension PostRow {
    /// Rows for the previews, and for a screen before a connection exists.
    static let sample: [PostRow] = [
        PostRow(slug: "planovany", year: "2026", date: "2099-01-01T09:00:00+01:00", title: "Plánovaný",
                type: "text", tags: [], state: .draft, scheduled: true, series: nil, pinned: false),
        PostRow(slug: "koncept", year: "2026", date: "2026-06-01T10:00:00+02:00", title: "Koncept",
                type: "text", tags: [], state: .draft, scheduled: false, series: nil, pinned: false),
        PostRow(slug: "venku", year: "2026", date: "2026-05-01T10:00:00+02:00", title: "Venku",
                type: "text", tags: ["louka", "les"], state: .published, scheduled: false,
                series: "Procházky", pinned: false),
        PostRow(slug: "pripnuty", year: "2025", date: "2025-03-01T10:00:00+01:00", title: "Připnutý",
                type: "image", tags: [], state: .published, scheduled: false, series: nil, pinned: true),
    ]
}

/// The engine says what it did in the terminal's words, and at the desk
/// those name a file where it lies -- "Restored: /srv/blog/content.nosync/
/// posts/2026/venku.json". On a phone that is a line of somebody's server
/// with the one useful word at its far end; here the word stays and the
/// way to it goes.
nonisolated enum ServerPaths {
    /// The directories only the engine's own files live under.
    private static let homes = ["/content.nosync/", "/media.nosync/", "/public.nosync/", "/trash/", "/incoming/"]
    // An absolute path of two parts or more: not one begun inside a word or
    // an address (https://…), and ended by a space or the punctuation of a sentence.
    private static let path = try! NSRegularExpression(pattern: #"(?<![\w:/.])/(?:[^\s/:,;)]+/)+[^\s:,;)]*"#)

    static func plain(_ line: String) -> String {
        let ns = line as NSString
        var out = ""
        var from = 0
        for match in path.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            var token = ns.substring(with: match.range)
            out += ns.substring(with: NSRange(location: from, length: match.range.location - from))
            from = match.range.location + match.range.length
            guard homes.contains(where: { (token + "/").contains($0) }) else { out += token; continue }
            // A full stop after the path is the sentence's, not the file's.
            var tail = ""
            if token.hasSuffix(".") { token.removeLast(); tail = "." }
            var name = token.split(separator: "/").last.map(String.init) ?? token
            if name.hasSuffix(".json") { name.removeLast(5) }
            out += name + tail
        }
        return out + ns.substring(from: from)
    }
}

extension Array where Element == String {
    /// The engine's lines without the server's paths in them.
    nonisolated var plain: [String] { map(ServerPaths.plain) }
}
