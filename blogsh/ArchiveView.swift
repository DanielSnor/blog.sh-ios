import SwiftUI

/// The archive as `browse` walks it: the posts newest first, the three
/// filters the screen has ([t] type, [s] state, [g] tag), the search ([/]),
/// [z] to clear them, Enter to open a post -- its crossroads -- and Space
/// for a look at the one under the cursor. The search is the engine's own
/// (`list --search`), over the whole text; until its answer is back, and on
/// an engine from before the flag, the rows are matched on what they carry
/// (title, slug, tags).
struct ArchiveView: View {
    var languages: [String] = []
    var baseURL: String = ""
    @State private var posts: [PostRow] = []
    @State private var problem: String?
    @State private var loading = false
    @State private var query = ""
    @State private var type: String?
    @State private var state: StateFilter?
    @State private var tag: String?
    @State private var found: Found?
    @State private var searchingFor: String?
    @State private var previewing: PostRow?

    /// What the engine found for a query, in its own order.
    struct Found: Equatable {
        let query: String
        let rows: [PostRow]
    }

    /// The states [s] offers, in the engine's own words.
    enum StateFilter: String, CaseIterable, Identifiable {
        case published, unpublished, draft, scheduled, pinned
        var id: String { rawValue }

        var label: String {
            switch self {
            case .published: String(localized: "browse.state.published", defaultValue: "published")
            case .unpublished: String(localized: "browse.state.unpublished", defaultValue: "not published yet")
            case .draft: String(localized: "browse.state.draft", defaultValue: "in progress")
            case .scheduled: String(localized: "browse.state.scheduled", defaultValue: "scheduled")
            case .pinned: String(localized: "browse.state.pinned", defaultValue: "pinned")
            }
        }

        func matches(_ post: PostRow) -> Bool {
            switch self {
            case .published: post.state == .published
            case .unpublished: post.state == .draft
            case .draft: post.state == .draft && !post.scheduled
            case .scheduled: post.scheduled
            case .pinned: post.pinned
            }
        }
    }

    var body: some View {
        List {
            if let problem {
                Text(problem).foregroundStyle(.secondary)
            }
            Section {
                ForEach(shown) { post in
                    NavigationLink(value: post) {
                        PostRowView(post: post)
                    }
                    .swipeActions(edge: .leading) {
                        Button { previewing = post } label: { Label("Preview", systemImage: "doc.text.magnifyingglass") }
                    }
                    .contextMenu {
                        Button { previewing = post } label: { Label("Preview", systemImage: "doc.text.magnifyingglass") }
                    }
                }
            } header: {
                Text(filterLine)
            }
        }
        .navigationDestination(for: PostRow.self) { post in
            PostCrossroadsView(post: post, languages: languages)
        }
        .sheet(item: $previewing) { post in
            NavigationStack { PostPreviewView(post: post, baseURL: baseURL) }
        }
        .searchable(text: $query, prompt: "Search the archive")
        .overlay {
            if loading && posts.isEmpty {
                ProgressView()
            } else if !loading && shown.isEmpty && problem == nil && searchingFor == nil {
                ContentUnavailableView(posts.isEmpty ? "No posts" : "Nothing matches", systemImage: "tray")
            }
        }
        .navigationTitle("The archive")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("type", selection: $type) {
                        Text("any type").tag(String?.none)
                        ForEach(types, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    Picker("state", selection: $state) {
                        Text("any state").tag(StateFilter?.none)
                        ForEach(StateFilter.allCases) { Text($0.label).tag(StateFilter?.some($0)) }
                    }
                    Picker("tag", selection: $tag) {
                        Text("any tag").tag(String?.none)
                        ForEach(tags, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    if type != nil || state != nil || tag != nil || !query.isEmpty {
                        Button { type = nil; state = nil; tag = nil; query = "" } label: {
                            Label("Clear the filters", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Label("Filter", systemImage: type != nil || state != nil || tag != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .task { await load() }
        .task(id: words) { await search(words) }
        .refreshable { await load() }
    }

    private var types: [String] { Array(Set(posts.map(\.type))).sorted() }
    private var tags: [String] { Array(Set(posts.flatMap(\.tags))).sorted { $0.lowercased() < $1.lowercased() } }

    /// The query as it is asked: what was typed, without the space around it.
    private var words: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The rows the filters and the search leave. The engine's answer when
    /// it is the answer to this very query -- it read the whole text, and
    /// its order is the screen's -- and the rows' own words until then.
    private var shown: [PostRow] {
        let searched: [PostRow]
        if let found, found.query == words {
            searched = found.rows
        } else {
            searched = posts.filter(matchesLocally)
        }
        return searched.filter { post in
            if let type, post.type != type { return false }
            if let state, !state.matches(post) { return false }
            if let tag, !post.tags.contains(where: { $0.lowercased() == tag.lowercased() }) { return false }
            return true
        }
    }

    private func matchesLocally(_ post: PostRow) -> Bool {
        let tokens = words.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return true }
        let haystack = ([post.title ?? "", post.slug] + post.tags).joined(separator: " ").lowercased()
        return tokens.allSatisfy { token in
            token.hasPrefix("-") ? !haystack.contains(token.dropFirst()) : haystack.contains(token)
        }
    }

    /// The status line the screen keeps: which filters are on, and the count.
    private var filterLine: String {
        var parts: [String] = []
        if let type { parts.append(String(localized: "type=\(type)")) }
        if let state { parts.append(String(localized: "state=\(state.label)")) }
        if let tag { parts.append(String(localized: "tag=\(tag)")) }
        if !words.isEmpty { parts.append(String(localized: "search “\(words)”")) }
        let filters = parts.isEmpty ? String(localized: "all") : parts.joined(separator: " · ")
        let line = String(localized: "Filter: \(filters) — \(shown.count) of \(posts.count)")
        return searchingFor == nil ? line : line + " …"
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let answer: ListAnswer = try await Engine.shared.call(["list"])
            posts = answer.posts
            problem = nil
            // The archive is in hand: the tag suggestions need not ask for it again.
            TagStore.shared.take(answer.posts)
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }

    /// [/]: the question goes to the engine once the keys rest, not on
    /// every one of them -- each asking is a connection.
    private func search(_ words: String) async {
        guard !words.isEmpty else {
            found = nil
            searchingFor = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        searchingFor = words
        defer { if searchingFor == words { searchingFor = nil } }
        let answer: ListAnswer? = try? await Engine.shared.call(["list", "--search=\(words)"])
        guard let answer, !Task.isCancelled else { return }
        // An engine from before the flag ignores it and answers with the
        // whole archive; the query said back is how the two are told apart.
        if answer.search != nil { found = Found(query: words, rows: answer.posts) }
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
            // Why the search found it: the line of its text that matched.
            if let match = post.match, !match.isEmpty {
                Text(match)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
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
