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

/// Why a chosen picture could not be read: said as what it most likely is.
@Suite struct UnreadTests {
    /// The library saying it needs the network is that, whatever the device thinks of its own.
    @Test func theLibrarysOwnWordForTheNetworkIsBelieved() {
        let needs = NSError(domain: "PHPhotosErrorDomain", code: 3164)
        #expect(Media.unread(needs, online: true) == .needsNetwork)
        let wrapped = NSError(domain: "CoreTransferable", code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: "PHPhotosErrorDomain", code: 3169)])
        #expect(Media.unread(wrapped, online: true) == .needsNetwork)
        #expect(Media.unread(NSError(domain: NSURLErrorDomain, code: -1009), online: true) == .needsNetwork)
    }

    /// Any failure on a device with no network is most likely the same thing;
    /// with a network, it is a picture that could not be read and no more.
    @Test func withoutANetworkAFailureIsTakenForIt() {
        let other = NSError(domain: "PHPhotosErrorDomain", code: 3302)
        #expect(Media.unread(other, online: false) == .needsNetwork)
        #expect(Media.unread(nil, online: false) == .needsNetwork)
        #expect(Media.unread(other, online: true) == .unreadable)
        #expect(Media.unread(nil, online: true) == .unreadable)
        #expect(Media.Unread.needsNetwork.words != Media.Unread.unreadable.words)
    }

    /// A silent server is asked again after five seconds, then at twice
    /// the wait each time, and never left alone for more than a minute.
    @Test func aSilentServerIsAskedAgainAtLongerAndLongerWaits() {
        #expect((0...6).map { Reach.pause(after: $0) } == [.seconds(5), .seconds(10), .seconds(20), .seconds(40), .seconds(60), .seconds(60), .seconds(60)])
        #expect(Reach.pause(after: -1) == .seconds(5))
        #expect(Reach.pause(after: 1_000) == .seconds(60))
    }
}
