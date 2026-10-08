import Foundation
import Testing
@testable import blogsh

/// Posts on their way from the device to the blog. A mistake here is a
/// post sent twice, sent to the wrong blog, or lost on the way.
@MainActor @Suite struct OutboxTests {
    /// A blog that answers as it is told to, and remembers what it was sent.
    final class Blog {
        var answers: [Result<String, Error>] = []
        var got: [[String]] = []

        func deliver(_ files: [DeliveryFile]) throws -> ActionAnswer {
            got.append(files.map(\.name))
            let slug = try (answers.isEmpty ? .success("a-draft") : answers.removeFirst()).get()
            return try JSONDecoder().decode(ActionAnswer.self, from: Data(#"{"ok":true,"slug":"\#(slug)"}"#.utf8))
        }
    }

    private func room(_ body: (URL) async throws -> Void) async rethrows {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try await body(home)
    }

    private func moment(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_780_000_000 + seconds) }

    private func refusal(_ message: String) -> EngineError {
        .refused(try! JSONDecoder().decode(Refusal.self, from: Data(#"{"ok":false,"error":"too_large","message":"\#(message)"}"#.utf8)))
    }

    /// A post that arrived waits no longer, and went with its pictures first.
    @Test func aPostThatArrivedWaitsNoLonger() async throws {
        try await room { home in
            let id = UUID(), blog = Blog()
            let post = Waiting(title: "Hello", text: "![x](photo.jpg)", at: moment(0))
            try WaitingRoom.put(post, shots: [Shot(name: "photo.jpg", data: Data([1]), width: 1, height: 1)], for: id, in: home)
            let outbox = Outbox(home: home, open: { id }, deliver: { files, _ in try blog.deliver(files) })

            #expect(await outbox.send(WaitingRoom.all(for: id, in: home)[0], for: id) == .sent("a-draft"))
            #expect(blog.got == [["photo.jpg", "hello.md"]])
            #expect(WaitingRoom.all(for: id, in: home).isEmpty)
            #expect(outbox.sending == nil)
        }
    }

    /// A silent server refuses nothing: the post still waits, with no
    /// reason written on it, and the ones after it are not tried.
    @Test func aSilentServerLeavesEverythingWaiting() async throws {
        try await room { home in
            let id = UUID(), blog = Blog()
            blog.answers = [.failure(EngineError.unreachable("one.example", "timeout"))]
            try WaitingRoom.put(Waiting(title: "one", at: moment(0)), shots: [], for: id, in: home)
            try WaitingRoom.put(Waiting(title: "two", at: moment(1)), shots: [], for: id, in: home)
            let outbox = Outbox(home: home, open: { id }, deliver: { files, _ in try blog.deliver(files) })

            #expect(await outbox.sendAll(for: id) == 0)
            #expect(blog.got == [["one.md"]])
            #expect(WaitingRoom.all(for: id, in: home).map(\.title) == ["one", "two"])
            #expect(WaitingRoom.all(for: id, in: home).allSatisfy { $0.problem == nil })
        }
    }

    /// What the blog turned away is kept with its reason and not sent
    /// again unasked; the posts after it go.
    @Test func aRefusedPostIsKeptWithItsReasonAndTheRestGo() async throws {
        try await room { home in
            let id = UUID(), blog = Blog()
            blog.answers = [.failure(refusal("Too large.")), .success("two")]
            try WaitingRoom.put(Waiting(title: "one", at: moment(0)), shots: [], for: id, in: home)
            try WaitingRoom.put(Waiting(title: "two", at: moment(1)), shots: [], for: id, in: home)
            let outbox = Outbox(home: home, open: { id }, deliver: { files, _ in try blog.deliver(files) })

            #expect(await outbox.sendAll(for: id) == 1)
            let left = WaitingRoom.all(for: id, in: home)
            #expect(left.map(\.title) == ["one"])
            #expect(left[0].problem == "Too large.")

            // Asked again by itself, it leaves the refused one alone...
            #expect(await outbox.sendAll(for: id) == 0)
            #expect(blog.got.count == 2)
            // ...and sent by hand, it goes.
            #expect(await outbox.send(left[0], for: id) == .sent("a-draft"))
            #expect(WaitingRoom.all(for: id, in: home).isEmpty)
        }
    }

    /// What was written for one blog is never sent with another open.
    @Test func nothingIsSentWithAnotherBlogOpen() async throws {
        try await room { home in
            let id = UUID(), blog = Blog()
            try WaitingRoom.put(Waiting(title: "one", at: moment(0)), shots: [], for: id, in: home)
            let outbox = Outbox(home: home, open: { UUID() }, deliver: { files, _ in try blog.deliver(files) })

            #expect(await outbox.sendAll(for: id) == 0)
            #expect(blog.got.isEmpty)
            #expect(WaitingRoom.all(for: id, in: home).count == 1)
        }
    }

    /// They go in the order they were written.
    @Test func postsGoInTheOrderTheyWereWritten() async throws {
        try await room { home in
            let id = UUID(), blog = Blog()
            try WaitingRoom.put(Waiting(title: "later", at: moment(60)), shots: [], for: id, in: home)
            try WaitingRoom.put(Waiting(title: "sooner", at: moment(0)), shots: [], for: id, in: home)
            let outbox = Outbox(home: home, open: { id }, deliver: { files, _ in try blog.deliver(files) })

            #expect(await outbox.sendAll(for: id) == 2)
            #expect(blog.got == [["sooner.md"], ["later.md"]])
        }
    }

    /// A delivery's answers: the last is the engine's own, a no among them is thrown.
    @Test func aDeliverysAnswersAreReadToTheLastOrTheFirstNo() throws {
        let fine = Data(#"{"ok":true}"#.utf8), made = Data(#"{"ok":true,"slug":"hello"}"#.utf8)
        #expect(try Engine.made(from: [fine, made]).slug == "hello")
        let no = Data(#"{"ok":false,"error":"too_large","message":"Too large."}"#.utf8)
        #expect(throws: EngineError.self) { try Engine.made(from: [no, made]) }
        #expect(throws: EngineError.self) { try Engine.made(from: []) }
    }

    /// Only the open blog is connected to, when a call says whose it is.
    @Test func aCallMeantForOneBlogFindsNoOther() {
        let suite = "outbox-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var blog = blogsh.Blog()
        blog.host = "one.example"
        blog.user = "dan"
        BlogShelf.write([blog], current: blog.id, to: defaults)

        #expect(ServerSettings.load(from: defaults, only: blog.id)?.host == "one.example")
        #expect(ServerSettings.load(from: defaults, only: UUID()) == nil)
        #expect(ServerSettings.load(from: defaults)?.host == "one.example")
    }
}
