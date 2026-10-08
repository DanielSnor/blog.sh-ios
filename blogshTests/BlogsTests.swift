import Foundation
import SwiftUI
import Testing
@testable import blogsh

/// The blogs the app holds, and how they are written down.
@Suite(.serialized) struct BlogsTests {
    /// Defaults of the tests' own, empty before a test and after it. One
    /// name for all of them: the system leaves a file behind for every
    /// domain it has ever been asked for, and a name a test would leave a
    /// file a test. That is also why the suite runs one test at a time.
    private func shelf(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "app.blogsh.ios.tests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    /// The app had one server before it had blogs. What was set up for it
    /// becomes the first blog, with the key it already had.
    @Test func whatWasSetUpBeforeBecomesTheFirstBlog() {
        shelf { defaults in
            defaults.set("blog.example", forKey: "server.host")
            defaults.set("dan", forKey: "server.user")
            defaults.set(202, forKey: "server.port")
            defaults.set("/app/data/blog", forKey: "server.path")
            defaults.set("sudo docker exec -i blog", forKey: "server.through")
            defaults.set("A Blog", forKey: "site.name")
            defaults.set("its claim", forKey: "site.claim")
            defaults.set("https://blog.example", forKey: "site.url")
            defaults.set("#ff5a00", forKey: "site.accent.light")
            defaults.set("#ff7a30", forKey: "site.accent.dark")
            defaults.set(48, forKey: "site.maxMb")

            let read = BlogShelf.read(from: defaults)
            #expect(read.blogs.count == 1)
            let blog = read.blogs[0]
            #expect(read.current == blog.id)
            #expect(blog.host == "blog.example")
            #expect(blog.user == "dan")
            #expect(blog.port == 202)
            #expect(blog.path == "/app/data/blog")
            #expect(blog.through == "sudo docker exec -i blog")
            #expect(blog.keyAccount == KeyStore.firstAccount)
            #expect(blog.name == "A Blog")
            #expect(blog.claim == "its claim")
            #expect(blog.url == "https://blog.example")
            #expect(blog.accentLight == "#ff5a00")
            #expect(blog.accentDark == "#ff7a30")
            #expect(blog.maxMb == 48)
        }
    }

    @Test func theOldSettingsAreTakenOverOnce() {
        shelf { defaults in
            defaults.set("blog.example", forKey: "server.host")
            let first = BlogShelf.read(from: defaults)
            let second = BlogShelf.read(from: defaults)
            #expect(second.blogs.count == 1)
            #expect(second.blogs[0].id == first.blogs[0].id)
        }
    }

    @Test func aPortAndALimitNeverSetTakeTheirDefaults() {
        shelf { defaults in
            defaults.set("blog.example", forKey: "server.host")
            let blog = BlogShelf.read(from: defaults).blogs[0]
            #expect(blog.port == 22)
            #expect(blog.maxMb == 24)
        }
    }

    @Test func blogsWrittenDownAreReadBack() {
        shelf { defaults in
            var one = Blog()
            one.host = "one.example"
            var two = Blog()
            two.host = "two.example"
            two.facts = Facts(posts: 92, since: "2026", words: 41319, readingHours: 3.4, tags: 14,
                              media: 33, mediaBytes: 31_600_000, trash: 10, trashBytes: 1_231_404, versions: 15, versionsBytes: 101_168)
            BlogShelf.write([one, two], current: two.id, to: defaults)

            let read = BlogShelf.read(from: defaults)
            #expect(read.blogs == [one, two])
            #expect(read.current == two.id)
            #expect(BlogShelf.current(from: defaults) == two)
            #expect(read.blogs[1].facts?.posts == 92)
        }
    }

    /// The order somebody put the blogs in is the order they are kept in,
    /// and which one is open does not change with it.
    @Test func blogsKeepTheOrderTheyWerePutIn() {
        shelf { defaults in
            var one = Blog(), two = Blog(), three = Blog()
            one.host = "one.example"
            two.host = "two.example"
            three.host = "three.example"
            var blogs = [one, two, three]
            // The last carried to the first place, as a held row is.
            blogs.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
            BlogShelf.write(blogs, current: two.id, to: defaults)

            let read = BlogShelf.read(from: defaults)
            #expect(read.blogs.map(\.host) == ["three.example", "one.example", "two.example"])
            #expect(read.current == two.id)
            #expect(BlogShelf.current(from: defaults) == two)
        }
    }

    /// A held row's "Up" and "Down": one place at a time, and nowhere
    /// past either end of the list.
    @Test func aBlogStepsUpAndDownTheListButNotOffIt() {
        var one = Blog(), two = Blog(), three = Blog()
        one.host = "one.example"
        two.host = "two.example"
        three.host = "three.example"
        let blogs = [one, two, three]

        #expect(BlogShelf.shifted(blogs, three.id, by: -1).map(\.host) == ["one.example", "three.example", "two.example"])
        #expect(BlogShelf.shifted(blogs, one.id, by: 1).map(\.host) == ["two.example", "one.example", "three.example"])
        #expect(BlogShelf.shifted(blogs, one.id, by: -1) == blogs)
        #expect(BlogShelf.shifted(blogs, three.id, by: 1) == blogs)
        #expect(BlogShelf.shifted(blogs, UUID(), by: 1) == blogs)
    }

    /// The blog that was open is gone from the list: the first one opens.
    @Test func anUnknownCurrentBlogFallsBackToTheFirst() {
        shelf { defaults in
            let one = Blog()
            BlogShelf.write([one], current: UUID(), to: defaults)
            #expect(BlogShelf.read(from: defaults).current == one.id)
        }
    }

    @Test func eachBlogHasAKeyAccountOfItsOwn() {
        let one = Blog(), two = Blog()
        #expect(one.keyAccount != two.keyAccount)
        #expect(one.keyAccount.hasPrefix("blog-"))
    }

    /// A blog written down by an earlier build, before a field existed, is
    /// still that blog.
    @Test func aBlogFromAnEarlierBuildIsStillRead() throws {
        let id = UUID()
        let json = #"[{"id":"\#(id.uuidString)","host":"blog.example","port":202,"user":"dan","path":"/app/data/blog","through":"","keyAccount":"ssh-ed25519"}]"#
        let blogs = try JSONDecoder().decode([Blog].self, from: Data(json.utf8))
        #expect(blogs.count == 1)
        #expect(blogs[0].id == id)
        #expect(blogs[0].name == "")
        #expect(blogs[0].claim == "")
        #expect(blogs[0].maxMb == 24)
        #expect(blogs[0].facts == nil)
        #expect(blogs[0].tonesLight == nil)
        #expect(blogs[0].tonesDark == nil)
    }

    /// A blog's palette is written down with it and read back as it was.
    @Test func aBlogKeepsItsPalette() throws {
        var blog = Blog()
        blog.tonesLight = Tones(bg: "#fff7eb", text: "#1e1d1c", metaText: "#6b6862", border: "#d7d0c6")
        blog.tonesDark = Tones(bg: "#000000", text: "#e6dccb", metaText: "#a1988a", border: "#3c3935")
        let back = try JSONDecoder().decode(Blog.self, from: JSONEncoder().encode(blog))
        #expect(back == blog)
    }

    /// What a blog is called in the list: its own name; before it has said
    /// one, its directory -- two blogs on one server share a host.
    @Test func aBlogIsCalledByItsNameThenItsDirectoryThenItsHost() {
        var blog = Blog()
        blog.host = "blog.example"
        #expect(blog.label == "blog.example")
        blog.path = "/app/data/blog.sh"
        #expect(blog.label == "blog.sh")
        blog.name = "./blog.sh"
        #expect(blog.label == "./blog.sh")
    }

    /// Where a blog is, under its name: with its port where the port is
    /// not ssh's usual one.
    @Test func whereABlogIsSaysItsPortWhenItIsNotTheUsualOne() {
        var blog = Blog()
        #expect(blog.place == "")
        blog.host = "blog.example"
        #expect(blog.place == "blog.example")
        blog.user = "me"
        #expect(blog.place == "me@blog.example")
        blog.port = 202
        #expect(blog.place == "me@blog.example:202")
        blog.host = "10.0.0.5"
        blog.port = 2222
        #expect(blog.place == "me@10.0.0.5:2222")
        blog.host = "fe80::1"
        #expect(blog.place == "me@[fe80::1]:2222")
        blog.port = 22
        #expect(blog.place == "me@fe80::1")
        // A port never set is the usual one.
        blog.host = "blog.example"
        blog.port = 0
        #expect(blog.place == "me@blog.example")
    }
}
