import Foundation

/// A post that was finished while its blog could not be reached, put by
/// on the device to be sent when it can: its words, and the pictures and
/// videos they name, as they will travel. Unlike the post being written
/// (`Unsent`), of which a blog has one, any number can wait -- each is
/// done with, and the form is free for the next.
///
/// What it holds of a picture is what a delivery needs and what its card
/// in the form needs to come back; the description is in the text's own
/// mark for it, as it always is.
nonisolated struct Waiting: Codable, Identifiable, Equatable, Sendable {
    /// One picture or video, as the post names it.
    struct Piece: Codable, Equatable, Sendable {
        var name: String
        var video = false
        var width = 0
        var height = 0
        var converted = true
    }

    var id = UUID()
    var title = ""
    var tags = ""
    var text = ""
    /// When it was put by: what the list says of it, and the order the
    /// posts go in. Not the post's date -- a draft is dated by the blog
    /// when it is published, as every draft is; sent with a date of its
    /// own it would come out dated back to the day it was written.
    var at = Date.distantPast
    var pieces: [Piece] = []
    /// Why the blog turned it away the last time it was sent, in its own words.
    var problem: String?
    /// The name its delivery goes under, the same every time it is sent:
    /// a post the server took just before the app was stopped is sent
    /// again the next time, and the blog knows it for the one it has.
    var receipt: String?
    /// Taken back into the form to be written on. It waits for nothing
    /// then -- it is not listed and not sent -- but its files stay where
    /// they are until the form has sent it, put it by again or been
    /// emptied: the form holds pictures in memory only, and a form left,
    /// or an app stopped, would otherwise take them along.
    var held: Bool?

    /// What to call it where it is listed, as the post being written is called.
    var headline: String { Unsent(title: title, tags: tags, text: text).headline }
}

/// Where the posts that wait are kept: a directory to a blog, one to a
/// post in it -- `post.json`, and beside it the files the post goes with.
/// Files, not defaults: a delivery is megabytes.
nonisolated enum WaitingRoom {
    static var home: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("waiting", isDirectory: true)
    }

    private static func room(_ blog: UUID, in home: URL) -> URL {
        home.appendingPathComponent(blog.uuidString, isDirectory: true)
    }

    private static func place(_ id: UUID, _ blog: UUID, in home: URL) -> URL {
        room(blog, in: home).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// A name as a file of the post's own directory, and of no other.
    private static func file(_ name: String, under directory: String, at place: URL) -> URL {
        place.appendingPathComponent(directory, isDirectory: true)
            .appendingPathComponent((name as NSString).lastPathComponent)
    }

    /// Puts a post by with its files. All of it or none: a post without
    /// one of its pictures is not a post that waits.
    static func put(_ post: Waiting, shots: [Shot], for blog: UUID, in home: URL = home) throws {
        let place = place(post.id, blog, in: home)
        let files = FileManager.default
        do {
            try files.createDirectory(at: place.appendingPathComponent("media", isDirectory: true), withIntermediateDirectories: true)
            try files.createDirectory(at: place.appendingPathComponent("posters", isDirectory: true), withIntermediateDirectories: true)
            var post = post
            // Given here at the latest, and written down with the post.
            if !(post.receipt.map(Receipt.isOne) ?? false) { post.receipt = Receipt.mint() }
            post.pieces = shots.map {
                Waiting.Piece(name: $0.name, video: $0.kind == .video, width: $0.width, height: $0.height, converted: $0.converted)
            }
            for shot in shots {
                try shot.data.write(to: file(shot.name, under: "media", at: place), options: .atomic)
                if let poster = shot.poster {
                    try poster.write(to: file(shot.name, under: "posters", at: place), options: .atomic)
                }
            }
            // Last: what is listed is what has all of its files.
            try JSONEncoder().encode(post).write(to: place.appendingPathComponent("post.json"), options: .atomic)
        } catch {
            try? files.removeItem(at: place)
            throw error
        }
    }

    /// What waits for a blog, in the order it was written: that is the
    /// order it is sent in. A post held by the form is not among them.
    static func all(for blog: UUID, in home: URL = home) -> [Waiting] {
        everything(for: blog, in: home).filter { $0.held != true }
    }

    /// Every post kept for a blog, the held ones too.
    private static func everything(for blog: UUID, in home: URL) -> [Waiting] {
        let places = (try? FileManager.default.contentsOfDirectory(at: room(blog, in: home), includingPropertiesForKeys: nil)) ?? []
        return places.compactMap { place in
            guard let data = try? Data(contentsOf: place.appendingPathComponent("post.json")) else { return nil }
            return try? JSONDecoder().decode(Waiting.self, from: data)
        }
        .sorted { ($0.at, $0.id.uuidString) < ($1.at, $1.id.uuidString) }
    }

    /// One post by its name, held or not.
    static func one(_ id: UUID, for blog: UUID, in home: URL = home) -> Waiting? {
        guard let data = try? Data(contentsOf: place(id, blog, in: home).appendingPathComponent("post.json")) else { return nil }
        return try? JSONDecoder().decode(Waiting.self, from: data)
    }

    /// The post was taken back into the form: held from here on.
    static func hold(_ id: UUID, for blog: UUID, in home: URL = home) {
        mark(id, for: blog, in: home) { $0.held = true }
    }

    /// Every held post of a blog waits again -- except the one the form
    /// still has. A held post nobody holds any more (the form's words
    /// were cleared, the app was stopped at the wrong moment) would
    /// otherwise be on the device and nowhere to be seen.
    static func release(for blog: UUID, except kept: UUID? = nil, in home: URL = home) {
        for post in everything(for: blog, in: home) where post.held == true && post.id != kept {
            mark(post.id, for: blog, in: home) { $0.held = nil }
        }
    }

    private static func mark(_ id: UUID, for blog: UUID, in home: URL, _ change: (inout Waiting) -> Void) {
        let file = place(id, blog, in: home).appendingPathComponent("post.json")
        guard let data = try? Data(contentsOf: file), var post = try? JSONDecoder().decode(Waiting.self, from: data) else { return }
        let before = post
        change(&post)
        guard post != before else { return }
        try? JSONEncoder().encode(post).write(to: file, options: .atomic)
    }

    /// The post as a delivery: its pictures first and the markdown last.
    static func delivery(of post: Waiting, for blog: UUID, in home: URL = home) throws -> [DeliveryFile] {
        let place = place(post.id, blog, in: home)
        var files = try post.pieces.map {
            DeliveryFile(name: $0.name, data: try Data(contentsOf: file($0.name, under: "media", at: place)))
        }
        let markdown = Markdown.file(title: post.title, tags: post.tags, body: post.text, receipt: post.receipt)
        files.append(DeliveryFile(name: Markdown.fileName(title: post.title, body: post.text), data: Data(markdown.utf8)))
        return files
    }

    /// Its pictures as the form holds them, for a post taken back to be
    /// written on; the descriptions are the text's to give them.
    static func shots(of post: Waiting, for blog: UUID, in home: URL = home) -> [Shot] {
        let place = place(post.id, blog, in: home)
        return post.pieces.compactMap { piece in
            guard let data = try? Data(contentsOf: file(piece.name, under: "media", at: place)) else { return nil }
            return Shot(name: piece.name, data: data, width: piece.width, height: piece.height,
                        kind: piece.video ? .video : .picture,
                        poster: try? Data(contentsOf: file(piece.name, under: "posters", at: place)),
                        converted: piece.converted,
                        thumb: piece.video ? nil : Pictures.thumbnail(data))
        }
    }

    /// What the blog said to a post it would not take, kept with the post.
    static func note(_ problem: String?, on id: UUID, for blog: UUID, in home: URL = home) {
        let file = place(id, blog, in: home).appendingPathComponent("post.json")
        guard let data = try? Data(contentsOf: file), var post = try? JSONDecoder().decode(Waiting.self, from: data),
              post.problem != problem else { return }
        post.problem = problem
        try? JSONEncoder().encode(post).write(to: file, options: .atomic)
    }

    /// Sent, or thrown away: it waits no longer.
    static func remove(_ id: UUID, for blog: UUID, in home: URL = home) {
        try? FileManager.default.removeItem(at: place(id, blog, in: home))
    }

    /// Everything kept for a blog that leaves the app.
    static func removeAll(for blog: UUID, in home: URL = home) {
        try? FileManager.default.removeItem(at: room(blog, in: home))
    }
}
