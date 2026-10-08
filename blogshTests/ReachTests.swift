import Foundation
import Testing
@testable import blogsh

/// Whether a blog is within reach: what the engine's calls said of its server.
@MainActor @Suite struct ReachTests {
    private func blog(_ host: String, port: Int = 22) -> Blog {
        var blog = Blog()
        blog.host = host
        blog.port = port
        blog.user = "dan"
        return blog
    }

    /// A server nobody answered at is silent until a call gets through again.
    @Test func aSilentServerIsOfflineUntilItIsHeardFrom() {
        let reach = Reach()
        let one = blog("one.example")
        #expect(!reach.isOffline(one))

        reach.nothing(from: Reach.server(host: "one.example", port: 22))
        #expect(reach.isOffline(one))

        reach.heard(from: Reach.server(host: "one.example", port: 22))
        #expect(!reach.isOffline(one))
    }

    /// The server is what is silent: two blogs behind one address share
    /// it, a blog elsewhere -- or on another port of the same host -- does not.
    @Test func blogsOnOneServerShareItsSilence() {
        let reach = Reach()
        reach.nothing(from: Reach.server(host: "one.example", port: 202))

        #expect(reach.isOffline(blog("one.example", port: 202)))
        #expect(reach.isOffline(blog(" One.Example ", port: 202)))
        #expect(!reach.isOffline(blog("one.example")))
        #expect(!reach.isOffline(blog("two.example", port: 202)))
        #expect(!reach.isOffline(nil))
    }

    /// A blog whose port was never written down is on ssh's own.
    @Test func noPortIsTheUsualOne() {
        #expect(Reach.server(host: "one.example", port: 0) == Reach.server(host: "one.example", port: 22))
    }

    /// What is said of a silent server names it, and is not the library's English.
    @Test func aSilentServerIsNamedInPlainWords() {
        let words = EngineError.unreachable("one.example", "NIOConnectionError(...)").localizedDescription
        #expect(words.contains("one.example"))
        #expect(!words.contains("NIOConnectionError"))
    }
}
