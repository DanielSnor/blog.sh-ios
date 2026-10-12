import Foundation
import Testing
@testable import blogsh

/// The practice blog answers what the app asks a blog, in the shapes the
/// engine gives them -- they were said by one -- and says no to whatever
/// would write.
@Suite struct PracticeTests {
    private func refused(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(Refusal.self, from: data))?.error == "practice"
    }

    /// Everything the first screen and the lists ask for is read as the
    /// app reads a real blog's answers.
    @Test func whatTheScreensAskForIsAnswered() throws {
        let version: VersionAnswer = try Engine.decode(Practice.answer(to: ["version"]))
        #expect(version.site.name == "Practice blog")
        #expect(version.site.url.isEmpty)
        let list: ListAnswer = try Engine.decode(Practice.answer(to: ["list"]))
        #expect(list.posts.count == 7)
        let drafts: ListAnswer = try Engine.decode(Practice.answer(to: ["list", "--drafts"]))
        #expect(drafts.posts.count == 2)
        let queue: QueueAnswer = try Engine.decode(Practice.answer(to: ["queue"]))
        #expect(queue.queue.isEmpty)
        let _: StatsAnswer = try Engine.decode(Practice.answer(to: ["stats"]))
        let _: HeldAnswer = try Engine.decode(Practice.answer(to: ["empty", "trash"]))
        let _: HeldAnswer = try Engine.decode(Practice.answer(to: ["empty", "versions"]))
        let check: DiagnosisAnswer = try Engine.decode(Practice.answer(to: ["check"]))
        #expect(check.errors == 0)
        let doctor: DiagnosisAnswer = try Engine.decode(Practice.answer(to: ["doctor"]))
        #expect(doctor.findings.count == 1)
        let devices: PairedDevices = try Engine.decode(Practice.answer(to: ["pair", "--list"]))
        #expect(devices.devices.isEmpty && !devices.mayLeave)
    }

    /// Every post of the list opens: its properties, its text, its versions.
    @Test func everyPostOpens() throws {
        let list: ListAnswer = try Engine.decode(Practice.answer(to: ["list"]))
        for post in list.posts {
            let props: PropsAnswer = try Engine.decode(Practice.answer(to: ["props", post.slug]))
            #expect(props.slug == post.slug)
            #expect(props.url.isEmpty)
            let edit: EditAnswer = try Engine.decode(Practice.answer(to: ["edit", post.slug]))
            #expect(edit.post.text?.isEmpty == false)
            let _: VersionsAnswer = try Engine.decode(Practice.answer(to: ["props", post.slug, "--versions"]))
        }
    }

    /// A search finds by what a row says of its post.
    @Test func aSearchFindsInTheList() throws {
        let found: ListAnswer = try Engine.decode(Practice.answer(to: ["list", "--search=pictures"]))
        #expect(found.posts.map(\.slug) == ["pictures-and-video"])
        let none: ListAnswer = try Engine.decode(Practice.answer(to: ["list", "--search=zzz"]))
        #expect(none.posts.isEmpty)
    }

    /// Nothing is written: what would change the blog is said no to, in
    /// a sentence, and a delivery is not taken.
    @Test func whatWouldWriteIsSaidNoTo() throws {
        for args in [["publish", "writing-a-post", "--yes"], ["delete", "writing-a-post", "--yes"], ["rebuild"],
                     ["props", "writing-a-post", "--set", "pinned=yes"], ["empty", "trash", "--yes"], ["restore", "thrown-away"],
                     ["schedule", "a-draft-about-autumn", "--at", "2027-01-01T10:00:00+01:00"], ["pair", "--revoke"], ["props", "no-such-post"]] {
            #expect(refused(Practice.answer(to: args)), "\(args)")
        }
        #expect(throws: EngineError.self) { try Engine.made(from: Practice.delivered) }
        let no = try JSONDecoder().decode(Refusal.self, from: Practice.answer(to: ["rebuild"]))
        #expect(no.words == Practice.refusal)
    }

    /// Nothing of the machine the answers were made on is carried along.
    @Test func theAnswersNameNoMachine() throws {
        let url = try #require(Bundle.main.url(forResource: "Practice", withExtension: "json"))
        let text = try String(contentsOf: url, encoding: .utf8)
        for trace in ["/var/folders", "/Users/", "example.com", "localhost"] {
            #expect(!text.contains(trace), "\(trace)")
        }
    }

    /// The record of the practice blog is kept and read back as one.
    @Test func thePracticeBlogIsKeptAsOne() throws {
        var blog = Blog()
        blog.practice = true
        let back = try JSONDecoder().decode(Blog.self, from: JSONEncoder().encode(blog))
        #expect(back.isPractice)
        #expect(!(try JSONDecoder().decode(Blog.self, from: JSONEncoder().encode(Blog()))).isPractice)
    }
}
