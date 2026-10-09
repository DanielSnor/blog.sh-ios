import SwiftUI

/// The posts that wait on the device, on their way out: one at a time,
/// in the order they were written, each to the blog it was written for
/// and to no other. A post goes as a draft -- nothing is published by
/// sending it -- and one that arrived waits no longer.
///
/// A post the blog would not take is kept, with the blog's reason, and is
/// not sent again unasked: what was refused once is refused again until
/// somebody has changed something. A silent server refuses nothing; what
/// could not reach it simply still waits.
@Observable final class Outbox {
    static let shared = Outbox()

    enum Outcome: Equatable {
        /// Written on the blog as a draft, under this slug.
        case sent(String)
        /// Still waits: the server could not be reached, or another post is on its way.
        case waits
        /// The blog said no, or the delivery broke on the way; its words.
        case refused(String)
    }

    /// What the blog says when it has not taken a delivery and has
    /// nothing against the post: try again later.
    nonisolated static let notNow: Set<String> = ["busy", "timeout"]

    /// The post on its way.
    private(set) var sending: UUID?
    /// The blogs whose waiting posts are being gone through.
    private var running: Set<UUID> = []

    private let home: URL
    private let open: () -> UUID?
    private let deliver: ([DeliveryFile], UUID) async throws -> ActionAnswer

    init(home: URL = WaitingRoom.home,
         open: @escaping () -> UUID? = { Blogs.shared.currentID },
         deliver: @escaping ([DeliveryFile], UUID) async throws -> ActionAnswer = { files, blog in
             try Engine.made(from: await Engine.shared.deliver(files, to: blog))
         }) {
        self.home = home
        self.open = open
        self.deliver = deliver
    }

    /// One post, to the blog it waits for -- which has to be the open one.
    @discardableResult
    func send(_ post: Waiting, for blog: UUID) async -> Outcome {
        guard sending == nil, open() == blog else { return .waits }
        sending = post.id
        defer {
            sending = nil
            Desk.shared.changed()
        }
        do {
            let files = try WaitingRoom.delivery(of: post, for: blog, in: home)
            let made = try await deliver(files, blog)
            WaitingRoom.remove(post.id, for: blog, in: home)
            return .sent(made.slug)
        } catch {
            if error.isCalledOff { return .waits }
            if case EngineError.unreachable = error { return .waits }
            // The blog is taking another delivery, or building, or gave up
            // on a delivery that stalled on the way: nothing of this one
            // was kept, and it is not a no to the post -- it waits, and
            // goes with the next asking.
            if case EngineError.refused(let refusal) = error, Self.notNow.contains(refusal.error) { return .waits }
            let words = error.localizedDescription
            WaitingRoom.note(words, on: post.id, for: blog, in: home)
            return .refused(words)
        }
    }

    /// Everything that waits for the blog and was not turned away before,
    /// until the server falls silent. How many arrived.
    ///
    /// A run for one blog does not stand in the way of another's: with a
    /// post on its way -- another blog's, or one sent by hand -- this run
    /// takes its turn after it. And the room is looked into again before
    /// every post: one that was thrown away, or taken back into the form,
    /// while another was going is not sent from memory.
    @discardableResult
    func sendAll(for blog: UUID) async -> Int {
        guard !running.contains(blog) else { return 0 }
        running.insert(blog)
        defer { running.remove(blog) }
        while sending != nil { try? await Task.sleep(for: .milliseconds(100)) }
        var sent = 0
        var tried: Set<UUID> = []
        while let post = WaitingRoom.all(for: blog, in: home).first(where: { $0.problem == nil && !tried.contains($0.id) }) {
            tried.insert(post.id)
            switch await send(post, for: blog) {
            case .sent: sent += 1
            case .waits: return sent
            case .refused: continue
            }
        }
        return sent
    }
}
