import Foundation
import Citadel
import CryptoKit
import NIOCore
import NIOSSH

/// What the engine said no to, or what went wrong on the way to it.
nonisolated enum EngineError: Error, LocalizedError {
    case notConfigured
    case noKey
    case hostKeyChanged(String)
    case refused(Refusal)
    case unreadable(String)
    /// Where on the way to the engine it broke, for the message that says so.
    case stage(String, Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: String(localized: "The server is not set up yet.")
        case .noKey: String(localized: "The app has no key yet.")
        case .hostKeyChanged(let fingerprint):
            String(localized: "The server's key changed (\(fingerprint)). If the server was reinstalled, forget the old key in Settings.")
        case .refused(let refusal): refusal.message
        case .unreadable(let text): String(localized: "The engine did not answer as data: \(text)")
        case .stage(let stage, let error): "\(stage): \(error)"
        }
    }
}

/// One engine command, run on the server through the app's key and the
/// forced command there (scripts/remote.sh, `run`): the argv goes over as
/// one line of JSON, the answer comes back as one object. Nothing here is
/// a shell; the server checks every word before the engine sees it.
actor Engine {
    static let shared = Engine()

    /// Runs `./blog.sh <args>` and decodes its answer, or throws the
    /// refusal the engine gave -- which is an answer too, just a no.
    nonisolated func call<T: Decodable>(_ args: [String], as type: T.Type = T.self) async throws -> T {
        let data = try await run(args)
        // A call the screen called off ends its read early, with nothing: that
        // is not an answer, and not a failure anybody is waiting to hear about.
        try Task.checkCancellation()
        guard !data.isEmpty else {
            throw EngineError.unreadable(String(localized: "The server closed the connection without an answer."))
        }
        let decoder = JSONDecoder()
        if let refusal = try? decoder.decode(Refusal.self, from: data), refusal.ok == false {
            throw EngineError.refused(refusal)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let text = String(decoding: data.prefix(300), as: UTF8.self)
            throw EngineError.unreadable(text.isEmpty ? "\(error)" : text)
        }
    }

    // Nothing here touches the actor: the client lives and dies inside one
    // call. @concurrent, because Citadel runs its methods on the global
    // executor and the client is not Sendable -- so it is made and used
    // there, never handed across an isolation boundary.
    @concurrent nonisolated func run(_ args: [String]) async throws -> Data {
        guard let settings = ServerSettings.load() else { throw EngineError.notConfigured }
        let key: Curve25519.Signing.PrivateKey
        do {
            key = try KeyStore.privateKey()
        } catch {
            throw EngineError.noKey
        }
        let client: SSHClient
        do {
            client = try await SSHClient.connect(
                host: settings.host,
                port: settings.port,
                authenticationMethod: .ed25519(username: settings.user, privateKey: key),
                hostKeyValidator: .custom(TrustOnFirstUse(host: settings.host, port: settings.port)),
                reconnect: .never
            )
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError.stage("connect", error)
        }
        // Closed on both ways out, in line rather than from a detached task:
        // a task spawned here would carry the client across the actor's
        // boundary, and the compiler is right to refuse that.
        do {
            let answer = try await Self.exec(args, on: client)
            try? await client.close()
            return answer
        } catch {
            try? await client.close()
            throw error
        }
    }

    /// A delivery: the files, pictures first and the markdown last, in the
    /// receiver's frame (a name, its base64, a line with a dot), ended by a
    /// line saying `end` -- scripts/remote.sh's `deliver`. One answer per
    /// file comes back; the last is the engine's own for the markdown.
    @concurrent nonisolated func deliver(_ files: [DeliveryFile]) async throws -> [Data] {
        guard let settings = ServerSettings.load() else { throw EngineError.notConfigured }
        let key: Curve25519.Signing.PrivateKey
        do {
            key = try KeyStore.privateKey()
        } catch {
            throw EngineError.noKey
        }
        let client: SSHClient
        do {
            client = try await SSHClient.connect(
                host: settings.host,
                port: settings.port,
                authenticationMethod: .ed25519(username: settings.user, privateKey: key),
                hostKeyValidator: .custom(TrustOnFirstUse(host: settings.host, port: settings.port)),
                reconnect: .never
            )
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError.stage("connect", error)
        }
        do {
            let answers = try await Self.send(files, on: client)
            try? await client.close()
            return answers
        } catch {
            try? await client.close()
            throw error
        }
    }

    @concurrent private static func send(_ files: [DeliveryFile], on client: SSHClient) async throws -> [Data] {
        var output = Data()
        var stage = "exec"
        do {
            try await client.withExec("deliver") { inbound, outbound in
                stage = "write"
                for file in files {
                    try await outbound.write(ByteBuffer(string: file.name + "\n"))
                    // 76 columns and a newline, the way base64 is written on
                    // a wire; the receiver strips the breaks before decoding.
                    let encoded = file.data.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
                    try await outbound.write(ByteBuffer(string: encoded + "\n.\n"))
                }
                try await outbound.write(ByteBuffer(string: "end\n"))
                stage = "read"
                for try await chunk in inbound {
                    if case .stdout(let buffer) = chunk {
                        output.append(contentsOf: buffer.readableBytesView)
                    }
                }
                stage = "close"
            }
        } catch {
            if stage == "close", !output.isEmpty { return Self.objects(in: output) }
            throw EngineError.stage("\(stage) (\(output.count) bytes so far)", error)
        }
        return Self.objects(in: output)
    }

    /// The answers as they came: one-line receipts for the pictures, the
    /// engine's pretty-printed object for the markdown. Split where a line
    /// opens a new object, each piece checked to be one.
    nonisolated static func objects(in output: Data) -> [Data] {
        var found: [Data] = []
        var current = Data()
        for line in output.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
            if line.first == UInt8(ascii: "{"), !current.isEmpty, (try? JSONSerialization.jsonObject(with: current)) != nil {
                found.append(current)
                current = Data()
            }
            current.append(contentsOf: line)
            current.append(UInt8(ascii: "\n"))
        }
        if (try? JSONSerialization.jsonObject(with: current)) != nil { found.append(current) }
        return found
    }

    @concurrent private static func exec(_ args: [String], on client: SSHClient) async throws -> Data {
        var request = try JSONSerialization.data(withJSONObject: ["args": args])
        request.append(0x0a)
        var answer = Data()
        var stage = "exec"
        do {
            try await client.withExec("run") { inbound, outbound in
                stage = "write"
                try await outbound.write(ByteBuffer(bytes: request))
                stage = "read"
                for try await chunk in inbound {
                    if case .stdout(let buffer) = chunk {
                        answer.append(contentsOf: buffer.readableBytesView)
                    }
                }
                stage = "close"
            }
        } catch {
            // The answer may be whole even when the close after it complains.
            if stage == "close", !answer.isEmpty { return answer }
            throw EngineError.stage("\(stage) (\(answer.count) bytes so far)", error)
        }
        return answer
    }
}

/// One file of a delivery: a bare name and its bytes.
nonisolated struct DeliveryFile: Sendable {
    let name: String
    let data: Data
}

/// The server's key is remembered the first time it is seen and has to be
/// the same every time after -- what ssh itself does with known_hosts.
nonisolated final class TrustOnFirstUse: NIOSSHClientServerAuthenticationDelegate, Sendable {
    let host: String
    let port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    static func defaultsKey(host: String, port: Int) -> String { "hostkey.\(host):\(port)" }

    static func forget(host: String, port: Int) {
        UserDefaults.standard.removeObject(forKey: defaultsKey(host: host, port: port))
    }

    static func known(host: String, port: Int) -> String? {
        UserDefaults.standard.string(forKey: defaultsKey(host: host, port: port))
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        var buffer = ByteBufferAllocator().buffer(capacity: 512)
        _ = hostKey.write(to: &buffer)
        let digest = SHA256.hash(data: Data(buffer.readableBytesView))
        let fingerprint = "SHA256:" + Data(digest).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        let key = Self.defaultsKey(host: host, port: port)
        if let known = UserDefaults.standard.string(forKey: key) {
            if known == fingerprint {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(EngineError.hostKeyChanged(fingerprint))
            }
        } else {
            UserDefaults.standard.set(fingerprint, forKey: key)
            validationCompletePromise.succeed(())
        }
    }
}

extension Error {
    /// A call the screen itself called off -- it went away, or asked again.
    /// Nobody is left to tell, so a screen keeps what it was saying.
    var isCalledOff: Bool { self is CancellationError }
}
