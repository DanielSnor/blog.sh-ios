import Foundation
import Citadel
import CryptoKit
import NIOCore
import NIOSSH

/// The code `./blog.sh pair` shows: where the blog is, which machine is
/// to answer there, and a key good once, for ten minutes, for one thing --
/// handing in the public half of a key this app made itself. It arrives
/// as a link, read by a camera or pasted as text:
///
///     blogsh://pair?v=1&h=<host>&p=<port>&u=<user>&k=<key>&f=<prints>&n=<site>
///
/// Nothing of it is kept but where the blog is: the key in it opens
/// nothing once it has been used.
nonisolated struct PairingCode: Equatable, Sendable {
    let host: String
    let port: Int
    let user: String
    /// The 32 bytes the one-time key is made of.
    let seed: Data
    /// The fingerprints of the server's own keys, as the code spells
    /// them; none where the code names none.
    let fingerprints: [String]
    /// What the blog calls itself, to ask "connect to …?" with.
    let site: String?

    enum Problem: Error, Equatable {
        /// Not a pairing code at all: another link, a sentence, nothing.
        case notACode
        /// A code of a kind this app does not know yet.
        case anotherVersion
        /// A pairing code with a part missing or unreadable.
        case incomplete
    }

    init(_ text: String) throws(Problem) {
        // Nothing the engine writes into a code is ever a space or a line
        // break: one found inside a pasted code was put there on the way
        // -- a mail that wraps, a note that breaks the line -- and is no
        // part of it.
        let link = String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
        guard let parts = URLComponents(string: link),
              parts.scheme?.lowercased() == "blogsh", parts.host?.lowercased() == "pair" else { throw .notACode }
        // The engine writes the parts the way a form is sent: a space is a
        // plus and a plus is %2B. Read as a plain link's would be, a blog
        // called "Můj blog" would be asked about as "Můj+blog".
        var said: [String: String] = [:]
        for item in parts.percentEncodedQueryItems ?? [] where said[item.name] == nil {
            let written = (item.value ?? "").replacingOccurrences(of: "+", with: "%20")
            said[item.name] = written.removingPercentEncoding ?? written
        }
        guard said["v"] == "1" else { throw said["v"] == nil ? .incomplete : .anotherVersion }
        guard let host = said["h"], !host.isEmpty,
              let user = said["u"], !user.isEmpty,
              let port = said["p"].flatMap(Int.init), (1...65_535).contains(port),
              let seed = said["k"].flatMap(Self.bytes), seed.count == 32 else { throw .incomplete }
        self.host = host
        self.port = port
        self.user = user
        self.seed = seed
        // A fingerprint is whole or it is not one: 43 characters, SHA-256
        // without its padding. A code cut off inside its last fingerprint
        // would otherwise be taken, and then turn its own server away as
        // another machine.
        let prints = (said["f"] ?? "").split(separator: ".").map(String.init)
        guard prints.allSatisfy({ $0.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil }) else { throw .incomplete }
        fingerprints = prints
        site = said["n"].flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }

    /// The server that answered is one the code told the app to expect --
    /// or the code named none, and the first one met is taken on trust,
    /// as with a blog set up by hand.
    func expects(_ fingerprint: String) -> Bool {
        fingerprints.isEmpty || fingerprints.contains(Self.urlSafe(fingerprint))
    }

    /// A fingerprint as the code spells it: without its "SHA256:", without
    /// padding, in the alphabet a link can carry.
    static func urlSafe(_ fingerprint: String) -> String {
        var print = fingerprint
        if print.hasPrefix("SHA256:") { print.removeFirst(7) }
        return print.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    /// The fingerprint of a key, as ssh prints it: SHA-256 over the key as
    /// it goes over the wire.
    static func fingerprint(ofKey blob: Data) -> String {
        "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    private static func bytes(_ urlSafe: String) -> Data? {
        var standard = urlSafe.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while standard.count % 4 != 0 { standard.append("=") }
        return Data(base64Encoded: standard)
    }
}

/// What went wrong on the way in, as far as it can be told apart -- each
/// is a different thing to say to somebody holding a phone.
nonisolated enum PairingError: Error, Equatable {
    /// The code is spent: too old, or used already. The engine said so,
    /// or the server would not even take its key.
    case spent
    /// Another machine answered than the one the code describes.
    case wrongServer
    /// Nobody answered there. What the network said of it is kept for
    /// whoever reads a log, not shown: it is the library's own English.
    case unreachable(String)
    /// The engine said no for a reason of its own; its sentence.
    case refused(String)
    /// The app could not make or read its own key.
    case noKey

    /// The engine's answer to `enroll`, read: the device's name as the
    /// blog wrote it down, or what it said no with.
    static func device(from answer: Data) throws(PairingError) -> String {
        struct Answer: Decodable {
            let ok: Bool
            let device: String?
            let error: String?
            let message: String?
        }
        guard let said = try? JSONDecoder().decode(Answer.self, from: answer) else {
            let words = String(decoding: answer.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw .refused(words)
        }
        if said.ok { return said.device ?? "" }
        switch said.error {
        case "expired", "used", "unknown_code": throw .spent
        default: throw .refused(said.message ?? said.error ?? "")
        }
    }
}

/// The exchange itself: connect with the code's key, make sure the right
/// machine answered, hand in the app's own public key. One connection of
/// its own, closed when it is over -- nothing of it is kept.
nonisolated enum Pairing {
    /// Returns the device's name as the blog wrote it down, and the
    /// fingerprint of the server that answered.
    @concurrent static func handIn(_ publicKey: String, named name: String, with code: PairingCode) async throws(PairingError) -> (device: String, server: String) {
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: code.seed) else { throw .spent }
        let trust = Trust(code: code)
        let client: SSHClient
        do {
            client = try await SSHClient.connect(
                host: code.host,
                port: code.port,
                authenticationMethod: .ed25519(username: code.user, privateKey: key),
                hostKeyValidator: .custom(trust),
                reconnect: .never,
                // Somebody is standing there holding a phone: an address
                // nobody answers on is given up after ten seconds, not thirty.
                connectTimeout: .seconds(10)
            )
        } catch let error as PairingError {
            throw error
        } catch SSHClientError.allAuthenticationOptionsFailed {
            // The server no longer takes the code's key: its line is gone.
            throw .spent
        } catch {
            // The check of the server's key fails the connection from inside.
            if trust.refused { throw .wrongServer }
            throw .unreachable("\(error)")
        }
        var request = Data()
        if let line = try? JSONSerialization.data(withJSONObject: ["key": publicKey, "name": name]) { request = line }
        request.append(0x0a)
        var answer = Data()
        var done = false
        do {
            let line = request
            try await client.withExec("enroll") { inbound, outbound in
                try await outbound.write(ByteBuffer(bytes: line))
                for try await chunk in inbound {
                    if case .stdout(let buffer) = chunk { answer.append(contentsOf: buffer.readableBytesView) }
                }
                done = true
            }
        } catch {
            // The answer may be whole even when the close after it complains.
            if !(done && !answer.isEmpty) {
                try? await client.close()
                throw .unreachable("\(error)")
            }
        }
        try? await client.close()
        return (try PairingError.device(from: answer), trust.seen)
    }

    /// The server's key, checked against the code before anything is said
    /// to the server, and remembered for the blog's later connections.
    private final class Trust: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
        let code: PairingCode
        private let lock = NSLock()
        private var print = ""
        private var turnedAway = false

        init(code: PairingCode) { self.code = code }

        var seen: String { lock.withLock { print } }
        var refused: Bool { lock.withLock { turnedAway } }

        func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
            var buffer = ByteBufferAllocator().buffer(capacity: 512)
            _ = hostKey.write(to: &buffer)
            let fingerprint = PairingCode.fingerprint(ofKey: Data(buffer.readableBytesView))
            if code.expects(fingerprint) {
                lock.withLock { print = fingerprint }
                validationCompletePromise.succeed(())
            } else {
                lock.withLock { turnedAway = true }
                validationCompletePromise.fail(PairingError.wrongServer)
            }
        }
    }
}
