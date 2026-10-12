import Foundation
import Testing
@testable import blogsh

/// The pictures of the post being written are kept beside its words.
@Suite struct UnsentShotsTests {
    private func home() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("unsent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func shot(_ name: String, _ bytes: [UInt8], alt: String = "", video: Bool = false) -> Shot {
        Shot(name: name, data: Data(bytes), width: 4, height: 3, alt: alt, kind: video ? .video : .picture,
             poster: video ? Data([9, 9]) : nil, converted: !video)
    }

    private func files(_ home: URL, _ blog: UUID, _ directory: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(blog.uuidString).appendingPathComponent(directory).path)) ?? []).sorted()
    }

    /// What the form held comes back as it held it: the order, the
    /// names, the descriptions, what kind each is, and the files.
    @Test func whatTheFormHeldComesBack() throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        let blog = UUID()
        UnsentShots.keep([shot("b.jpg", [2, 2], alt: "Druhý"), shot("a.mp4", [1], video: true)], for: blog, in: home)
        let back = UnsentShots.shots(for: blog, in: home)
        #expect(back.map(\.name) == ["b.jpg", "a.mp4"])
        #expect(back.map(\.alt) == ["Druhý", ""])
        #expect(back.map(\.data) == [Data([2, 2]), Data([1])])
        #expect(back[1].kind == .video)
        #expect(back[1].poster == Data([9, 9]))
        #expect(back[1].converted == false)
        #expect(back[0].width == 4 && back[0].height == 3)
        #expect(UnsentShots.kept(for: blog, in: home) != nil)
    }

    /// A shot taken out of the form leaves no file behind; one added
    /// later is written beside the rest, which are not written again.
    @Test func theFilesFollowTheForm() throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        let blog = UUID()
        UnsentShots.keep([shot("a.jpg", [1]), shot("v.mp4", [5], video: true)], for: blog, in: home)
        #expect(files(home, blog, "media") == ["a.jpg", "v.mp4"])
        #expect(files(home, blog, "posters") == ["v.mp4"])
        // The same name kept again is not written over: the file is the shot's.
        UnsentShots.keep([shot("a.jpg", [7, 7, 7]), shot("c.jpg", [3])], for: blog, in: home)
        #expect(files(home, blog, "media") == ["a.jpg", "c.jpg"])
        #expect(files(home, blog, "posters") == [])
        #expect(UnsentShots.shots(for: blog, in: home).map(\.data) == [Data([1]), Data([3])])
    }

    /// A description typed later is kept; the picture's file is as it was.
    @Test func aDescriptionTypedLaterIsKept() throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        let blog = UUID()
        UnsentShots.keep([shot("a.jpg", [1])], for: blog, in: home)
        UnsentShots.keep([shot("a.jpg", [1], alt: "Les po dešti")], for: blog, in: home)
        #expect(UnsentShots.shots(for: blog, in: home).map(\.alt) == ["Les po dešti"])
    }

    /// An emptied form keeps nothing, and neither does a blog that left;
    /// another blog's pictures are not touched by either.
    @Test func anEmptiedFormKeepsNothing() throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        let blog = UUID(), other = UUID()
        UnsentShots.keep([shot("a.jpg", [1])], for: blog, in: home)
        UnsentShots.keep([shot("o.jpg", [8])], for: other, in: home)
        UnsentShots.keep([], for: blog, in: home)
        #expect(UnsentShots.shots(for: blog, in: home).isEmpty)
        #expect(UnsentShots.kept(for: blog, in: home) == nil)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(blog.uuidString).path))
        #expect(UnsentShots.shots(for: other, in: home).map(\.name) == ["o.jpg"])
        UnsentShots.forget(for: other, in: home)
        #expect(UnsentShots.shots(for: other, in: home).isEmpty)
    }

    /// A name cannot reach out of the blog's own directory.
    @Test func aNameStaysInItsDirectory() throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        let blog = UUID()
        UnsentShots.keep([shot("../../ven.jpg", [1])], for: blog, in: home)
        #expect(files(home, blog, "media") == ["ven.jpg"])
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("ven.jpg").path))
        #expect(UnsentShots.shots(for: blog, in: home).map(\.data) == [Data([1])])
    }

    /// A picture whose file is gone is left out, and the rest come back.
    @Test func aLostFileIsLeftOut() throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        let blog = UUID()
        UnsentShots.keep([shot("a.jpg", [1]), shot("b.jpg", [2])], for: blog, in: home)
        try FileManager.default.removeItem(at: home.appendingPathComponent(blog.uuidString).appendingPathComponent("media/a.jpg"))
        #expect(UnsentShots.shots(for: blog, in: home).map(\.name) == ["b.jpg"])
    }
}
