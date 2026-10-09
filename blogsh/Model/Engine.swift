import Foundation
import os
import Citadel
import CryptoKit
import NIOCore
import NIOPosix
import NIOSSH

/// What the engine said no to, or what went wrong on the way to it.
nonisolated enum EngineError: Error, LocalizedError {
    case notConfigured
    case noKey
    /// The server let the connection in and turned the key away: its
    /// account has no line for it.
    case keyNotKnown
    case hostKeyChanged(String)
    case refused(Refusal)
    case unreadable(String)
    /// Nobody answered at the server's address. What the network said of
    /// it is kept for whoever reads a log, not shown: it is the library's
    /// own English.
    case unreachable(String, String)
    /// Where on the way to the engine it broke, for the message that says so.
    case stage(String, Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: String(localized: "The server is not set up yet.")
        case .noKey: String(localized: "The app has no key yet.")
        case .keyNotKnown:
            String(localized: "The server does not know this blog's key. The line under the key in the blog's settings belongs in ~/.ssh/authorized_keys on the server.")
        case .hostKeyChanged(let fingerprint):
            String(localized: "The server's key changed (\(fingerprint)). If the server was reinstalled, forget the old key in the blog's settings.")
        // The engine's own sentence here speaks of --yes and of a screen the
        // terminal has; on a phone neither is anything one can do.
        case .refused(let refusal) where refusal.error == "ambiguous_slug":
            String(localized: "Two posts in different years share this slug, and the app cannot say which of them is meant. At the desk, ./blog.sh props asks which.")
        case .refused(let refusal): refusal.message
        case .unreadable(let text): String(localized: "The engine did not answer as data: \(text)")
        case .unreachable(let server, _):
            String(localized: "The server \(server) did not answer. Is this device on a network the server can be reached from?")
        case .stage(let stage, let error): "\(stage): \(error)"
        }
    }
}

/// One engine command, run on the server through the app's key and the
/// forced command there (scripts/remote.sh, `run`): the argv goes over as
/// one line of JSON, the answer comes back as one object. Nothing here is
/// a shell; the server checks every word before the engine sees it.
///
/// Every command is a channel of its own on one connection, which is kept
/// between them (`Line`) rather than opened for each.
actor Engine {
    static let shared = Engine()

    /// Runs `./blog.sh <args>` and decodes its answer, or throws the
    /// refusal the engine gave -- which is an answer too, just a no.
    ///
    /// The call is seen through whatever becomes of the task that asked: a
    /// screen the system builds, drops and builds again on its way in (a
    /// split view collapsing does exactly that) would otherwise call its
    /// own first read off half way, and be left showing nothing -- which
    /// reads as "there is nothing". A connection is short; its answer is
    /// simply not used when nobody is left to use it.
    nonisolated func call<T: Decodable & Sendable>(_ args: [String], as type: T.Type = T.self) async throws -> T {
        try await Task { try Self.decode(try await self.run(args), as: type) }.value
    }

    /// Several commands over one connection (`batch`), seen through the same way.
    nonisolated func answers(to commands: [[String]]) async throws -> [Data] {
        try await Task { try await self.batch(commands) }.value
    }

    /// One answer of a batch, read as `call` reads its own.
    nonisolated static func decode<T: Decodable>(_ data: Data, as type: T.Type = T.self) throws -> T {
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

    // Nothing here touches the actor. @concurrent, because Citadel runs
    // its methods on the global executor.
    @concurrent nonisolated func run(_ args: [String]) async throws -> Data {
        try await batch([args])[0]
    }

    /// Several commands over ONE connection, one after another, an answer
    /// for each. A screen that needs three things asks for them here: a
    /// connection is the expensive part -- a handshake each -- and a
    /// server that counts connections (a firewall's rate limit does) turns
    /// the fourth one away. A command that fails ends the batch; what was
    /// answered before it is lost with it.
    @concurrent nonisolated func batch(_ commands: [[String]]) async throws -> [Data] {
        try await Self.onTheLine { wire, wary in
            var answers: [Data] = []
            for args in commands {
                // Only the first can find the connection dead without
                // having said anything; after it, the connection has just
                // been heard from.
                answers.append(try await Self.exec(args, on: wire, wary: wary && answers.isEmpty, said: !answers.isEmpty))
            }
            return answers
        }
        .told(commands.contains(where: Self.changesTheBlog))
    }

    /// A delivery: the files, pictures first and the markdown last, in the
    /// receiver's frame (a name, its base64, a line with a dot), ended by a
    /// line saying `end` -- scripts/remote.sh's `deliver`. One answer per
    /// file comes back; the last is the engine's own for the markdown.
    ///
    /// `blog`: whose delivery it is, where it was not written just now on
    /// the open blog's own form. With another blog open by the time it
    /// goes, it does not go.
    @concurrent nonisolated func deliver(_ files: [DeliveryFile], to blog: UUID? = nil) async throws -> [Data] {
        try await Self.onTheLine(only: blog) { wire, wary in
            try await Self.send(files, on: wire, wary: wary)
        }
        .told(true)
    }

    // MARK: - The connection

    /// A connection, to be kept by the line: not Sendable by its own
    /// account, and used only through its own methods, which take
    /// themselves to its event loop.
    ///
    /// It lives on a thread of its own, `Strand`: taken down with it, a
    /// connection is gone whatever state it was left in.
    final class Wired: @unchecked Sendable {
        let client: SSHClient
        private let strand: Strand

        init(_ client: SSHClient, on strand: Strand) {
            self.client = client
            self.strand = strand
        }

        /// Closed in order, and then for certain.
        func close() async {
            try? await client.close()
            await strand.end()
        }
    }

    /// The thread one connection lives on, and nothing else does. The SSH
    /// library opens a connection and, when the handshake on it fails --
    /// the key is not known to the server, the server's key has changed
    /// -- hands back the error and keeps the socket: nobody is given
    /// anything to close it by, and the server holds the half-open
    /// connection until its own patience runs out. A server that counts
    /// the connections of an address counts those. Ending the thread
    /// closes whatever was opened on it.
    final class Strand: Sendable {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        func end() async {
            try? await group.shutdownGracefully()
        }
    }

    /// Kept for five minutes after its last call: somebody reading through
    /// the app asks the server every few seconds, and a server that counts
    /// connections stops answering the tenth. See `Line`.
    static let line = Line<Wired>(keep: 300,
                                  open: { door in
                                      let wire = try await connect(door)
                                      log.info("connection opened")
                                      return wire
                                  },
                                  close: {
                                      await $0.close()
                                      log.info("connection closed")
                                  })

    /// The connection's comings and goings, for whoever reads the device's log.
    private static let log = Logger(subsystem: "app.blogsh.ios", category: "line")

    /// Lets go of the kept connection: the app left the screen, or what a
    /// connection is opened with was changed.
    nonisolated static func hangUp() {
        Task { await line.drop() }
    }

    /// The connection failed before the call had said anything on it, so
    /// nothing was done on the server and the call can be made again.
    private struct NothingSaid: Error {
        let reason: Error
    }

    /// Runs `work` on the kept connection, opening one where none is kept.
    /// A kept connection can be dead without anybody knowing -- the network
    /// changed under it, a router forgot it: if it fails before the call
    /// said anything, the call is made once more on a new one. A call that
    /// had begun to speak is never repeated; whether a publish arrived is
    /// not something to guess at.
    @concurrent private static func onTheLine<T: Sendable>(only blog: UUID? = nil, _ work: @Sendable (Wired, _ wary: Bool) async throws -> T) async throws -> T {
        guard let settings = ServerSettings.load(only: blog) else {
            if blog != nil { throw CancellationError() }
            throw EngineError.notConfigured
        }
        let door = Door(host: settings.host, port: settings.port, user: settings.user, keyAccount: settings.keyAccount)
        // What became of the call is said to whoever shows the blog as
        // within reach or not: a server nobody answered at is silent
        // until a call gets through to it again.
        let server = Reach.server(host: door.host, port: door.port)
        var again = true
        while true {
            let hold: Line<Wired>.Hold
            do {
                hold = try await line.take(door)
            } catch {
                if case EngineError.unreachable = error { await Reach.shared.nothing(from: server) }
                throw error
            }
            do {
                let result = try await work(hold.wire, hold.rested)
                await line.give(hold)
                await Reach.shared.heard(from: server)
                return result
            } catch let nothing as NothingSaid {
                await line.give(hold, broken: true)
                guard again else { throw EngineError.stage("exec (0 bytes so far)", nothing.reason) }
                again = false
            } catch {
                // Whatever broke, this is not a connection to hand on --
                // except where the engine itself answered and the close
                // after it complained, which never comes here.
                await line.give(hold, broken: true)
                throw error
            }
        }
    }

    @concurrent private static func connect(_ door: Door) async throws -> Wired {
        let key: Curve25519.Signing.PrivateKey
        do {
            key = try KeyStore.privateKey(account: door.keyAccount)
        } catch {
            throw EngineError.noKey
        }
        let strand = Strand()
        do {
            let client = try await SSHClient.connect(
                host: door.host,
                port: door.port,
                authenticationMethod: .ed25519(username: door.user, privateKey: key),
                hostKeyValidator: .custom(TrustOnFirstUse(host: door.host, port: door.port)),
                reconnect: .never,
                group: strand.group,
                // An address nobody answers on is given up after ten
                // seconds, not thirty: somebody is waiting for the screen.
                connectTimeout: .seconds(10)
            )
            return Wired(client, on: strand)
        } catch {
            // Whatever was opened on the way is closed with its thread:
            // a connection that got as far as the handshake and no
            // further is otherwise left open on the server.
            await strand.end()
            if let error = error as? EngineError { throw error }
            if case SSHClientError.allAuthenticationOptionsFailed = error { throw EngineError.keyNotKnown }
            log.info("no connection: \(String(describing: error), privacy: .public)")
            throw EngineError.unreachable(door.host, "\(error)")
        }
    }

    /// Watches a call's first step on a connection that has lain unused:
    /// one that has not let the call in after ten seconds is closed, which
    /// ends the wait -- and the call is made again on a new one.
    private final class Watch: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private var task: Task<Void, Never>?

        init(_ wire: Wired, wary: Bool) {
            guard wary else { return }
            task = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, !self.isIn else { return }
                try? await wire.client.close()
            }
        }

        var isIn: Bool { lock.withLock { done } }

        /// The call was let in: the connection lives.
        func letIn() {
            lock.withLock { done = true }
            task?.cancel()
        }
    }

    @concurrent private static func send(_ files: [DeliveryFile], on wire: Wired, wary: Bool) async throws -> [Data] {
        var output = Data()
        var stage = "exec"
        let watch = Watch(wire, wary: wary)
        do {
            try await wire.client.withExec("deliver") { inbound, outbound in
                watch.letIn()
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
            watch.letIn()
            if stage == "close", !output.isEmpty { return Self.objects(in: output) }
            if stage == "exec" { throw NothingSaid(reason: error) }
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

    /// The request as the forced command reads it: the argv, and -- for
    /// the two commands that answer in sentences, `check` and `doctor` --
    /// the language the app speaks. An engine that has it says its
    /// findings in it; one that has not, or an older one, which reads the
    /// argv and nothing else, says them in the blog's own.
    nonisolated static func request(_ args: [String], lang: String? = Bundle.main.preferredLocalizations.first) -> [String: Any] {
        var request: [String: Any] = ["args": args]
        if ["check", "doctor"].contains(args.first ?? ""), let lang,
           lang.range(of: "^[a-z]{2,3}$", options: .regularExpression) != nil {
            request["lang"] = lang
        }
        return request
    }

    /// The command changes what the first screen says of the blog: its
    /// drafts, its queue, what the trash and the versions hold.
    nonisolated static func changesTheBlog(_ args: [String]) -> Bool {
        switch args.first ?? "" {
        case "publish", "unpublish", "delete", "restore", "schedule": true
        case "queue": args.count > 1
        case "props": args.contains { ["--set", "--rename", "--drop-address", "--restore-version"].contains($0) }
        case "empty": args.contains("--yes")
        default: false
        }
    }

    /// `said`: an earlier command of the same batch has already run on
    /// this connection, so a failure here is not one to start over from.
    @concurrent private static func exec(_ args: [String], on wire: Wired, wary: Bool, said: Bool) async throws -> Data {
        var request = try JSONSerialization.data(withJSONObject: Self.request(args))
        request.append(0x0a)
        var answer = Data()
        var stage = "exec"
        let watch = Watch(wire, wary: wary)
        do {
            try await wire.client.withExec("run") { inbound, outbound in
                watch.letIn()
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
            watch.letIn()
            // The answer may be whole even when the close after it complains.
            if stage == "close", !answer.isEmpty { return answer }
            if stage == "exec", !said { throw NothingSaid(reason: error) }
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

nonisolated extension Array where Element == Data {
    /// The answers, handed on -- after the desk was told that the blog
    /// has changed, where it has: the first screen reads its cards again.
    func told(_ changed: Bool) async -> [Data] {
        if changed { await Desk.shared.wrote() }
        return self
    }
}

extension Engine {
    /// A delivery's answers, read: the engine's own for the markdown, which
    /// is the last -- or the first no among them, thrown.
    nonisolated static func made(from answers: [Data]) throws -> ActionAnswer {
        let decoder = JSONDecoder()
        for answer in answers {
            if let refusal = try? decoder.decode(Refusal.self, from: answer), refusal.ok == false {
                throw EngineError.refused(refusal)
            }
        }
        guard let last = answers.last else { throw EngineError.unreadable("") }
        return try decoder.decode(ActionAnswer.self, from: last)
    }
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
