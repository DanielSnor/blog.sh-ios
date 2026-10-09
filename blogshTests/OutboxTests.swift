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

/// What an audit of the sending found, each as the second reader made it
/// fail: a post sent that was thrown away, a blog whose posts nobody came
/// back for, a post written twice.
@MainActor @Suite struct OutboxAuditTests {
    /// What a blog was sent: whose delivery, the names, and the markdown.
    final class Blog {
        var got: [[String]] = []
        var whose: [UUID] = []
        var markdown: [String] = []

        func take(_ files: [DeliveryFile], for blog: UUID) {
            got.append(files.map(\.name))
            whose.append(blog)
            markdown.append(String(decoding: files.last?.data ?? Data(), as: UTF8.self))
        }
    }

    private func answer(_ slug: String) throws -> ActionAnswer {
        try JSONDecoder().decode(ActionAnswer.self, from: Data(#"{"ok":true,"slug":"\#(slug)"}"#.utf8))
    }

    private func room(_ body: (URL) async throws -> Void) async rethrows {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-audit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try await body(home)
    }

    private func moment(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_780_000_000 + seconds) }

    /// A post thrown away while an earlier one is on its way is not sent
    /// from what the run remembered of the room.
    @Test func aPostThrownAwayWhileAnotherIsOnItsWayIsNotSent() async throws {
        try await room { home in
            let id = UUID(), blog = Blog()
            let one = Waiting(title: "one", at: moment(0)), two = Waiting(title: "two", at: moment(1))
            try WaitingRoom.put(one, shots: [], for: id, in: home)
            try WaitingRoom.put(two, shots: [], for: id, in: home)
            let (gate, open) = AsyncStream<Void>.makeStream()
            let outbox = Outbox(home: home, open: { id }, deliver: { files, to in
                blog.take(files, for: to)
                // The first upload takes its time: somebody is in the list meanwhile.
                if blog.got.count == 1 { for await _ in gate { break } }
                return try self.answer("a-draft")
            })

            let run = Task { await outbox.sendAll(for: id) }
            while outbox.sending == nil { await Task.yield() }
            #expect(outbox.sending == one.id)
            // The list's "Throw away", after "It was never sent; nothing of it is kept."
            WaitingRoom.remove(two.id, for: id, in: home)
            open.yield()

            #expect(await run.value == 1)
            #expect(blog.got == [["one.md"]])
        }
    }

    /// A blog opened while another blog's post is on its way has its own
    /// posts sent, after it: nobody else would ask again.
    @Test func aBlogOpenedWhileAnothersPostIsOnItsWayHasItsOwnPostsSent() async throws {
        try await room { home in
            let a = UUID(), b = UUID(), blog = Blog()
            var current = a
            try WaitingRoom.put(Waiting(title: "of a", at: moment(0)), shots: [], for: a, in: home)
            try WaitingRoom.put(Waiting(title: "of b", at: moment(1)), shots: [], for: b, in: home)
            let (gate, open) = AsyncStream<Void>.makeStream()
            let outbox = Outbox(home: home, open: { current }, deliver: { files, to in
                blog.take(files, for: to)
                if blog.got.count == 1 { for await _ in gate { break } }
                return try self.answer("a-draft")
            })

            let first = Task { await outbox.sendAll(for: a) }
            while outbox.sending == nil { await Task.yield() }
            current = b
            let second = Task { await outbox.sendAll(for: b) }
            for _ in 0..<50 { await Task.yield() }
            open.yield()
            _ = await first.value
            _ = await second.value

            #expect(blog.whose == [a, b])
            #expect(WaitingRoom.all(for: a, in: home).isEmpty)
            #expect(WaitingRoom.all(for: b, in: home).isEmpty)
        }
    }

    /// The server has the whole delivery and the app is gone before the
    /// answer. The next launch sends the post again -- under the same
    /// receipt, by which the engine knows it for the one it has.
    @Test func aPostTheServerTookBeforeTheAppDiedGoesAgainUnderTheSameReceipt() async throws {
        try await room { home in
            let id = UUID(), blog = Blog()
            try WaitingRoom.put(Waiting(title: "one", text: "Words.", at: moment(0)), shots: [], for: id, in: home)
            let (gate, open) = AsyncStream<Void>.makeStream()
            // The run that was cut off: everything was written, the answer never came.
            let before = Outbox(home: home, open: { id }, deliver: { files, to in
                blog.take(files, for: to)
                for await _ in gate { break }
                throw CancellationError()
            })
            let cut = Task { await before.sendAll(for: id) }
            while before.sending == nil { await Task.yield() }

            // The next launch.
            let after = Outbox(home: home, open: { id }, deliver: { files, to in
                blog.take(files, for: to)
                return try self.answer("one")
            })
            await after.sendAll(for: id)
            open.yield()
            _ = await cut.value

            let receipts = blog.markdown.map { text in
                text.split(separator: "\n").first { $0.hasPrefix("receipt: ") }.map { String($0.dropFirst(9)) }
            }
            #expect(receipts.count == 2)
            #expect(receipts[0] != nil && receipts[0] == receipts[1])
            #expect(Receipt.isOne(receipts[0] ?? ""))
        }
    }

    /// The blog is busy -- another delivery is being taken, the site is
    /// being built: that is not a no to the post. It waits without a
    /// reason written on it, and goes with the next asking.
    @Test func aBusyBlogLeavesThePostWaiting() async throws {
        try await room { home in
            let id = UUID(), blog = Blog()
            try WaitingRoom.put(Waiting(title: "one", at: moment(0)), shots: [], for: id, in: home)
            var busy = true
            let outbox = Outbox(home: home, open: { id }, deliver: { files, to in
                blog.take(files, for: to)
                if busy {
                    throw EngineError.refused(try JSONDecoder().decode(Refusal.self, from: Data(#"{"ok":false,"error":"busy","message":"Another delivery is being taken."}"#.utf8)))
                }
                return try self.answer("one")
            })

            #expect(await outbox.sendAll(for: id) == 0)
            #expect(WaitingRoom.all(for: id, in: home).map(\.problem) == [nil])
            busy = false
            #expect(await outbox.sendAll(for: id) == 1)
            #expect(WaitingRoom.all(for: id, in: home).isEmpty)
        }
    }

    /// A receipt is what the engine takes for one, and no two posts share one.
    @Test func aReceiptIsSixteenLowercaseHexDigitsOfItsOwn() {
        let one = Receipt.mint(), two = Receipt.mint()
        #expect(one.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil)
        #expect(one != two)
        #expect(!Receipt.isOne("ABCDEF0123456789"))
        #expect(!Receipt.isOne("abc"))
        #expect(!Receipt.isOne("0123456789abcdef\nx: y"))
        #expect(Markdown.frontMatter(title: "T", tags: "", receipt: "0123456789abcdef") == "---\ntitle: T\nreceipt: 0123456789abcdef\n---\n\n")
        // What is not a receipt is not written: the engine refuses a bad one.
        #expect(Markdown.frontMatter(title: "T", tags: "", receipt: "nope") == "---\ntitle: T\n---\n\n")
    }

    /// The post being written keeps its receipt from one opening of the
    /// form to the next, and takes it along when it is put by and back.
    @Test func aPostKeepsItsReceiptWhereverItWaits() async throws {
        let suite = "outbox-audit-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let blog = UUID()
        Unsent(title: "T", text: "x", at: moment(0), receipt: "0123456789abcdef").keep(for: blog, in: defaults)
        #expect(Unsent.kept(for: blog, in: defaults)?.receipt == "0123456789abcdef")

        try await room { home in
            try WaitingRoom.put(Waiting(title: "T", text: "x", at: moment(0), receipt: "0123456789abcdef"), shots: [], for: blog, in: home)
            #expect(WaitingRoom.all(for: blog, in: home)[0].receipt == "0123456789abcdef")
            // One put by without a name is given one, written down with it.
            try WaitingRoom.put(Waiting(title: "U", at: moment(1)), shots: [], for: blog, in: home)
            let given = WaitingRoom.all(for: blog, in: home)[1].receipt
            #expect(Receipt.isOne(given ?? ""))
            #expect(WaitingRoom.all(for: blog, in: home)[1].receipt == given)
        }
    }
}
