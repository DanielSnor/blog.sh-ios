import Foundation

/// Where a connection goes and what it is opened with: one blog's server
/// and that blog's key. Two calls share a connection only when all of it
/// is the same.
nonisolated struct Door: Hashable, Sendable {
    let host: String
    let port: Int
    let user: String
    let keyAccount: String
}

/// The connection the app keeps to the open blog's server. A server
/// counts the connections an address opens, and turns the ones over its
/// count away -- so somebody going from screen to screen, each asking a
/// thing or two, was soon asking a server that no longer answered. One
/// connection is opened with the first call and kept for the ones after
/// it: every command is a channel of its own on it, several at once where
/// a build runs while a list is read. It is closed when nothing has used
/// it for a while, when another blog is opened, and when the app leaves
/// the screen.
///
/// What is kept here is only which connection, for whom and how busy; how
/// one is opened and closed is handed in, so the keeping can be tested
/// without a server.
actor Line<Wire: Sendable> {
    /// One call's use of the connection, given back when the call is over.
    struct Hold: Sendable {
        let wire: Wire
        fileprivate let id: Int
        /// The connection had been lying unused for a while when this call
        /// took it, and no other call was on it: if it does not answer,
        /// it is dead rather than slow, and nobody else is harmed by
        /// closing it.
        let rested: Bool
    }

    private let keep: Double
    private let rest: Double
    private let open: @Sendable (Door) async throws -> Wire
    private let close: @Sendable (Wire) async -> Void

    private var current: (id: Int, door: Door, wire: Wire)?
    /// A connection on its way up: whoever asks for the same door
    /// meanwhile waits for this one instead of opening a second.
    private var opening: (id: Int, door: Door, task: Task<Wire, Error>)?
    /// Calls in flight, by connection.
    private var busy: [Int: Int] = [:]
    /// Connections no longer kept that a call is still on: closed when
    /// their last call gives them back.
    private var leaving: [Int: Wire] = [:]
    private var lastUsed: [Int: ContinuousClock.Instant] = [:]
    private var timer: Task<Void, Never>?
    private var serial = 0
    /// How many connections were opened, ever: what a server counts.
    private(set) var opened = 0

    /// `keep`: how long a connection nobody uses is kept, in seconds.
    /// `rest`: after how long unused it is no longer taken on trust.
    init(keep: Double, rest: Double = 20,
         open: @escaping @Sendable (Door) async throws -> Wire,
         close: @escaping @Sendable (Wire) async -> Void) {
        self.keep = keep
        self.rest = rest
        self.open = open
        self.close = close
    }

    /// The connection to this door: the kept one, the one just being
    /// opened, or a new one -- after which whatever was kept to another
    /// door is let go.
    func take(_ door: Door) async throws -> Hold {
        if let current, current.door == door {
            return hold(current.id, current.wire)
        }
        if let opening, opening.door == door {
            let wire = try await opening.task.value
            return hold(opening.id, wire)
        }
        serial += 1
        let id = serial
        let open = open
        let task = Task { try await open(door) }
        // Said before anything is waited for: a call for the same door
        // that arrives meanwhile finds this one, and opens no second.
        opening = (id, door, task)
        await letGo()
        do {
            let wire = try await task.value
            opened += 1
            if opening?.id == id {
                opening = nil
                current = (id, door, wire)
            } else {
                // Let go of while it was coming up: used by the calls
                // that waited for it, kept by nobody.
                leaving[id] = wire
            }
            return hold(id, wire)
        } catch {
            if opening?.id == id { opening = nil }
            throw error
        }
    }

    /// The call is over. `broken`: the connection failed under it, and is
    /// not one to hand to the next call.
    func give(_ hold: Hold, broken: Bool = false) async {
        let id = hold.id
        if broken, let kept = current, kept.id == id {
            current = nil
            leaving[id] = kept.wire
        }
        lastUsed[id] = .now
        let left = (busy[id] ?? 1) - 1
        busy[id] = left > 0 ? left : nil
        guard left <= 0 else { return }
        if let wire = leaving.removeValue(forKey: id) {
            lastUsed[id] = nil
            await close(wire)
        } else if current?.id == id {
            arm(id)
        }
    }

    /// Lets go of whatever is kept: the app left the screen, or the key
    /// or the server's address was changed under the connection.
    func drop() async {
        opening = nil
        await letGo()
    }

    private func hold(_ id: Int, _ wire: Wire) -> Hold {
        let alone = busy[id] == nil
        let since = lastUsed[id].map { ContinuousClock.now - $0 }
        busy[id, default: 0] += 1
        if current?.id == id { timer?.cancel() }
        return Hold(wire: wire, id: id, rested: alone && (since.map { $0 > .seconds(rest) } ?? false))
    }

    private func letGo() async {
        timer?.cancel()
        guard let kept = current else { return }
        current = nil
        if busy[kept.id] == nil {
            lastUsed[kept.id] = nil
            await close(kept.wire)
        } else {
            leaving[kept.id] = kept.wire
        }
    }

    private func arm(_ id: Int) {
        timer?.cancel()
        let keep = keep
        timer = Task {
            try? await Task.sleep(for: .seconds(keep))
            guard !Task.isCancelled else { return }
            await self.expire(id)
        }
    }

    private func expire(_ id: Int) async {
        guard let kept = current, kept.id == id, busy[id] == nil else { return }
        current = nil
        lastUsed[id] = nil
        await close(kept.wire)
    }
}
