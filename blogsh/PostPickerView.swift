import SwiftUI

/// "A post": first the pick, the last fifty posts the terminal offers
/// (pick_slug_interactively, RECENT_LIST_COUNT), then the crossroads the
/// wizard puts after it -- the text, or the properties and the actions.
struct PostPickerView: View {
    /// The languages the site publishes beyond its own, for the crossroads.
    var languages: [String] = []
    @State private var posts: [PostRow] = []
    @State private var problem: String?
    @State private var loading = false

    static let recentCount = 50

    var body: some View {
        List {
            if let problem {
                Text(problem).foregroundStyle(.secondary)
            }
            ForEach(posts) { post in
                NavigationLink(value: post) {
                    PostRowView(post: post)
                }
            }
        }
        .navigationDestination(for: PostRow.self) { post in
            PostCrossroadsView(post: post, languages: languages)
        }
        .overlay {
            if loading && posts.isEmpty {
                ProgressView()
            } else if !loading && posts.isEmpty && problem == nil {
                ContentUnavailableView("No posts to choose from.", systemImage: "tray")
            }
        }
        .navigationTitle("A post")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let answer: ListAnswer = try await Engine.shared.call(["list"])
            posts = Array(answer.posts.prefix(Self.recentCount))
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// The wizard's crossroads for one post: Enter opens the text, [v] the
/// properties. The text is the editor's, and comes with it; the
/// properties are here.
struct PostCrossroadsView: View {
    let post: PostRow
    var languages: [String] = []

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.title ?? post.slug).font(.headline)
                    Text(post.slug).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            // The prompt's words: "Edit what? [Enter] the text  [v] properties and
            // actions". The text is the editor's and comes with it.
            Section("Edit what?") {
                NavigationLink {
                    TextEditView(slug: post.slug)
                } label: {
                    Label("the text", systemImage: "text.alignleft")
                }
                // [l]: only on a site that publishes more than one language,
                // the way the prompt only mentions it there.
                ForEach(languages, id: \.self) { lang in
                    NavigationLink {
                        TranslateView(slug: post.slug, lang: lang)
                    } label: {
                        Label("language: \(Locale.current.localizedString(forLanguageCode: lang) ?? lang)", systemImage: "character.bubble")
                    }
                }
                NavigationLink {
                    PropsView(slug: post.slug)
                } label: {
                    Label("properties and actions", systemImage: "slider.horizontal.3")
                }
            }
        }
        .navigationTitle(post.title ?? post.slug)
        .toolbarTitleDisplayMode(.inline)
    }
}

extension PostRow: Hashable {
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

#Preview {
    NavigationStack { PostPickerView() }
}
