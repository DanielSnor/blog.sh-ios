import SwiftUI

/// Space on the archive screen: a look at the post under the cursor without
/// opening it -- its title, the row's own line, its tags, and the text as
/// the editor would show it. `edit <slug> --json` hands the text out for
/// any post, a draft as well as a published one; nothing is written. The
/// page itself is one tap further: a published post's address, or the
/// hidden page the build keeps for a draft.
struct PostPreviewView: View {
    let post: PostRow
    var baseURL: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var entry: EditEntry?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(post.title ?? post.slug)
                    .font(.title3.bold())
                HStack(spacing: 8) {
                    StateBadge(post: post)
                    if let day = post.day {
                        Text(day, format: .dateTime.year().month().day())
                    }
                    Text(verbatim: "[\(post.type)]")
                    Text(verbatim: post.slug).lineLimit(1)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if !post.tags.isEmpty {
                    Text("tags: \(post.tags.joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Divider()
                if let entry {
                    let text = words(of: entry)
                    if text.isEmpty {
                        Text("(the post has no text)").foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: text)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                } else if let problem {
                    Text(problem).foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Preview")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            if let url = webURL {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openURL(url) } label: { Label("Show on the web", systemImage: "safari") }
                }
            }
        }
        .task { await load() }
    }

    /// The text without the header the editor puts above it: the title and
    /// the tags are already on the screen.
    private func words(of entry: EditEntry) -> String {
        guard var text = entry.text else { return "" }
        if text.hasPrefix("---\n"), let close = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) {
            text = String(text[close.upperBound...])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Where the page is: the site's address and the post's own path, which
    /// for a draft is its hidden preview.
    private var webURL: URL? {
        guard let entry, !baseURL.isEmpty, entry.preview.hasPrefix("/") else { return nil }
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return URL(string: base + entry.preview)
    }

    private func load() async {
        do {
            let answer: EditAnswer = try await Engine.shared.call(["edit", post.slug])
            entry = answer.post
            problem = nil
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { PostPreviewView(post: PostRow.sample[0]) }
}
