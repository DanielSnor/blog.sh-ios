import Foundation
import os

/// The pictures and videos of the post being written, kept on the device
/// beside its words (`Unsent`): chosen, not sent yet. The form holds them
/// in memory, and a form left -- a way back taken, another tile opened,
/// another blog, an app stopped behind another -- took them along; the
/// words came back and the pictures had to be found again.
///
/// The same holds for pictures added to a post the blog already has,
/// while its text is being changed: kept until the change is saved.
///
/// A directory to a blog, and in it one to each writing -- `new` for the
/// new post, of which a blog has one at a time, and `edits/<slug>` for a
/// post being changed: `shots.json`, the list in the form's order, and
/// beside it the files as they will travel.
nonisolated enum UnsentShots {
    /// One picture or video, as the form's card has it.
    struct Piece: Codable, Equatable, Sendable {
        var name: String
        var alt = ""
        var video = false
        var width = 0
        var height = 0
        var converted = true
    }

    private static let log = Logger(subsystem: "app.blogsh.ios", category: "unsent")

    static var home: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("unsent", isDirectory: true)
    }

    /// The new post's room, or that of the post whose text is being changed.
    private static func room(_ blog: UUID, _ slug: String?, in home: URL) -> URL {
        let blogs = home.appendingPathComponent(blog.uuidString, isDirectory: true)
        guard let slug else { return blogs.appendingPathComponent("new", isDirectory: true) }
        // One name, whatever the slug holds: a directory of this blog's edits.
        let name = slug.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
        return blogs.appendingPathComponent("edits", isDirectory: true)
            .appendingPathComponent(name.isEmpty ? "_" : name, isDirectory: true)
    }

    /// A name as a file of the blog's own directory, and of no other.
    private static func file(_ name: String, under directory: String, at room: URL) -> URL {
        room.appendingPathComponent(directory, isDirectory: true)
            .appendingPathComponent((name as NSString).lastPathComponent)
    }

    private static func list(at room: URL) -> [Piece] {
        guard let data = try? Data(contentsOf: room.appendingPathComponent("shots.json")),
              let pieces = try? JSONDecoder().decode([Piece].self, from: data) else { return [] }
        return pieces
    }

    /// Keeps what the form holds now: a file is written once, when its
    /// shot is new; one whose shot is gone from the form goes too. With
    /// nothing in the form, nothing is kept.
    static func keep(_ shots: [Shot], for blog: UUID, slug: String? = nil, in home: URL = home) {
        let room = room(blog, slug, in: home)
        let files = FileManager.default
        guard !shots.isEmpty else {
            try? files.removeItem(at: room)
            return
        }
        do {
            for directory in ["media", "posters"] {
                try files.createDirectory(at: room.appendingPathComponent(directory, isDirectory: true), withIntermediateDirectories: true)
            }
            let wanted = Set(shots.map { ($0.name as NSString).lastPathComponent })
            for directory in ["media", "posters"] {
                let kept = (try? files.contentsOfDirectory(atPath: room.appendingPathComponent(directory).path)) ?? []
                for name in kept where !wanted.contains(name) {
                    try? files.removeItem(at: file(name, under: directory, at: room))
                }
            }
            for shot in shots {
                let media = file(shot.name, under: "media", at: room)
                if !files.fileExists(atPath: media.path) {
                    try shot.data.write(to: media, options: .atomic)
                }
                let poster = file(shot.name, under: "posters", at: room)
                if let frame = shot.poster, !files.fileExists(atPath: poster.path) {
                    try frame.write(to: poster, options: .atomic)
                }
            }
            let pieces = shots.map {
                Piece(name: $0.name, alt: $0.alt, video: $0.kind == .video, width: $0.width, height: $0.height, converted: $0.converted)
            }
            // Last, and only when it says something new: a description
            // is typed a letter at a time.
            if pieces != list(at: room) {
                try JSONEncoder().encode(pieces).write(to: room.appendingPathComponent("shots.json"), options: .atomic)
            }
        } catch {
            // Not kept, then: the form still has them, and says so itself
            // when it comes back without.
            log.error("shots not kept: \(String(describing: error), privacy: .public)")
        }
    }

    /// What is kept for a blog, as the form holds its shots; one whose
    /// file does not read is left out.
    static func shots(for blog: UUID, slug: String? = nil, in home: URL = home) -> [Shot] {
        let room = room(blog, slug, in: home)
        return list(at: room).compactMap { piece in
            guard let data = try? Data(contentsOf: file(piece.name, under: "media", at: room)) else { return nil }
            return Shot(name: piece.name, data: data, width: piece.width, height: piece.height, alt: piece.alt,
                        kind: piece.video ? .video : .picture,
                        poster: try? Data(contentsOf: file(piece.name, under: "posters", at: room)),
                        converted: piece.converted,
                        thumb: piece.video ? nil : Pictures.thumbnail(data))
        }
    }

    /// When they were last kept; nil where nothing is.
    static func kept(for blog: UUID, slug: String? = nil, in home: URL = home) -> Date? {
        let list = room(blog, slug, in: home).appendingPathComponent("shots.json")
        return (try? FileManager.default.attributesOfItem(atPath: list.path))?[.modificationDate] as? Date
    }

    /// The post was sent, put by or thrown away; the change was saved or given up.
    static func forget(for blog: UUID, slug: String? = nil, in home: URL = home) {
        try? FileManager.default.removeItem(at: room(blog, slug, in: home))
    }

    /// The post was renamed: what was kept for it follows it to its new name.
    static func move(for blog: UUID, from old: String, to new: String, in home: URL = home) {
        let from = room(blog, old, in: home), to = room(blog, new, in: home)
        guard old != new, FileManager.default.fileExists(atPath: from.path) else { return }
        try? FileManager.default.removeItem(at: to)
        try? FileManager.default.moveItem(at: from, to: to)
    }

    /// Everything kept for a blog that leaves the app.
    static func forgetAll(for blog: UUID, in home: URL = home) {
        try? FileManager.default.removeItem(at: home.appendingPathComponent(blog.uuidString, isDirectory: true))
    }
}
