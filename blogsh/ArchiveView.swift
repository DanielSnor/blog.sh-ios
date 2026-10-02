import SwiftUI

/// The archive as `browse` walks it: the posts newest first, the three
/// filters the screen has ([t] type, [s] state, [g] tag), the search ([/]),
/// [z] to clear them, Enter to open a post -- its crossroads -- and Space
/// for a preview of a published one. The search here reads what the rows
/// carry (title, slug, tags); the terminal's reads the whole text.
struct ArchiveView: View {
    var languages: [String] = []
    var baseURL: String = ""
    @Environment(\.openURL) private var openURL
    @State private var posts: [PostRow] = []
    @State private var problem: String?
    @State private var loading = false
    @State private var query = ""
    @State private var type: String?
    @State private var state: StateFilter?
    @State private var tag: String?

    /// The states [s] offers, in the engine's own words.
    enum StateFilter: String, CaseIterable, Identifiable {
        case published, unpublished, draft, scheduled, pinned
        var id: String { rawValue }

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
                    .contextMenu {
                        if post.state == .published, let url = publicURL(post) {
                            Button { openURL(url) } label: { Label("Preview", systemImage: "safari") }
                        }
                    }
                }
            } header: {
                Text(filterLine)
            }
        }
        .navigationDestination(for: PostRow.self) { post in
            PostCrossroadsView(post: post, languages: languages)
        }
        .searchable(text: $query, prompt: "Search the archive")
        .overlay {
            if loading && posts.isEmpty {
                ProgressView()
            } else if !loading && shown.isEmpty && problem == nil {
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
                        ForEach(StateFilter.allCases) { Text($0.rawValue).tag(StateFilter?.some($0)) }
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
        .refreshable { await load() }
    }

    private var types: [String] { Array(Set(posts.map(\.type))).sorted() }
    private var tags: [String] { Array(Set(posts.flatMap(\.tags))).sorted { $0.lowercased() < $1.lowercased() } }

    /// The rows the filters and the search leave, in the order they came.
    private var shown: [PostRow] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return posts.filter { post in
            if let type, post.type != type { return false }
            if let state, !state.matches(post) { return false }
            if let tag, !post.tags.contains(where: { $0.lowercased() == tag.lowercased() }) { return false }
            guard !words.isEmpty else { return true }
            let haystack = ([post.title ?? "", post.slug] + post.tags).joined(separator: " ").lowercased()
            return words.allSatisfy { word in
                word.hasPrefix("-") ? !haystack.contains(word.dropFirst()) : haystack.contains(word)
            }
        }
    }

    /// The status line the screen keeps: which filters are on, and the count.
    private var filterLine: String {
        var parts: [String] = []
        if let type { parts.append("type=\(type)") }
        if let state { parts.append("state=\(state.rawValue)") }
        if let tag { parts.append("tag=\(tag)") }
        if !query.isEmpty { parts.append("search “\(query)”") }
        let filters = parts.isEmpty ? "all" : parts.joined(separator: " · ")
        return "Filter: \(filters) — \(shown.count) of \(posts.count)"
    }

    private func publicURL(_ post: PostRow) -> URL? {
        guard !baseURL.isEmpty else { return nil }
        return URL(string: baseURL.hasSuffix("/") ? "\(baseURL)posts/\(post.year)/\(post.slug)/" : "\(baseURL)/posts/\(post.year)/\(post.slug)/")
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let answer: ListAnswer = try await Engine.shared.call(["list"])
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
    NavigationStack { ArchiveView() }
}
