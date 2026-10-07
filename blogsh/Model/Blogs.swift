import SwiftUI

/// One blog the app drives: where it is, what it is reached through, the
/// key it is reached with, and what it last said about itself -- so its
/// screen opens as that blog, in its colour, before the server has
/// answered. A key belongs to one blog: on the server a key runs one
/// forced command, and that command is one blog's `scripts/remote.sh`.
/// The colours a blog's pages are set in, for one scheme: the ground,
/// what is written on it, what is written beside it, and its rules. As
/// the blog's config names them, in hex.
nonisolated struct Tones: Codable, Equatable, Sendable {
    var bg: String
    var text: String
    var metaText: String
    var border: String

    enum CodingKeys: String, CodingKey {
        case bg, text, border
        case metaText = "meta_text"
    }

    /// A colour as a number, the way a palette writes one -- `#fff7eb`,
    /// `#fc0` -- or nothing when the word is not that.
    static func value(_ hex: String) -> UInt32? {
        var word = hex.trimmingCharacters(in: .whitespaces)
        guard word.hasPrefix("#") else { return nil }
        word.removeFirst()
        if word.count == 3 { word = word.map { "\($0)\($0)" }.joined() }
        guard word.count == 6, word.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(word, radix: 16)
    }

    typealias Scheme = (bg: UInt32, text: UInt32, metaText: UInt32, border: UInt32)

    /// The four as numbers -- all of them or none: a palette with one
    /// colour unreadable is not worn at all, rather than half worn.
    var values: Scheme? {
        guard let bg = Self.value(bg), let text = Self.value(text),
              let metaText = Self.value(metaText), let border = Self.value(border) else { return nil }
        return (bg, text, metaText, border)
    }

    // The app's own colours: the palette the engine ships with, the blue
    // one -- what a blog looks like before anybody chose its colours, and
    // so what the app looks like before a blog has said its own.
    static let ownLight: Scheme = (0xF5F8FA, 0x444A5A, 0x657784, 0xE1E8ED)
    static let ownDark: Scheme = (0x111111, 0xFFFFFF, 0x6A7F8C, 0x263340)
    static let ownAccent: (light: UInt32, dark: UInt32) = (0x1DA1F2, 0x4AB3F4)

    /// The two schemes the app is drawn in: the blog's, when it has said
    /// both and both read whole and the app is not asked to keep to its
    /// own; the app's own otherwise.
    static func worn(own: Bool, light: Tones?, dark: Tones?) -> (light: Scheme, dark: Scheme) {
        if !own, let light = light?.values, let dark = dark?.values { return (light, dark) }
        return (ownLight, ownDark)
    }
}

nonisolated struct Blog: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var host = ""
    var port = 22
    var user = ""
    /// The blog's directory on the server, and the command it is entered through.
    var path = ""
    var through = ""
    /// The keychain account its key is kept under.
    var keyAccount: String

    // What it said last: `version --json`.
    var name = ""
    var claim = ""
    var url = ""
    var accentLight = ""
    var accentDark = ""
    /// The rest of its palette, per scheme; nil until it has said it.
    var tonesLight: Tones?
    var tonesDark: Tones?
    var maxMb = 24
    /// What it counted last: `stats`, the trash, the versions.
    var facts: Facts?

    init(keyAccount: String? = nil) {
        let id = UUID()
        self.id = id
        self.keyAccount = keyAccount ?? "blog-\(id.uuidString.lowercased())"
    }

    // Read field by field: a blog written down by an earlier build, before a
    // field existed, is still that blog.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.id = id
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 22
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        through = try c.decodeIfPresent(String.self, forKey: .through) ?? ""
        keyAccount = try c.decodeIfPresent(String.self, forKey: .keyAccount) ?? "blog-\(id.uuidString.lowercased())"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        claim = try c.decodeIfPresent(String.self, forKey: .claim) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        accentLight = try c.decodeIfPresent(String.self, forKey: .accentLight) ?? ""
        accentDark = try c.decodeIfPresent(String.self, forKey: .accentDark) ?? ""
        tonesLight = try c.decodeIfPresent(Tones.self, forKey: .tonesLight)
        tonesDark = try c.decodeIfPresent(Tones.self, forKey: .tonesDark)
        maxMb = try c.decodeIfPresent(Int.self, forKey: .maxMb) ?? 24
        facts = try c.decodeIfPresent(Facts.self, forKey: .facts)
    }

    /// What to call it in a list: its own name, or where it is, before it has said one.
    var label: String {
        if !name.isEmpty { return name }
        // Until the engine has said its name, the directory tells two
        // blogs on one server apart; the host alone would not.
        let folder = path.split(separator: "/").last.map(String.init) ?? ""
        return folder.isEmpty ? host.trimmingCharacters(in: .whitespaces) : folder
    }
}

/// The blog in numbers, as the first screen says them under the search:
/// the archive counted (`stats`), and what the trash and the versions hold.
nonisolated struct Facts: Codable, Equatable, Sendable {
    var posts = 0
    /// The year of the first post.
    var since = ""
    var words = 0
    var readingHours = 0.0
    var tags = 0
    var media = 0
    var mediaBytes = 0
    var trash = 0
    var trashBytes = 0
    var versions = 0
    var versionsBytes = 0
}

/// Where the blogs are written down. Plain defaults, read and written from
/// wherever the app happens to be running -- the engine's calls read the
/// current blog off the main actor.
nonisolated enum BlogShelf {
    static let listKey = "blogs"
    static let currentKey = "blogs.current"

    static func read(from defaults: UserDefaults = .standard) -> (blogs: [Blog], current: UUID?) {
        migrate(defaults)
        let blogs = (defaults.data(forKey: listKey)).flatMap { try? JSONDecoder().decode([Blog].self, from: $0) } ?? []
        let chosen = defaults.string(forKey: currentKey).flatMap(UUID.init(uuidString:))
        let current = blogs.contains { $0.id == chosen } ? chosen : blogs.first?.id
        return (blogs, current)
    }

    static func write(_ blogs: [Blog], current: UUID?, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(blogs) { defaults.set(data, forKey: listKey) }
        defaults.set(current?.uuidString, forKey: currentKey)
    }

    static func current(from defaults: UserDefaults = .standard) -> Blog? {
        let shelf = read(from: defaults)
        return shelf.blogs.first { $0.id == shelf.current }
    }

    /// The app had one server before it had blogs: what was set up for it
    /// becomes the first blog, with the key it already had.
    private static func migrate(_ defaults: UserDefaults) {
        guard defaults.object(forKey: listKey) == nil else { return }
        let host = defaults.string(forKey: "server.host") ?? ""
        let user = defaults.string(forKey: "server.user") ?? ""
        guard !host.isEmpty || !user.isEmpty || KeyStore.hasKey(account: KeyStore.firstAccount) else {
            write([], current: nil, to: defaults)
            return
        }
        var blog = Blog(keyAccount: KeyStore.firstAccount)
        blog.host = host
        blog.user = user
        let port = defaults.integer(forKey: "server.port")
        blog.port = port == 0 ? 22 : port
        blog.path = defaults.string(forKey: "server.path") ?? ""
        blog.through = defaults.string(forKey: "server.through") ?? ""
        blog.name = defaults.string(forKey: "site.name") ?? ""
        blog.claim = defaults.string(forKey: "site.claim") ?? ""
        blog.url = defaults.string(forKey: "site.url") ?? ""
        blog.accentLight = defaults.string(forKey: "site.accent.light") ?? ""
        blog.accentDark = defaults.string(forKey: "site.accent.dark") ?? ""
        let max = defaults.integer(forKey: "site.maxMb")
        blog.maxMb = max == 0 ? 24 : max
        write([blog], current: blog.id, to: defaults)
    }
}

/// The blogs as the screens see them: which there are, which one is open.
@Observable
final class Blogs {
    static let shared = Blogs()

    private(set) var all: [Blog]
    private(set) var currentID: UUID?

    private init() {
        let shelf = BlogShelf.read()
        all = shelf.blogs
        currentID = shelf.current
    }

    var current: Blog? { all.first { $0.id == currentID } }

    /// A change to the blog that is open, written down at once.
    func update(_ change: (inout Blog) -> Void) {
        guard let index = all.firstIndex(where: { $0.id == currentID }) else { return }
        var blog = all[index]
        change(&blog)
        guard blog != all[index] else { return }
        all[index] = blog
        save()
    }

    func select(_ id: UUID) {
        guard id != currentID, all.contains(where: { $0.id == id }) else { return }
        currentID = id
        save()
    }

    /// A new blog, open: its directory and its key are the settings' to
    /// fill in. The server is the one of the blog that was open -- a second
    /// blog most often lives beside the first, and what the first is
    /// reached through is long to type twice. Every field stays editable.
    @discardableResult
    func add() -> Blog {
        var blog = Blog()
        if let beside = current {
            blog.host = beside.host
            blog.port = beside.port
            blog.user = beside.user
            blog.through = beside.through
        }
        all.append(blog)
        currentID = blog.id
        save()
        return blog
    }

    /// The blog leaves the app, and its key with it. The blog itself is not touched.
    func remove(_ id: UUID) {
        guard let blog = all.first(where: { $0.id == id }) else { return }
        try? KeyStore.deleteKey(account: blog.keyAccount)
        Unsent.forget(for: id)
        Unsaved.forgetAll(for: id)
        Engine.hangUp()
        all.removeAll { $0.id == id }
        if currentID == id { currentID = all.first?.id }
        save()
    }

    private func save() {
        BlogShelf.write(all, current: currentID)
    }
}
