import SwiftUI

/// The posts kept on the device until their blog can be reached: each
/// with what it is called, when it was written and what goes with it,
/// and the three things there are to do with one -- send it, take it
/// back into the form to write on, throw it away.
struct WaitingView: View {
    /// Back to the form, with a post handed to it.
    let write: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var discarding: Waiting?
    @State private var said: String?
    private var blogs = Blogs.shared
    private var outbox = Outbox.shared

    init(write: @escaping () -> Void) { self.write = write }

    private var posts: [Waiting] {
        _ = Desk.shared.changes
        guard let blog = blogs.currentID else { return [] }
        return WaitingRoom.all(for: blog)
    }

    private var offline: Bool { Reach.shared.isOffline(blogs.current) }

    /// The form holds a post of its own: there is no room in it for another.
    private var formTaken: Bool { blogs.currentID.map { Unsent.kept(for: $0) != nil } ?? true }

    var body: some View {
        let posts = posts
        PaperScreen(name: String(localized: "Waiting to be sent"), count: posts.isEmpty ? nil : posts.count.formatted()) {
            if posts.isEmpty {
                Hint("Nothing waits on this device.").gap(14)
            } else if offline {
                Hint("The blog's server cannot be reached. The posts go to the blog as drafts, in the order they were written, once it answers.")
                    .gap(14)
            } else {
                Hint("Each goes to the blog as a draft; publishing is a decision of its own, made there.").gap(14)
            }
            if let said {
                ProblemLine(text: said)
            }
            ForEach(posts) { post in
                Plate {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: post.headline.isEmpty ? String(localized: "A post without words") : post.headline)
                            .font(.ui(16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                        Text(verbatim: about(post))
                            .font(.ui(13))
                            .foregroundStyle(Theme.muted)
                        if let problem = post.problem {
                            Text(verbatim: problem)
                                .font(.ui(13, weight: .medium))
                                .foregroundStyle(Theme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 4)
                    Command("Send to the blog as a draft", symbol: "paperplane", busy: outbox.sending == post.id) {
                        Task { await send(post) }
                    }
                    .outOfReach(offline)
                    .disabled(outbox.sending != nil)
                    Command("Back to the form, to write on", symbol: "square.and.pencil") {
                        Desk.shared.hand(post)
                        dismiss()
                        write()
                    }
                    .outOfReach(formTaken)
                    .disabled(outbox.sending != nil)
                    Command("Throw away", symbol: "trash", danger: true) { discarding = post }
                        .disabled(outbox.sending == post.id)
                        .confirmationDialog("Throw '\(post.headline)' away? It was never sent; nothing of it is kept.",
                                            isPresented: Binding(get: { discarding?.id == post.id }, set: { if !$0 { discarding = nil } }),
                                            titleVisibility: .visible) {
                            Button("Throw away", role: .destructive) { discard(post) }
                        }
                }
                .gap(14)
            }
            if formTaken, !posts.isEmpty {
                Hint("The form holds a post that is being written: send it or clear it before another is taken back into it.")
            }
        }
        .navigationTitle("Waiting to be sent")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    /// When it was written, and how many pictures and videos go with it.
    private func about(_ post: Waiting) -> String {
        guard !post.pieces.isEmpty else { return post.at.spoken }
        return String(localized: "\(post.at.spoken) · pictures and video: \(post.pieces.count)")
    }

    private func send(_ post: Waiting) async {
        guard let blog = blogs.currentID else { return }
        said = nil
        switch await outbox.send(post, for: blog) {
        case .sent(let slug): Herald.shared.say(String(localized: "Draft written: \(slug)"))
        case .waits: said = Reach.shared.isOffline(blogs.current) ? String(localized: "The blog's server did not answer; the post still waits.") : nil
        case .refused: break
        }
    }

    private func discard(_ post: Waiting) {
        guard let blog = blogs.currentID else { return }
        WaitingRoom.remove(post.id, for: blog)
        Desk.shared.changed()
    }
}
