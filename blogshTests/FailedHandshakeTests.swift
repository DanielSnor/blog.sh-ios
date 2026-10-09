import Foundation
import CryptoKit
import NIOCore
import NIOPosix
import NIOSSH
import Testing
@testable import blogsh

/// An SSH server on this device's own loopback, standing in for sshd: it
/// goes through the handshake and then lets a key in or turns it away.
/// Like sshd, it does not hang up on a key it turned away -- the client
/// may try another -- so a connection the client does not close stays.
nonisolated final class LoopbackSSHD: @unchecked Sendable {
    nonisolated final class Auth: NIOSSHServerUserAuthenticationDelegate, Sendable {
        let lets: Bool
        init(lets: Bool) { self.lets = lets }
        var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { .publicKey }
        func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
            responsePromise.succeed(lets ? .success : .failure)
        }
    }

    private let lock = NSLock()
    private var accepted: [Channel] = []
    private var listener: Channel?

    /// The connections that were made to it, in the order they came.
    var connections: [Channel] { lock.withLock { accepted } }
    var port: Int { lock.withLock { listener?.localAddress?.port ?? 0 } }

    static func start(lettingIn: Bool) async throws -> LoopbackSSHD {
        let sshd = LoopbackSSHD()
        let hostKey = NIOSSHPrivateKey(ed25519Key: .init())
        let auth = Auth(lets: lettingIn)
        let listener = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { channel in
                sshd.lock.withLock { sshd.accepted.append(channel) }
                return channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSHHandler(role: .server(.init(hostKeys: [hostKey], userAuthDelegate: auth)),
                                      allocator: channel.allocator,
                                      inboundChildChannelInitializer: nil))
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        sshd.lock.withLock { sshd.listener = listener }
        return sshd
    }

    func stop() {
        let (listener, accepted) = lock.withLock { (self.listener, self.accepted) }
        for channel in accepted { channel.close(promise: nil) }
        listener?.close(promise: nil)
    }
}

/// A connection that did not get through the handshake. The app has no
/// use for it; the server should see it go at once, as it does when ssh
/// is turned away.
@Suite(.serialized) struct FailedHandshakeTests {
    private func until(seconds: Double, _ what: () -> Bool) async -> Bool {
        for _ in 0..<Int(seconds * 20) {
            if what() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return what()
    }

    /// The control: a connection the app does close is seen to go by the
    /// stand-in server, so the tests below do not fail for want of looking.
    @Test func aConnectionTheAppClosesIsSeenToGo() async throws {
        let sshd = try await LoopbackSSHD.start(lettingIn: true)
        defer { sshd.stop() }
        let account = "audit-\(UUID().uuidString.lowercased())"
        try KeyStore.makeKey(account: account)
        defer { try? KeyStore.deleteKey(account: account) }
        defer { TrustOnFirstUse.forget(host: "127.0.0.1", port: sshd.port) }
        let door = Door(host: "127.0.0.1", port: sshd.port, user: "nobody", keyAccount: account)

        let hold = try await Engine.line.take(door)
        await Engine.line.give(hold)
        try #require(sshd.connections.count == 1)
        await Engine.line.drop()
        #expect(await until(seconds: 5) { !sshd.connections[0].isActive })
    }

    /// The key's line is not in authorized_keys yet: every call ends in
    /// EngineError.keyNotKnown. Watched for twelve seconds, which is past
    /// the library's own ten-second login timer.
    @Test func aConnectionWhoseKeyWasTurnedAwayIsClosed() async throws {
        let sshd = try await LoopbackSSHD.start(lettingIn: false)
        defer { sshd.stop() }
        let account = "audit-\(UUID().uuidString.lowercased())"
        try KeyStore.makeKey(account: account)
        defer { try? KeyStore.deleteKey(account: account) }
        defer { TrustOnFirstUse.forget(host: "127.0.0.1", port: sshd.port) }
        let door = Door(host: "127.0.0.1", port: sshd.port, user: "nobody", keyAccount: account)

        do {
            let hold = try await Engine.line.take(door)
            await Engine.line.give(hold)
            Issue.record("the stand-in server let the key in")
        } catch EngineError.keyNotKnown {
            // What the scenario is about.
        }
        try #require(sshd.connections.count == 1)
        let gone = await until(seconds: 12) { !sshd.connections[0].isActive }
        #expect(gone, "twelve seconds after the call failed with keyNotKnown, its connection is still open on the server")
    }

    /// Five calls while the key is not known -- five taps on "Test the
    /// connection" -- and what the server holds open afterwards.
    @Test func fiveCallsTurnedAwayLeaveNothingOpen() async throws {
        let sshd = try await LoopbackSSHD.start(lettingIn: false)
        defer { sshd.stop() }
        let account = "audit-\(UUID().uuidString.lowercased())"
        try KeyStore.makeKey(account: account)
        defer { try? KeyStore.deleteKey(account: account) }
        defer { TrustOnFirstUse.forget(host: "127.0.0.1", port: sshd.port) }
        let door = Door(host: "127.0.0.1", port: sshd.port, user: "nobody", keyAccount: account)

        for _ in 0..<5 {
            do {
                let hold = try await Engine.line.take(door)
                await Engine.line.give(hold)
                Issue.record("the stand-in server let the key in")
            } catch EngineError.keyNotKnown {}
        }
        try #require(sshd.connections.count == 5)
        _ = await until(seconds: 3) { sshd.connections.allSatisfy { !$0.isActive } }
        let open = sshd.connections.filter(\.isActive).count
        #expect(open == 0, "connections still open on the server after five failed calls")
    }

    /// The server's key is not the one remembered: every call ends in
    /// EngineError.hostKeyChanged.
    @Test func aConnectionToAServerWhoseKeyChangedIsClosed() async throws {
        let sshd = try await LoopbackSSHD.start(lettingIn: true)
        defer { sshd.stop() }
        let account = "audit-\(UUID().uuidString.lowercased())"
        try KeyStore.makeKey(account: account)
        defer { try? KeyStore.deleteKey(account: account) }
        UserDefaults.standard.set("SHA256:the-key-before-the-reinstall", forKey: TrustOnFirstUse.defaultsKey(host: "127.0.0.1", port: sshd.port))
        defer { TrustOnFirstUse.forget(host: "127.0.0.1", port: sshd.port) }
        let door = Door(host: "127.0.0.1", port: sshd.port, user: "nobody", keyAccount: account)

        do {
            let hold = try await Engine.line.take(door)
            await Engine.line.give(hold)
            Issue.record("the changed key was taken")
        } catch EngineError.hostKeyChanged {
            // What the scenario is about.
        }
        try #require(sshd.connections.count == 1)
        let gone = await until(seconds: 5) { !sshd.connections[0].isActive }
        #expect(gone, "five seconds after the call failed with hostKeyChanged, its connection is still open on the server")
    }
}
