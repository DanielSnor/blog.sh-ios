import CoreGraphics
import Foundation
import ImageIO
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

/// A picture taken from the device's files instead of the photo library,
/// and the ground the app is read on. A mistake here is a file that
/// cannot be added, or a setting that comes back as another.
@Suite struct FilesAndDaylightTests {
    private func picture(_ width: Int, _ height: Int) throws -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0.4, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(ctx.makeImage())
        let out = NSMutableData()
        let sink = try #require(CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(sink, image, nil)
        #expect(CGImageDestinationFinalize(sink))
        return out as Data
    }

    /// A file is read as a picked photograph is -- shrunk, written as
    /// JPEG -- and is called by the name it has in its folder.
    @Test func aPictureFromAFileIsCalledByItsOwnName() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Snímek obrazovky 2026.PNG")
        try picture(4000, 1000).write(to: file)

        let shot = try await Media.shot(fromFile: file, index: 1, taken: [])
        #expect(shot.name == "snimek-obrazovky-2026.jpg")
        #expect(shot.width == Pictures.maxEdge)
        #expect(shot.height == Pictures.maxEdge / 4)
        #expect(shot.thumb != nil)
        // A second one of the same name gets a number, as two photographs do.
        let again = try await Media.shot(fromFile: file, index: 2, taken: [shot.name])
        #expect(again.name == "snimek-obrazovky-2026-2.jpg")
    }

    /// What is no picture, or is not there, is said to be unreadable.
    @Test func aFileThatIsNoPictureIsNotAdded() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("notes.jpg")
        try Data("not a picture".utf8).write(to: note)
        await #expect(throws: Media.Unread.self) { try await Media.shot(fromFile: note, index: 1, taken: []) }
        await #expect(throws: Media.Unread.self) { try await Media.shot(fromFile: folder.appendingPathComponent("gone.jpg"), index: 1, taken: []) }
    }

    /// The ground chosen in the settings comes back as it was kept, and
    /// anything else that was kept is the system's own way.
    @Test func theChosenGroundIsReadBackAsItWasKept() {
        #expect(DayNight.allCases == [.system, .day, .night])
        #expect(DayNight(kept: DayNight.day.rawValue) == .day)
        #expect(DayNight(kept: DayNight.night.rawValue) == .night)
        #expect(DayNight(kept: 0) == .system)
        #expect(DayNight(kept: 7) == .system)
        #expect(DayNight(kept: -1) == .system)
    }
}
