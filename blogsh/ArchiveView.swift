import SwiftUI

/// The archive as `list --json` hands it out, newest first -- what the
/// terminal's `browse` walks. Filters and search come with it; for now the
/// list, loaded from the server, with the draft filter the command has.
struct ArchiveView: View {
    @State private var posts: [PostRow] = []
    @State private var draftsOnly = false
    @State private var problem: String?
    @State private var loading = false

    var body: some View {
        List {
            if let problem {
                Text(problem).foregroundStyle(.secondary)
            }
            ForEach(posts) { post in
                PostRowView(post: post)
            }
        }
        .overlay {
            if loading && posts.isEmpty {
                ProgressView()
            } else if !loading && posts.isEmpty && problem == nil {
                ContentUnavailableView("No posts", systemImage: "tray")
            }
        }
        .navigationTitle("The archive")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle("Drafts", systemImage: "pencil", isOn: $draftsOnly)
                    .toggleStyle(.button)
            }
        }
        .task(id: draftsOnly) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        var args = ["list"]
        if draftsOnly { args.append("--drafts") }
        do {
            let answer: ListAnswer = try await Engine.shared.call(args)
            posts = answer.posts
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}

struct PostRowView: View {
    let post: PostRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(post.title ?? post.slug)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                if post.pinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Pinned")
                }
            }
            HStack(spacing: 8) {
                StateBadge(post: post)
                if let day = post.day {
                    Text(day, format: .dateTime.year().month().day())
                }
                Text(post.type)
                if !post.tags.isEmpty {
                    Text(post.tags.joined(separator: ", "))
                        .lineLimit(1)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// A draft, a scheduled draft, or nothing at all for a published post:
/// the same three states `list` marks on the terminal.
struct StateBadge: View {
    let post: PostRow

    var body: some View {
        if post.scheduled {
            Text("Scheduled").badgeStyle(.cyan)
        } else if post.state == .draft {
            Text("Draft").badgeStyle(.yellow)
        }
    }
}

private extension Text {
    func badgeStyle(_ color: Color) -> some View {
        self
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}

#Preview {
    NavigationStack { List(PostRow.sample) { PostRowView(post: $0) } }
}
