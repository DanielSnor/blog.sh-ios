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
            ScreenHeader(title: String(localized: "tile.post", defaultValue: "Post"))
                .padding(.top, 2)
                .padding(.bottom, 6)
                .paperRow()
            if let problem {
                Text(problem).font(.ui(14)).foregroundStyle(Theme.muted).paperRow()
            }
            ForEach(posts) { post in
                NavigationLink(value: post) {
                    PostRowView(post: post)
                }
                .navigationLinkIndicatorVisibility(.hidden)
                .paperRow()
            }
        }
        .paperList()
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
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}

/// The wizard's crossroads for one post: Enter opens the text, [v] the
/// properties. The text is the editor's, and comes with it; the
/// properties are here.
struct PostCrossroadsView: View {
    let post: PostRow
    var languages: [String] = []
    @Environment(\.openURL) private var openURL
    @State private var looking = false
    @State private var problem: String?

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
            // Not a key of the prompt: at the desk the browser is one window
            // away, on a phone the page is only this far. A published post
            // opens at its address, a draft at the hidden page the build keeps.
            Section {
                Button {
                    Task { await show() }
                } label: {
                    Label(post.state == .published ? "Show on the web" : "Show the preview on the web", systemImage: "safari")
                }
                .disabled(looking)
            } footer: {
                if let problem {
                    Text(problem).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(post.title ?? post.slug)
        .toolbarTitleDisplayMode(.inline)
    }

    /// The address is the engine's to say: a post can carry one of its own.
    private func show() async {
        looking = true
        defer { looking = false }
        do {
            let props: PropsAnswer = try await Engine.shared.call(["props", post.slug])
            guard let url = URL(string: props.url), !props.url.isEmpty else {
                problem = String(localized: "The site has no address set, so there is nothing to open.")
                return
            }
            problem = nil
            openURL(url)
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}

extension PostRow: Hashable {
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

#Preview {
    NavigationStack { PostPickerView() }
}
