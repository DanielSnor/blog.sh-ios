import SwiftUI

/// "A post": first the pick, the last fifty posts the terminal offers
/// (pick_slug_interactively, RECENT_LIST_COUNT), then the crossroads the
/// wizard puts after it -- the text, or the properties and the actions.
struct PostPickerView: View {
    /// The languages the site publishes beyond its own, for the crossroads.
    var languages: [String] = []
    @State private var posts: [PostRow] = []
    /// How many the blog has in all: the list is only its newest.
    @State private var total = 0
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
            // Why the list ends here, and where the rest is: said once
            // there is a rest. The whole of it is the way to the archive,
            // with its search already open.
            if total > posts.count {
                NavigationLink {
                    ArchiveView(languages: languages, baseURL: Blogs.shared.current?.url ?? "", searching: true)
                } label: {
                    (Text("The last \(String(posts.count)) posts of \(total.formatted()), as ./blog.sh offers them. Looking for an older one?")
                        .foregroundStyle(Theme.muted)
                     + Text(verbatim: " ")
                     + Text("Search the archive.").foregroundStyle(.tint))
                        .font(.ui(13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                }
                .navigationLinkIndicatorVisibility(.hidden)
                .paperRow(rule: false)
            }
        }
        .paperList()
        .navigationDestination(for: PostRow.self) { post in
            PostCrossroadsView(post: post, languages: languages, gone: { Task { await load() } })
        }
        .overlay {
            if loading && posts.isEmpty {
                ProgressView()
            } else if !loading && posts.isEmpty && problem == nil {
                EmptyNote(symbol: "tray", title: "No posts to choose from.")
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
            total = answer.posts.count
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
    /// The row the screen was opened from: what the list knew then.
    let opened: PostRow
    var languages: [String] = []
    /// Said to the list the post was picked from, when the post is deleted.
    var gone: (() -> Void)?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var looking = false
    @State private var problem: String?
    /// The post's text as the editor would open it: where the lede is read
    /// from, and handed on to the editor so it need not ask again.
    @State private var entry: EditEntry?
    @State private var reading = false
    /// The post was deleted from its properties: this screen is about a
    /// post that is not there, and leaves once it is in front again -- a
    /// screen under another cannot be left.
    @State private var deleted = false
    /// What the post is now, asked again every time the screen is come
    /// to: its title may have been rewritten in the editor and its slug in
    /// the properties, and the row this was opened from knows neither.
    @State private var now: PostRow?
    /// Where the post is, to hand on: the engine's to say, with the rest.
    @State private var link: PostLink?

    init(post: PostRow, languages: [String] = [], gone: (() -> Void)? = nil) {
        opened = post
        self.languages = languages
        self.gone = gone
    }

    private var post: PostRow { now ?? opened }

    var body: some View {
        PaperScreen {
            PostHeading(title: post.title ?? post.slug, detail: post.slug)
            // Which post this is, before anything is done to it: when it is
            // from, what state it is in, and how it begins.
            HStack(spacing: 8) {
                if let day = post.day {
                    Text(verbatim: post.scheduled ? RowDate.soon(day) : RowDate.short(day))
                        .font(.mono(12, bold: post.scheduled))
                        .foregroundStyle(post.scheduled ? AnyShapeStyle(.tint) : AnyShapeStyle(Theme.muted))
                }
                StateBadge(post: post)
                Text(verbatim: post.tags.isEmpty ? post.type : post.tags.joined(separator: ", "))
                    .font(.ui(13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .padding(.top, 10)
            Group {
                if let text = entry?.text {
                    let lede = Lede.of(text)
                    if !lede.words.isEmpty {
                        Text(verbatim: lede.words).foregroundStyle(Theme.ink).lineLimit(9)
                    } else if let picture = lede.picture {
                        Text("Picture: \(picture)").foregroundStyle(Theme.muted)
                    } else {
                        Text("(the post has no text)").foregroundStyle(Theme.muted)
                    }
                } else if reading {
                    ProgressView()
                }
            }
            .font(.ui(15))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            // The prompt's words: "Edit what? [Enter] the text  [v] properties and
            // actions". The text is the editor's and comes with it.
            SectionLabel("Edit what?")
            Plate {
                NavigationLink {
                    // The text read for the lede is handed on only while it is
                    // this post's under this name: after a rename it is not.
                    TextEditView(slug: post.slug, loaded: entry?.slug == post.slug ? entry : nil)
                } label: {
                    CommandRow("the text", symbol: "text.alignleft", leads: true)
                }
                // [l]: only on a site that publishes more than one language,
                // the way the prompt only mentions it there.
                ForEach(languages, id: \.self) { lang in
                    NavigationLink {
                        TranslateView(slug: post.slug, lang: lang)
                    } label: {
                        CommandRow("language: \(Locale.current.localizedString(forLanguageCode: lang) ?? lang)",
                                   symbol: "character.bubble", leads: true)
                    }
                }
                NavigationLink {
                    // A post deleted from its properties takes this screen with
                    // it, and the list reads itself again.
                    PropsView(slug: post.slug, gone: { deleted = true }, renamed: { now = post.seen(as: $0); link = PostLink($0) })
                } label: {
                    CommandRow("properties and actions", symbol: "slider.horizontal.3", leads: true)
                }
            }
            .buttonStyle(PressStyle())
            // Not a key of the prompt: at the desk the browser is one window
            // away, on a phone the page is only this far. A published post
            // opens at its address, a draft at the hidden page the build keeps.
            Plate {
                Command(post.state == .published ? "Show on the web" : "Show the preview on the web",
                        symbol: "safari", busy: looking) {
                    Task { await show() }
                }
                .disabled(looking)
            }
            .padding(.top, 10)
            if let problem {
                ProblemLine(text: problem)
            }
        }
        .navigationTitle(post.title ?? post.slug)
        .toolbar {
            if let link {
                ToolbarItem(placement: .topBarTrailing) { ShareKey(link: link) }
            }
        }
        // Every time the screen is come to, not once: on the way back from
        // the editor the text may be another, and so is the version a save
        // has to name.
        .task { await read() }
    }

    /// `edit <slug> --json` and `props <slug> --json`, in one go: the text
    /// handed out and what the post is now, nothing written. A failure
    /// costs the lede and leaves the row as the list had it -- the keys
    /// below ask for themselves.
    private func read() async {
        if deleted {
            // Back in front, on the way out: after the screen above has gone.
            try? await Task.sleep(for: .milliseconds(500))
            gone?()
            dismiss()
            return
        }
        reading = true
        defer { reading = false }
        let slug = post.slug
        guard let answers = try? await Engine.shared.answers(to: [["edit", slug], ["props", slug]]),
              answers.count == 2 else { return }
        // Asked of one name, answered after the post took another: not this one's to keep.
        guard slug == post.slug else { return }
        if let answer: EditAnswer = try? Engine.decode(answers[0]) { entry = answer.post }
        if let props: PropsAnswer = try? Engine.decode(answers[1]), props.ok {
            now = post.seen(as: props)
            link = PostLink(props)
        }
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
