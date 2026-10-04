import SwiftUI

/// One blog the app drives: where it is, what it is reached through, the
/// key it is reached with, and what it last said about itself -- so its
/// screen opens as that blog, in its colour, before the server has
/// answered. A key belongs to one blog: on the server a key runs one
/// forced command, and that command is one blog's `scripts/remote.sh`.
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
    var maxMb = 24

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
        maxMb = try c.decodeIfPresent(Int.self, forKey: .maxMb) ?? 24
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

    /// A new blog, open and empty: its place and its key are the settings' to fill in.
    @discardableResult
    func add() -> Blog {
        let blog = Blog()
        all.append(blog)
        currentID = blog.id
        save()
        return blog
    }

    /// The blog leaves the app, and its key with it. The blog itself is not touched.
    func remove(_ id: UUID) {
        guard let blog = all.first(where: { $0.id == id }) else { return }
        try? KeyStore.deleteKey(account: blog.keyAccount)
        all.removeAll { $0.id == id }
        if currentID == id { currentID = all.first?.id }
        save()
    }

    private func save() {
        BlogShelf.write(all, current: currentID)
    }
}
