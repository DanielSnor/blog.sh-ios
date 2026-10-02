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
