import Foundation
import Network
import Observation

/// Whether a blog's server answered the last time it was asked. A blog
/// whose server did not is offline: nothing that needs the server is
/// offered there, and what can be done without it -- writing -- still
/// is. The server is what is silent, not the blog: two blogs behind one
/// address share its fate.
///
/// Nothing here asks the server anything. The engine's calls say what
/// became of them: one that could not get through makes the server
/// silent, any that was answered makes it heard from again.
@Observable final class Reach {
    static let shared = Reach()

    private(set) var silent: Set<String> = []

    /// How long a silent server is left alone before it is asked again
    /// by itself, attempt after attempt: five seconds, then twice as long
    /// each time, and a minute at the most. A network that has just come
    /// back often does not carry a connection yet; asked once and no
    /// more, a server that would have answered a moment later stayed
    /// silent until somebody thought of it.
    nonisolated static func pause(after attempt: Int) -> Duration {
        attempt >= 4 ? .seconds(60) : .seconds(5 << max(attempt, 0))
    }

    /// A server, as the app tells one from another.
    nonisolated static func server(host: String, port: Int) -> String {
        "\(host.trimmingCharacters(in: .whitespaces).lowercased()):\(port == 0 ? 22 : port)"
    }

    func nothing(from server: String) {
        if !silent.contains(server) { silent.insert(server) }
    }

    func heard(from server: String) {
        if silent.contains(server) { silent.remove(server) }
    }

    /// The blog's server did not answer the last time it was asked.
    func isOffline(_ blog: Blog?) -> Bool {
        guard let blog else { return false }
        return silent.contains(Self.server(host: blog.host, port: blog.port))
    }
}

/// The device's own network, watched for one thing: the moment it has
/// one that can carry a connection. That is when a server that was
/// silent is worth asking again -- which nobody should have to think of.
nonisolated enum NetworkWatch {
    /// The device's network as it was last seen, kept by one watcher of
    /// its own from the first time anybody asks.
    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var up = true
        private let monitor = NWPathMonitor()

        init() {
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                self.lock.withLock { self.up = path.status == .satisfied }
            }
            monitor.start(queue: DispatchQueue(label: "app.blogsh.ios.network.seen"))
        }

        var isUp: Bool { lock.withLock { up } }
    }

    private static let seen = Seen()

    /// The device has a network that can carry a connection. Until the
    /// system has said anything, it is taken to have one.
    static var hasNetwork: Bool { seen.isUp }

    static var comes: AsyncStream<Void> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                if path.status == .satisfied { continuation.yield() }
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "app.blogsh.ios.network"))
        }
    }
}
