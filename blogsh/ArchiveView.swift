import SwiftUI

/// The archive as `list --json` hands it out, newest first. For now it
/// draws a sample of the answer, so the row's shape can be judged before
/// the connection that fetches the real one exists.
struct ArchiveView: View {
    private let posts = PostRow.sample

    var body: some View {
        List(posts) { post in
            PostRowView(post: post)
        }
        .navigationTitle("Archive")
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
    NavigationStack { ArchiveView() }
}
