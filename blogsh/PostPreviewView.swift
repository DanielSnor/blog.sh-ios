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
        PaperScreen(title: post.title ?? post.slug) {
            PostFacts(post: post)
            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 14)
            if let entry {
                let text = words(of: entry)
                if text.isEmpty {
                    Text("(the post has no text)").font(.ui(15)).foregroundStyle(Theme.muted)
                } else {
                    Text(verbatim: text)
                        .font(.mono(15, bold: false))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                }
            } else if let problem {
                ProblemLine(text: problem)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Preview")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            if let url = webURL {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openURL(url) } label: { Label("Show on the web", systemImage: "safari") }
                }
                if let link = PostLink(address: url.absoluteString, title: post.title ?? post.slug) {
                    ToolbarItem(placement: .topBarTrailing) { ShareKey(link: link) }
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
