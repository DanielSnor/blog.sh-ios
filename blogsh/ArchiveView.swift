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
    /// What the screen opens with: a state already chosen, the search already open.
    var initialState: StateFilter?
    var searching = false
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
    @State private var searchOpen = false
    @State private var opened = false

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
            ScreenHeader(title: String(localized: "tile.browse", defaultValue: "Archive"), count: countLine)
                .padding(.top, 2)
                .paperRow(rule: false)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button { state = nil } label: { FilterPill(label: String(localized: "all"), selected: state == nil) }
                    ForEach(StateFilter.allCases) { one in
                        Button { state = state == one ? nil : one } label: { FilterPill(label: one.label, selected: state == one) }
                    }
                    Menu {
                        Picker("type", selection: $type) {
                            Text("any type").tag(String?.none)
                            ForEach(types, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    } label: {
                        FilterPill(label: type.map { String(localized: "type=\($0)") } ?? String(localized: "type"), selected: type != nil)
                    }
                    Menu {
                        Picker("tag", selection: $tag) {
                            Text("any tag").tag(String?.none)
                            ForEach(tags, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    } label: {
                        FilterPill(label: tag.map { String(localized: "tag=\($0)") } ?? String(localized: "tag"), selected: tag != nil)
                    }
                }
                .buttonStyle(PressStyle())
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 10)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden, edges: .top)
            .listRowSeparatorTint(Theme.line)
            if let problem {
                Text(problem).font(.ui(14)).foregroundStyle(Theme.muted).paperRow()
            }
            ForEach(shown) { post in
                NavigationLink(value: post) {
                    PostRowView(post: post)
                }
                .navigationLinkIndicatorVisibility(.hidden)
                .paperRow()
                .swipeActions(edge: .leading) {
                    Button { previewing = post } label: { Label("Preview", systemImage: "doc.text.magnifyingglass") }
                }
                .contextMenu {
                    Button { previewing = post } label: { Label("Preview", systemImage: "doc.text.magnifyingglass") }
                }
            }
        }
        .paperList()
        .navigationDestination(for: PostRow.self) { post in
            PostCrossroadsView(post: post, languages: languages)
        }
        .sheet(item: $previewing) { post in
            NavigationStack { PostPreviewView(post: post, baseURL: baseURL) }
        }
        .searchable(text: $query, isPresented: $searchOpen, prompt: "Search the archive")
        .overlay {
            if loading && posts.isEmpty {
                ProgressView()
            } else if !loading && shown.isEmpty && problem == nil && searchingFor == nil {
                ContentUnavailableView(posts.isEmpty ? "No posts" : "Nothing matches", systemImage: "tray")
            }
        }
        .navigationTitle("The archive")
        .task {
            if !opened {
                opened = true
                state = initialState
                searchOpen = searching
            }
            await load()
        }
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

    /// How many, beside the screen's name: all of them, or how many of
    /// them the filters and the search leave.
    private var countLine: String {
        let filtered = type != nil || state != nil || tag != nil || !words.isEmpty
        let line = filtered ? String(localized: "\(shown.count) of \(posts.count)") : posts.count.formatted()
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

/// A post as a row says it: its title, its tags under it, and at the
/// edge its date -- in the accent when it is a date still to come.
struct PostRowView: View {
    let post: PostRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                // An untitled post goes by its slug, dimmed, as the terminal dims it.
                Text(post.title ?? post.slug)
                    .font(.ui(15, weight: post.title == nil ? .medium : .bold))
                    .foregroundStyle(post.title == nil ? Theme.muted : Theme.ink)
                    .lineLimit(2)
                Text(post.tags.isEmpty ? post.type : post.tags.joined(separator: ", "))
                    .font(.ui(13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                // Why the search found it: the line of its text that matched.
                if let match = post.match, !match.isEmpty {
                    Text(match)
                        .font(.ui(12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                if let day = post.day {
                    Text(verbatim: post.scheduled ? RowDate.soon(day) : RowDate.short(day))
                        .font(.mono(11, bold: post.scheduled))
                        .foregroundStyle(post.scheduled ? AnyShapeStyle(.tint) : AnyShapeStyle(Theme.muted))
                } else {
                    StateBadge(post: post)
                }
                if post.pinned {
                    Image(systemName: "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .accessibilityLabel("Pinned")
                }
            }
            .padding(.top, 3)
        }
        .padding(.vertical, 11)
    }
}

/// A draft, a scheduled draft, or nothing at all for a published post:
/// the same three states `list` marks on the terminal.
struct StateBadge: View {
    let post: PostRow

    var body: some View {
        if post.scheduled {
            Text("Scheduled").stateMark(filled: true)
        } else if post.state == .draft {
            Text("Draft").stateMark(filled: false)
        }
    }
}

private extension Text {
    func stateMark(filled: Bool) -> some View {
        font(.mono(11, bold: filled))
            .textCase(.lowercase)
            .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.muted))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background { if filled { Capsule().fill(.tint) } }
            .overlay { if !filled { Capsule().strokeBorder(Theme.line, lineWidth: 1) } }
    }
}

#Preview {
    NavigationStack { ArchiveView() }
}
