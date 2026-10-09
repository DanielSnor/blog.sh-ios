import Foundation

/// A post being written and not sent yet: its title, its tags, its text.
/// Kept on the device at every letter, for the blog it is written for --
/// so an app that was closed, or stopped by the system behind another,
/// or a way back taken by mistake, costs nothing that was written.
///
/// The pictures are not kept: they are large, and come back from the
/// library in a moment. The marks the text has for them are text, and
/// stay; a picture chosen again takes its name and its description back
/// from its mark.
nonisolated struct Unsent: Codable, Equatable, Sendable {
    var title = ""
    var tags = ""
    var text = ""
    /// When it was last written in.
    var at = Date.distantPast
    /// The name its delivery goes under, the same for every attempt at
    /// sending it: see `Receipt`.
    var receipt: String?
    /// The post that waited on the device and was taken back into the
    /// form: its pictures are still in its files (`Waiting.held`), and the
    /// form finds them there again.
    var from: UUID?

    /// Nothing worth keeping: spaces and line breaks are not writing.
    var isEmpty: Bool {
        [title, tags, text].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// What to call it where it is listed: its title, or -- written
    /// without one -- the first words of its text.
    var headline: String {
        let named = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !named.isEmpty { return named }
        let first = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("!") } ?? ""
        return String(first.drop { $0 == "#" || $0 == " " }.prefix(60))
    }

    /// The text names a picture or a video, which was not kept with it.
    var namesPictures: Bool {
        text.range(of: #"!{1,2}\[[^\n]*\]\([^)\s"\u201E\u201C\u201D]+"# + Kept.caption + #"\)"#, options: .regularExpression) != nil
    }

    /// The text names a picture or a video that is not among these: one
    /// the form does not have back.
    func namesPictures(beyond names: [String]) -> Bool {
        guard let marks = try? NSRegularExpression(pattern: #"!{1,2}\[[^\n]*\]\(([^)\s"\u201E\u201C\u201D]+)"# + Kept.caption + #"\)"#) else { return false }
        let whole = text as NSString
        return marks.matches(in: text, range: NSRange(location: 0, length: whole.length)).contains { match in
            !names.contains(whole.substring(with: match.range(at: 1)))
        }
    }

    static func key(_ blog: UUID) -> String { "unsent.\(blog.uuidString)" }

    /// What is kept for this blog; nothing where nothing is, or where
    /// what is there does not read.
    static func kept(for blog: UUID, in defaults: UserDefaults = .standard) -> Unsent? {
        guard let data = defaults.data(forKey: key(blog)),
              let unsent = try? JSONDecoder().decode(Unsent.self, from: data),
              !unsent.isEmpty else { return nil }
        return unsent
    }

    /// Keeps it for this blog -- or, emptied, keeps nothing: a form that
    /// was sent, or cleared by hand, leaves no post behind to bring back.
    /// What is kept already, word for word, is left as it is and keeps
    /// its time: a form that was only opened was not written in.
    func keep(for blog: UUID, in defaults: UserDefaults = .standard) {
        guard !isEmpty, let data = try? JSONEncoder().encode(self) else {
            defaults.removeObject(forKey: Self.key(blog))
            return
        }
        if let kept = Self.kept(for: blog, in: defaults),
           kept.title == title, kept.tags == tags, kept.text == text, kept.receipt == receipt, kept.from == from { return }
        defaults.set(data, forKey: Self.key(blog))
    }

    static func forget(for blog: UUID, in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(blog))
    }

    /// The post was sent: what is kept is forgotten -- if it is still what
    /// was sent. Whatever was written since is another post's beginning,
    /// and stays.
    static func forget(for blog: UUID, sent: Unsent, in defaults: UserDefaults = .standard) {
        guard let kept = kept(for: blog, in: defaults) else { return }
        if kept.title == sent.title, kept.tags == sent.tags, kept.text == sent.text {
            forget(for: blog, in: defaults)
        }
    }
}

/// Changes to a post the blog already has -- its text, or its words in
/// another language -- written and not saved yet. Kept as the new post's
/// writing is kept, for the same reasons; and with the version of the
/// post they were written over, so that the screen can say when the post
/// has moved on under them.
nonisolated struct Unsaved: Codable, Equatable, Sendable {
    var text: String
    /// The digest the post had when the changes were begun.
    var base: String
    /// When they were last written in.
    var at: Date
    /// The post's title, for where the changes are listed by name.
    var title: String?

    /// Which of a post's texts: its own, or one language of it.
    enum What: Equatable, Sendable {
        case text
        case language(String)

        fileprivate var word: String {
            switch self {
            case .text: "text"
            case .language(let code): "lang-\(code)"
            }
        }

        fileprivate init?(word: String) {
            if word == "text" {
                self = .text
            } else if word.hasPrefix("lang-"), word.count > 5 {
                self = .language(String(word.dropFirst(5)))
            } else {
                return nil
            }
        }
    }

    /// Every change kept for a blog: which post, which of its texts.
    static func all(for blog: UUID, in defaults: UserDefaults = .standard) -> [(slug: String, what: What, kept: Unsaved)] {
        let prefix = prefix(blog)
        return defaults.dictionaryRepresentation().keys.compactMap { key in
            guard key.hasPrefix(prefix) else { return nil }
            let rest = key.dropFirst(prefix.count)
            guard let dot = rest.firstIndex(of: "."), let what = What(word: String(rest[..<dot])) else { return nil }
            let slug = String(rest[rest.index(after: dot)...])
            guard !slug.isEmpty, let kept = kept(for: blog, slug: slug, what: what, in: defaults) else { return nil }
            return (slug, what, kept)
        }
    }

    static func key(_ blog: UUID, slug: String, what: What) -> String {
        "\(prefix(blog))\(what.word).\(slug)"
    }

    private static func prefix(_ blog: UUID) -> String { "unsaved.\(blog.uuidString)." }

    static func kept(for blog: UUID, slug: String, what: What, in defaults: UserDefaults = .standard) -> Unsaved? {
        guard let data = defaults.data(forKey: key(blog, slug: slug, what: what)) else { return nil }
        return try? JSONDecoder().decode(Unsaved.self, from: data)
    }

    /// Kept, unless the same words are kept already -- those keep their time.
    func keep(for blog: UUID, slug: String, what: What, in defaults: UserDefaults = .standard) {
        if let kept = Self.kept(for: blog, slug: slug, what: what, in: defaults), kept.text == text { return }
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key(blog, slug: slug, what: what))
    }

    static func forget(for blog: UUID, slug: String, what: What, in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(blog, slug: slug, what: what))
    }

    /// What an editor holds now, as it is kept. Changes that were
    /// brought back stay the changes begun over the version they were
    /// begun over, however much is added to them: it is that version the
    /// screen compares with the blog's to say the post has moved on.
    static func now(_ text: String, title: String?, over base: String, begun: Unsaved?, at: Date = .now) -> Unsaved {
        Unsaved(text: text, base: begun?.base ?? base, at: at, title: title)
    }

    /// The text was saved: what is kept is forgotten -- if it is still
    /// what was saved. Whatever was written since stays.
    static func forget(for blog: UUID, slug: String, what: What, saved text: String, in defaults: UserDefaults = .standard) {
        guard let kept = kept(for: blog, slug: slug, what: what, in: defaults), kept.text == text else { return }
        forget(for: blog, slug: slug, what: what, in: defaults)
    }

    /// The post has another slug now: what was kept for it -- its text and
    /// every language -- goes with it, or it would wait under a name no
    /// post answers to. Where the new name has something kept already, the
    /// later writing stays.
    static func move(for blog: UUID, from old: String, to new: String, in defaults: UserDefaults = .standard) {
        guard old != new, !new.isEmpty else { return }
        for (slug, what, kept) in all(for: blog, in: defaults) where slug == old {
            if let there = Self.kept(for: blog, slug: new, what: what, in: defaults), there.at >= kept.at {
                // The newer stays where it is.
            } else if let data = try? JSONEncoder().encode(kept) {
                defaults.set(data, forKey: key(blog, slug: new, what: what))
            }
            forget(for: blog, slug: old, what: what, in: defaults)
        }
    }

    /// Everything kept for a blog that leaves the app.
    static func forgetAll(for blog: UUID, in defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix(blog)) {
            defaults.removeObject(forKey: key)
        }
    }

    /// The text names a picture the post does not have: one that was
    /// chosen on the device and, like every picture, not kept.
    func namesPictures(beyond media: [String]) -> Bool {
        guard let marks = try? NSRegularExpression(pattern: #"!{1,2}\[[^\n]*\]\(([^)\s"\u201E\u201C\u201D]+)"# + Kept.caption + #"\)"#) else { return false }
        let whole = text as NSString
        return marks.matches(in: text, range: NSRange(location: 0, length: whole.length)).contains { match in
            !media.contains(whole.substring(with: match.range(at: 1)))
        }
    }
}

/// One thing begun on this device for a blog and not finished: a new post
/// not sent, a post's text or one of its languages changed and not saved.
/// What the first screen lists, so that writing kept from the last time is
/// seen without opening the form it waits in.
nonisolated struct Begun: Identifiable, Equatable, Sendable {
    enum What: Hashable, Sendable {
        case new
        case text(slug: String)
        case language(slug: String, lang: String)
    }

    let what: What
    /// What to call it: the post's title, or what stands for one.
    let title: String
    let at: Date

    var id: What { what }

    /// All of them for a blog: the new post first, then the changes to
    /// posts the blog has, the last written first.
    static func all(for blog: UUID, in defaults: UserDefaults = .standard) -> [Begun] {
        var changes: [Begun] = []
        for (slug, what, kept) in Unsaved.all(for: blog, in: defaults) {
            let title = kept.title.flatMap { $0.isEmpty ? nil : $0 } ?? slug
            switch what {
            case .text: changes.append(Begun(what: .text(slug: slug), title: title, at: kept.at))
            case .language(let lang): changes.append(Begun(what: .language(slug: slug, lang: lang), title: title, at: kept.at))
            }
        }
        changes.sort { ($0.at, $1.title) > ($1.at, $0.title) }
        guard let unsent = Unsent.kept(for: blog, in: defaults) else { return changes }
        return [Begun(what: .new, title: unsent.headline, at: unsent.at)] + changes
    }
}
