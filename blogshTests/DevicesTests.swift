import Foundation
import Testing
@testable import blogsh

/// The devices a code let in, as the blog lists them through its door,
/// and what the app makes of who is asking.
@Suite struct DevicesTests {
    private let phone = "SHA256:la6QSKoLVR1OyiPKsCYMqieZSBecBuurCBCGPv6Fals"
    private let tablet = "SHA256:ysUXkFzgUqoqTPIe2meJVL9qcNx4GcU/usa/kLQPlPY"

    private func refusal(_ code: String, _ message: String? = nil) -> EngineError {
        .refused(Refusal(ok: false, error: code, message: message))
    }

    @Test func theListIsRead() throws {
        let data = Data(#"{"ok":true,"devices":[{"name":"Danielův iPhone","fingerprint":"\#(phone)","self":true},{"name":"Tablet","fingerprint":"\#(tablet)","self":false}],"self":"\#(phone)"}"#.utf8)
        let answer: PairedDevices = try Engine.decode(data)
        #expect(answer.devices.map(\.name) == ["Danielův iPhone", "Tablet"])
        #expect(answer.devices.map(\.own) == [true, false])
        #expect(answer.own == phone)
        #expect(answer.mayLeave)
        #expect(answer.revoked == nil)
    }

    /// After the device was taken off, the blog names it and lists who
    /// is left; nobody is asking any more.
    @Test func theTakingOffIsRead() throws {
        let data = Data(#"{"ok":true,"revoked":{"name":"Danielův iPhone","fingerprint":"\#(phone)"},"devices":[{"name":"Tablet","fingerprint":"\#(tablet)","self":false}],"self":null}"#.utf8)
        let answer: PairedDevices = try Engine.decode(data)
        #expect(answer.revoked?.name == "Danielův iPhone")
        #expect(answer.devices.count == 1)
        #expect(!answer.mayLeave)
    }

    /// A blog reached by a line written by hand: no devices, nobody known.
    @Test func aBlogWithNoneIsRead() throws {
        let answer: PairedDevices = try Engine.decode(Data(#"{"ok":true,"devices":[],"self":null}"#.utf8))
        #expect(answer.devices.isEmpty)
        #expect(!answer.mayLeave)
        #expect(!answer.holdsThis(key: phone))
    }

    /// An older pairing's line does not say whose it is: the blog cannot
    /// tell who asks, the app still knows its own key in the list -- and
    /// does not offer what the blog would say no to.
    @Test func thisDeviceIsKnownByItsKeyWhereTheBlogCannotTell() throws {
        let data = Data(#"{"ok":true,"devices":[{"name":"iPhone","fingerprint":"\#(phone)","self":false},{"name":"Tablet","fingerprint":"\#(tablet)","self":false}],"self":null}"#.utf8)
        let answer: PairedDevices = try Engine.decode(data)
        #expect(answer.isThis(answer.devices[0], key: phone))
        #expect(!answer.isThis(answer.devices[1], key: phone))
        #expect(answer.holdsThis(key: phone))
        #expect(!answer.holdsThis(key: nil))
        #expect(!answer.mayLeave)
    }

    /// A line whose key was damaged by hand carries no fingerprint, and
    /// is nobody's by that.
    @Test func aLineWithNoKeyIsNobodys() {
        let broken = PairedDevices.Device(name: "?", fingerprint: "")
        let answer = PairedDevices(ok: true, devices: [broken], own: nil, revoked: nil)
        #expect(!answer.isThis(broken, key: ""))
        #expect(!answer.isThis(broken, key: nil))
    }

    @Test func anOlderBlogIsToldApart() {
        #expect(PairedDevices.notKnownThere(refusal("unknown_command", "pair is not a command here")))
        #expect(!PairedDevices.notKnownThere(refusal("device_unknown")))
        #expect(!PairedDevices.notKnownThere(EngineError.keyNotKnown(paired: true)))
    }

    /// The answer to the taking off was lost, the app asked again, and
    /// the server no longer knew the key: that is the taking off.
    @Test func aKeyNoLongerKnownIsTheDeviceGone() {
        #expect(PairedDevices.isGone(after: EngineError.keyNotKnown(paired: true)))
        #expect(!PairedDevices.isGone(after: refusal("busy")))
        #expect(!PairedDevices.isGone(after: EngineError.unreachable("blog.example", "timeout")))
    }

    /// The key file held by another run is said in the blog's words, not
    /// in the app's sentence about a build and a save.
    @Test func aHeldKeyFileIsSaidInTheBlogsWords() {
        let said = "Soubor s klíči zrovna mění někdo jiný, takže se nic neodebralo. Za chvíli to zkus znovu."
        #expect(PairedDevices.words(for: refusal("busy", said)) == said)
        #expect(PairedDevices.words(for: refusal("busy")) == Refusal.held)
        #expect(PairedDevices.words(for: refusal("write_failed", "could not be written")) == "could not be written")
    }

    /// Taking off waits its turn at the key file; looking does not. Both
    /// are asked in the language the app speaks.
    @Test func theDoorIsAskedAsItExpects() {
        #expect(Engine.waitsItsTurn(["pair", "--revoke"]))
        #expect(!Engine.waitsItsTurn(["pair", "--list"]))
        #expect(Engine.request(["pair", "--list"], lang: "cs")["lang"] as? String == "cs")
        #expect(Engine.request(["pair", "--revoke"], lang: "de")["lang"] as? String == "de")
        #expect(!Engine.changesTheBlog(["pair", "--revoke"]))
    }
}
