import SwiftUI

/// The wizard's main menu: what `./blog.sh` with no command shows. The
/// order and the number of entries are the engine's (locales/*.yml,
/// wizard_menu_*); the app adds nothing to it. Settings are not a menu
/// entry -- the terminal has none -- so they sit in the toolbar.
enum MenuEntry: String, CaseIterable, Identifiable {
    case add, post, queue, browse, restore, rebuild

    var id: String { rawValue }

    /// The entry as the wizard prints it.
    var name: LocalizedStringKey {
        switch self {
        case .add: "New post"
        case .post: "A post"
        case .queue: "The scheduled-post queue"
        case .browse: "The archive"
        case .restore: "Trash"
        case .rebuild: "The site"
        }
    }

    /// The entry as a tile says it: one word.
    var short: String {
        switch self {
        case .add: String(localized: "tile.add", defaultValue: "New")
        case .post: String(localized: "tile.post", defaultValue: "Post")
        case .queue: String(localized: "tile.queue", defaultValue: "Queue")
        case .browse: String(localized: "tile.browse", defaultValue: "Archive")
        case .restore: String(localized: "tile.restore", defaultValue: "Trash")
        case .rebuild: String(localized: "tile.rebuild", defaultValue: "Site")
        }
    }

    var symbol: String {
        switch self {
        case .add: "plus"
        case .post: "doc.text"
        case .queue: "list.number"
        case .browse: "archivebox"
        case .restore: "trash"
        case .rebuild: "globe"
        }
    }
}

/// What waits, read once for the first screen: the queue, and how many
/// drafts are in progress.
struct Glance: Equatable {
    var queue: [QueueRow]
    var drafts: Int
}

struct ContentView: View {
    @State private var selection: MenuEntry?
    @State private var column: NavigationSplitViewColumn = .sidebar
    // Where there is room for both, which of the two columns are shown: the
    // menu steps aside when the screen is turned upright over an open screen.
    @State private var columns: NavigationSplitViewVisibility = .automatic
    @State private var upright = false
    // A fresh stack for every visit, and what the archive opens with.
    @State private var visit = 0
    @State private var archiveState: ArchiveView.StateFilter?
    @State private var archiveSearching = false
    @State private var showingSettings = false
    @State private var identity: VersionAnswer?
    @State private var identityProblem: String?
    @State private var glance: Glance?
    @State private var showingBlogs = false
    // After the blogs' sheet has closed: a blog just added goes to its settings.
    @State private var settingsNext = false
    // The blogs, and the one that is open: its name, its colour and its limit
    // are kept from its last answer, so the app opens as that blog before
    // the server has said anything.
    private var blogs = Blogs.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $column) {
            HomeView(name: identity?.site.name ?? blogs.current?.label ?? "", claim: identity?.site.claim ?? blogs.current?.claim ?? "",
                     url: identity?.site.url ?? blogs.current?.url ?? "",
                     switchBlog: { showingBlogs = true },
                     identity: identity, problem: identityProblem, glance: glance,
                     current: sizeClass == .regular ? selection : nil,
                     open: open)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "gearshape") { showingSettings = true }
                    }
                }
                .sheet(isPresented: $showingSettings, onDismiss: { Task { await load() } }) {
                    NavigationStack { SettingsView() }
                }
                .sheet(isPresented: $showingBlogs, onDismiss: {
                    if settingsNext {
                        settingsNext = false
                        showingSettings = true
                    }
                }) {
                    NavigationStack { BlogsView(added: { settingsNext = true }) }
                }
                .task { await load() }
                .refreshable { await load() }
        } detail: {
            // A stack of its own: the screens push further screens (a post,
            // then its properties), and the split view's detail column does
            // not push by itself.
            NavigationStack {
                switch selection {
                case .add: ComposeView()
                case .post: PostPickerView(languages: otherLanguages)
                case .queue: QueueView()
                case .browse: ArchiveView(languages: otherLanguages, baseURL: identity?.site.url ?? "",
                                          initialState: archiveState, searching: archiveSearching)
                case .restore: TrashView()
                case .rebuild: SiteView()
                case nil:
                    EmptyNote(symbol: "terminal", title: "What do you want to do?")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.paper.ignoresSafeArea())
                }
            }
            .id(visit)
        }
        // The blog's own accent, as /write/ wears it: every control of the
        // app, the sheets included. Until a blog has said its own, the
        // look's.
        .tint(Color(hex: (colorScheme == .dark ? blogs.current?.accentDark : blogs.current?.accentLight) ?? "") ?? Theme.ember)
        // Another blog: nothing of the last one stays on the screen, and its
        // own name and colour are there before its server answers.
        .onChange(of: blogs.currentID) {
            identity = nil
            identityProblem = nil
            glance = nil
            selection = nil
            visit += 1
            column = .sidebar
            if upright { columns = .all }
            TagStore.shared.reset()
            Task { await load() }
        }
        // Upright there is room for one column: the screen that is open, or
        // the menu when none is. On its side there is room for both.
        .onGeometryChange(for: Bool.self) { $0.size.width < $0.size.height } action: { now in
            upright = now
            columns = now && selection != nil ? .detailOnly : .all
        }
        // What changed on the way back is on the first screen again.
        .onChange(of: column) { _, now in
            if now == .sidebar { Task { await loadGlance() } }
        }
    }

    private func open(_ entry: MenuEntry, state: ArchiveView.StateFilter? = nil, searching: Bool = false) {
        archiveState = state
        archiveSearching = searching
        visit += 1
        selection = entry
        column = .detail
        // Upright there is room for one: the screen that was asked for.
        if upright { columns = .detailOnly }
    }

    /// The languages the site publishes beyond its own.
    private var otherLanguages: [String] {
        guard let identity else { return [] }
        return identity.site.locales.filter { $0 != identity.site.lang }
    }
    /// Everything the first screen says, over one connection: the identity
    /// block (`version --json`), the queue and the drafts. Without a server
    /// set up the header says so and the settings are one tap away.
    private func load() async {
        let asked = blogs.currentID
        do {
            let answers = try await Engine.shared.answers(to: [["version"], ["queue"], ["list", "--drafts"]])
            // Another blog was opened while this one was answering.
            guard asked == blogs.currentID else { return }
            let answer: VersionAnswer = try Engine.decode(answers[0])
            identity = answer
            identityProblem = nil
            // Asked of one blog, answered while another is open: not this one's to keep.
            blogs.update { blog in
                blog.name = answer.site.name
                blog.claim = answer.site.claim
                blog.url = answer.site.url
                blog.maxMb = answer.maxMb
                if let accent = answer.site.accent {
                    blog.accentLight = accent.light
                    blog.accentDark = accent.dark
                }
            }
            glance = Self.glance(queue: answers[1], drafts: answers[2])
        } catch EngineError.notConfigured {
            identity = nil
            glance = nil
            identityProblem = String(localized: "No server yet — set one up under the gear.")
        } catch {
            // Called off, or another blog by now: the screen keeps what it shows.
            if error.isCalledOff || asked != blogs.currentID { return }
            identity = nil
            glance = nil
            identityProblem = error.localizedDescription
        }
    }

    /// The two cards again, on the way back from a screen that may have
    /// changed them -- one connection, and a failure leaves them as they were.
    private func loadGlance() async {
        let asked = blogs.currentID
        guard identity != nil,
              let answers = try? await Engine.shared.answers(to: [["queue"], ["list", "--drafts"]]),
              asked == blogs.currentID else { return }
        glance = Self.glance(queue: answers[0], drafts: answers[1]) ?? glance
    }

    /// An engine too old to answer one of the two has no cards, not an error.
    private static func glance(queue: Data, drafts: Data) -> Glance? {
        guard let waiting: QueueAnswer = try? Engine.decode(queue),
              let unpublished: ListAnswer = try? Engine.decode(drafts) else { return nil }
        return Glance(queue: waiting.queue, drafts: unpublished.posts.filter { !$0.scheduled }.count)
    }
}

/// The first screen, at one glance: which blog and which engine, what
/// waits -- the next post in the queue, the drafts in progress -- and the
/// six entries of the wizard's menu as tiles.
struct HomeView: View {
    /// The blog as it was last known, or as it has just said.
    let name: String
    let claim: String
    let url: String
    /// The header is the way to the other blogs.
    let switchBlog: () -> Void
    let identity: VersionAnswer?
    let problem: String?
    let glance: Glance?
    /// The entry whose screen is open beside this one, where there is a beside.
    let current: MenuEntry?
    let open: (MenuEntry, ArchiveView.StateFilter?, Bool) -> Void

    @State private var mark: UIImage?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The blog's own mark beside its name, as /write/ wears it: the name
                // and the claim share one left edge, the mark stands before both.
                // The whole of it is a key: the other blogs are behind it.
                Button(action: switchBlog) {
                    HStack(alignment: .center, spacing: 14) {
                        if let mark { SiteMark(image: mark) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: name.isEmpty ? "blog.sh" : name)
                                .font(.display(40))
                                .textCase(.lowercase)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .accessibilityAddTraits(.isHeader)
                            if !claim.isEmpty {
                                Text(verbatim: claim)
                                    .font(.ui(15))
                                    .foregroundStyle(Theme.muted)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityHint(Text("Blogs"))
                HStack(spacing: 8) {
                    Rectangle().fill(.tint).frame(width: 14, height: 1)
                    Text(verbatim: "./blog.sh \(identity?.engine ?? "")")
                        .engineLabel()
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 14)

                if identity == nil {
                    if let problem {
                        Text(verbatim: problem)
                            .font(.ui(14))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 14)
                    } else {
                        ProgressView().padding(.top, 14)
                    }
                }

                if let glance {
                    VStack(spacing: 8) {
                        Button { open(.queue, nil, false) } label: { queueCard(glance) }
                        Button { open(.browse, .draft, false) } label: { draftsCard(glance) }
                    }
                    .buttonStyle(PressStyle())
                    .padding(.top, 18)
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(MenuEntry.allCases) { entry in
                        Button { open(entry, nil, false) } label: {
                            Tile(entry: entry, highlighted: current == entry)
                        }
                    }
                }
                .buttonStyle(PressStyle())
                .padding(.top, glance == nil ? 22 : 10)

                Button { open(.browse, nil, true) } label: {
                    Card(capsule: true) {
                        Text(verbatim: "/").font(.mono(13)).foregroundStyle(.tint)
                        Text("Search the archive").engineLabel().foregroundStyle(Theme.muted)
                    }
                }
                .buttonStyle(PressStyle())
                .padding(.top, 14)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(Theme.paper.ignoresSafeArea())
        // The mark: at once from the copy kept on the device, then fetched again.
        .task(id: url) {
            mark = SiteIcon.kept(for: url)
            if let fresh = await SiteIcon.fetch(for: url) { mark = fresh }
        }
        .navigationTitle(Text(verbatim: "./blog.sh"))
        .namedByItsHeader()
    }

    /// The next post to go out, and how many wait in all.
    private func queueCard(_ glance: Glance) -> some View {
        Card {
            Image(systemName: "clock").foregroundStyle(.tint)
            if let next = glance.queue.first {
                let when = ISO8601DateFormatter.engine.date(from: next.date).map(RowDate.soon) ?? ""
                Text(verbatim: "\(next.title.isEmpty ? next.slug : next.title) · \(when)")
                    .font(.ui(15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                CountBadge(count: glance.queue.count)
            } else {
                Text("Nothing scheduled").font(.ui(15)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func draftsCard(_ glance: Glance) -> some View {
        Card {
            Image(systemName: "pencil").foregroundStyle(.tint)
            if glance.drafts > 0 {
                Text("Drafts in progress").font(.ui(15, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer(minLength: 6)
                CountBadge(count: glance.drafts)
            } else {
                Text("No drafts in progress").font(.ui(15)).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// The blog's favicon, the one the build puts at /assets/images/favicon.png
/// and /write/ shows in its header. Shown at once from the copy kept on the
/// device, then fetched again; a blog without one has no mark, and the name
/// stands at the edge by itself.
struct SiteMark: View {
    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

nonisolated enum SiteIcon {
    static func address(for site: String) -> URL? {
        guard !site.isEmpty, let base = URL(string: site), base.scheme == "https" || base.scheme == "http" else { return nil }
        return base.appendingPathComponent("assets/images/favicon.png")
    }

    /// One file per blog, by its host, among what the system may clear.
    private static func file(for site: String) -> URL? {
        guard let host = URL(string: site)?.host(), !host.isEmpty else { return nil }
        let name = "site-mark-" + host.replacingOccurrences(of: "[^A-Za-z0-9.-]", with: "_", options: .regularExpression) + ".png"
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(name)
    }

    static func kept(for site: String) -> UIImage? {
        guard let file = file(for: site), let data = try? Data(contentsOf: file) else { return nil }
        return UIImage(data: data)
    }

    @concurrent static func fetch(for site: String) async -> UIImage? {
        guard let address = address(for: site) else { return nil }
        var request = URLRequest(url: address)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        if let file = file(for: site) { try? data.write(to: file, options: .atomic) }
        return image
    }
}

/// One entry of the menu: its mark and its word.
struct Tile: View {
    let entry: MenuEntry
    var highlighted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
        VStack(spacing: 8) {
            Image(systemName: entry.symbol)
                .font(.system(size: 21, weight: .regular))
                .frame(height: 24)
            Text(verbatim: entry.short)
                .font(.ui(13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background { if highlighted { shape.fill(.tint.opacity(0.12)) } else { shape.fill(Theme.card) } }
        .overlay { if highlighted { shape.strokeBorder(.tint, lineWidth: 1) } else { shape.strokeBorder(Theme.line, lineWidth: 1) } }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(entry.name))
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ContentView()
}

extension Color {
    /// `#rrggbb` or `#rgb`, the way a palette writes a colour; anything
    /// else -- rgb(), a name, nothing -- is nil.
    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        guard digits.hasPrefix("#") else { return nil }
        digits.removeFirst()
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xff) / 255,
                  green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
    }
}
