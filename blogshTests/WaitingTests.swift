import Foundation
import Testing
@testable import blogsh

/// Posts put by on the device until their blog can be reached. A mistake
/// here is writing that is lost, or a post sent without its pictures.
@Suite struct WaitingTests {
    /// A directory of the test's own, gone when the test is.
    private func room(_ body: (URL) throws -> Void) rethrows {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("waiting-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home)
    }

    private func moment(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_780_000_000 + seconds) }

    /// What was put by comes back whole: the words, the files under the
    /// names the text has for them, and what a card in the form needs.
    @Test func aPostPutByComesBackWithItsPictures() throws {
        try room { home in
            let blog = UUID()
            let picture = Shot(name: "photo.jpg", data: Data([1, 2, 3]), width: 40, height: 30)
            let video = Shot(name: "clip.mp4", data: Data([9, 8]), width: 0, height: 0, kind: .video, poster: Data([7]), converted: false)
            let post = Waiting(title: "Hello", tags: "a, b", text: "Text\n\n![a hill](photo.jpg)\n\n!![](clip.mp4)", at: moment(0))
            try WaitingRoom.put(post, shots: [picture, video], for: blog, in: home)

            let kept = WaitingRoom.all(for: blog, in: home)
            #expect(kept.count == 1)
            #expect(kept[0].id == post.id)
            #expect(kept[0].title == "Hello")
            #expect(kept[0].pieces.map(\.name) == ["photo.jpg", "clip.mp4"])

            let shots = WaitingRoom.shots(of: kept[0], for: blog, in: home)
            #expect(shots.map(\.name) == ["photo.jpg", "clip.mp4"])
            #expect(shots[0].data == Data([1, 2, 3]))
            #expect(shots[0].width == 40 && shots[0].height == 30)
            #expect(shots[1].kind == .video)
            #expect(shots[1].poster == Data([7]))
            #expect(shots[1].converted == false)
        }
    }

    /// As a delivery: the pictures first, the markdown last -- and the
    /// markdown dated by when the post was written, not by when it goes.
    @Test func aWaitingPostIsDeliveredDatedByWhenItWasWritten() throws {
        try room { home in
            let blog = UUID()
            let post = Waiting(title: "Hello there", tags: "", text: "![x](photo.jpg)", at: moment(0))
            try WaitingRoom.put(post, shots: [Shot(name: "photo.jpg", data: Data([1]), width: 1, height: 1)], for: blog, in: home)

            let kept = WaitingRoom.all(for: blog, in: home)[0]
            let files = try WaitingRoom.delivery(of: kept, for: blog, in: home)
            #expect(files.map(\.name) == ["photo.jpg", "hello-there.md"])
            #expect(files[0].data == Data([1]))
            let markdown = String(decoding: files[1].data, as: UTF8.self)
            // ...and under the receipt it was given when it was put by.
            let receipt = try #require(kept.receipt)
            #expect(markdown.hasPrefix("---\ntitle: Hello there\ndate: \(Markdown.stamp(moment(0)))\nreceipt: \(receipt)\n---\n\n"))
            #expect(markdown.hasSuffix("![x](photo.jpg)\n"))
        }
    }

    /// The date in the header is a moment with its offset, to the second.
    @Test func theWrittenDateCarriesItsOffset() {
        let prague = TimeZone(identifier: "Europe/Prague")!
        #expect(Markdown.stamp(Date(timeIntervalSince1970: 1_780_000_000), zone: prague) == "2026-05-28T22:26:40+02:00")
        #expect(Markdown.frontMatter(title: "", tags: "") == "")
    }

    /// Any number wait, each blog's own, in the order they were written.
    @Test func postsWaitInTheOrderTheyWereWritten() throws {
        try room { home in
            let blog = UUID(), other = UUID()
            try WaitingRoom.put(Waiting(title: "second", at: moment(60)), shots: [], for: blog, in: home)
            try WaitingRoom.put(Waiting(title: "first", at: moment(0)), shots: [], for: blog, in: home)
            try WaitingRoom.put(Waiting(title: "elsewhere", at: moment(30)), shots: [], for: other, in: home)

            #expect(WaitingRoom.all(for: blog, in: home).map(\.title) == ["first", "second"])
            #expect(WaitingRoom.all(for: other, in: home).map(\.title) == ["elsewhere"])
            #expect(WaitingRoom.all(for: UUID(), in: home).isEmpty)
        }
    }

    /// Sent or thrown away, a post is gone with its files; a blog that
    /// leaves the app takes all of its own, and nobody else's.
    @Test func whatIsSentOrThrownAwayWaitsNoLonger() throws {
        try room { home in
            let blog = UUID(), other = UUID()
            let one = Waiting(title: "one", at: moment(0)), two = Waiting(title: "two", at: moment(1))
            try WaitingRoom.put(one, shots: [Shot(name: "a.jpg", data: Data([1]), width: 1, height: 1)], for: blog, in: home)
            try WaitingRoom.put(two, shots: [], for: blog, in: home)
            try WaitingRoom.put(Waiting(title: "kept", at: moment(2)), shots: [], for: other, in: home)

            WaitingRoom.remove(one.id, for: blog, in: home)
            #expect(WaitingRoom.all(for: blog, in: home).map(\.title) == ["two"])
            #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(blog.uuidString).appendingPathComponent(one.id.uuidString).path))

            WaitingRoom.removeAll(for: blog, in: home)
            #expect(WaitingRoom.all(for: blog, in: home).isEmpty)
            #expect(WaitingRoom.all(for: other, in: home).map(\.title) == ["kept"])
        }
    }

    /// What the blog said to a post it would not take stays with the post.
    @Test func aRefusalIsKeptWithThePost() throws {
        try room { home in
            let blog = UUID()
            let post = Waiting(title: "one", at: moment(0))
            try WaitingRoom.put(post, shots: [], for: blog, in: home)

            WaitingRoom.note("Too large.", on: post.id, for: blog, in: home)
            #expect(WaitingRoom.all(for: blog, in: home)[0].problem == "Too large.")
            WaitingRoom.note(nil, on: post.id, for: blog, in: home)
            #expect(WaitingRoom.all(for: blog, in: home)[0].problem == nil)
        }
    }

    /// A name is a file of the post's own directory, whatever it says.
    @Test func aNameCannotLeaveThePostsDirectory() throws {
        try room { home in
            let blog = UUID()
            let post = Waiting(title: "one", at: moment(0))
            try WaitingRoom.put(post, shots: [Shot(name: "../../escaped.jpg", data: Data([1]), width: 1, height: 1)], for: blog, in: home)

            #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("escaped.jpg").path))
            #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(blog.uuidString).appendingPathComponent("escaped.jpg").path))
            #expect(WaitingRoom.shots(of: WaitingRoom.all(for: blog, in: home)[0], for: blog, in: home).count == 1)
        }
    }

    /// It is called what the post being written would be called.
    @Test func aWaitingPostIsCalledByItsTitleOrItsFirstWords() {
        #expect(Waiting(title: " Hello ", text: "x").headline == "Hello")
        #expect(Waiting(text: "![a](b.jpg)\n\n# First words\nmore").headline == "First words")
    }
}

/// A post taken back into the form: its pictures stay in its files for as
/// long as the form has it. Before, they were deleted on the way in and
/// lived in the form's memory alone.
@Suite struct HeldTests {
    private func room(_ body: (URL) throws -> Void) rethrows {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("held-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home)
    }

    private func moment(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_780_000_000 + seconds) }

    /// Held, a post is not listed and so not sent -- and is all there:
    /// its words and its pictures, to be found again by its name.
    @Test func aHeldPostIsNotListedAndKeepsItsPictures() throws {
        try room { home in
            let blog = UUID()
            let post = Waiting(title: "Hello", text: "![x](photo.jpg)", at: moment(0))
            try WaitingRoom.put(post, shots: [Shot(name: "photo.jpg", data: Data([1, 2, 3]), width: 4, height: 3)], for: blog, in: home)
            try WaitingRoom.put(Waiting(title: "Other", at: moment(1)), shots: [], for: blog, in: home)

            WaitingRoom.hold(post.id, for: blog, in: home)

            #expect(WaitingRoom.all(for: blog, in: home).map(\.title) == ["Other"])
            let held = try #require(WaitingRoom.one(post.id, for: blog, in: home))
            #expect(held.held == true)
            #expect(held.title == "Hello")
            let shots = WaitingRoom.shots(of: held, for: blog, in: home)
            #expect(shots.map(\.name) == ["photo.jpg"])
            #expect(shots.first?.data == Data([1, 2, 3]))
        }
    }

    /// A held post the form no longer has waits again; the one it has stays held.
    @Test func aHeldPostNobodyHoldsWaitsAgain() throws {
        try room { home in
            let blog = UUID(), other = UUID()
            let one = Waiting(title: "one", at: moment(0)), two = Waiting(title: "two", at: moment(1))
            try WaitingRoom.put(one, shots: [], for: blog, in: home)
            try WaitingRoom.put(two, shots: [], for: blog, in: home)
            try WaitingRoom.put(Waiting(title: "elsewhere", at: moment(2)), shots: [], for: other, in: home)
            WaitingRoom.hold(one.id, for: blog, in: home)
            WaitingRoom.hold(two.id, for: blog, in: home)

            WaitingRoom.release(for: blog, except: two.id, in: home)
            #expect(WaitingRoom.all(for: blog, in: home).map(\.title) == ["one"])
            #expect(WaitingRoom.one(two.id, for: blog, in: home)?.held == true)

            WaitingRoom.release(for: blog, in: home)
            #expect(WaitingRoom.all(for: blog, in: home).map(\.title) == ["one", "two"])
            #expect(WaitingRoom.all(for: other, in: home).map(\.title) == ["elsewhere"])
        }
    }

    /// Sent, put by anew or thrown away by the form, the held post goes with its files.
    @Test func aHeldPostGoesWhenTheFormIsDoneWithIt() throws {
        try room { home in
            let blog = UUID()
            let post = Waiting(title: "one", at: moment(0))
            try WaitingRoom.put(post, shots: [Shot(name: "a.jpg", data: Data([1]), width: 1, height: 1)], for: blog, in: home)
            WaitingRoom.hold(post.id, for: blog, in: home)
            WaitingRoom.remove(post.id, for: blog, in: home)
            #expect(WaitingRoom.one(post.id, for: blog, in: home) == nil)
            #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(blog.uuidString).appendingPathComponent(post.id.uuidString).path))
        }
    }

    /// The writing in the form remembers which post it was taken back
    /// from, from one opening of the form to the next.
    @Test func theWritingRemembersThePostItCameFrom() {
        let suite = "held-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let blog = UUID(), post = UUID()
        Unsent(title: "T", text: "x", at: moment(0), from: post).keep(for: blog, in: defaults)
        #expect(Unsent.kept(for: blog, in: defaults)?.from == post)
        // The same words under another origin are written down again.
        Unsent(title: "T", text: "x", at: moment(5), from: nil).keep(for: blog, in: defaults)
        #expect(Unsent.kept(for: blog, in: defaults)?.from == nil)
    }

    /// "Its pictures were not kept" is said only of pictures the form does not have back.
    @Test func picturesTheFormHasBackAreNotSaidToBeMissing() {
        let kept = Unsent(text: "![a](photo-1.jpg \"One.\")\n\n![b](photo-2.jpg)")
        #expect(!kept.namesPictures(beyond: ["photo-1.jpg", "photo-2.jpg"]))
        #expect(kept.namesPictures(beyond: ["photo-1.jpg"]))
        #expect(kept.namesPictures(beyond: []))
        #expect(!Unsent(text: "no pictures").namesPictures(beyond: []))
    }
}
