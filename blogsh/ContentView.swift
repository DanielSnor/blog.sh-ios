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
    /// Something begun and not finished, opened from the first screen:
    /// the editor it waits in, straight away.
    @State private var resumed: Begun.What?
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
    @State private var showingWaiting = false
    /// The first screen is being asked for: one asking at a time.
    @State private var loading = false
    /// A pairing code that came in as a link, opened from another app.
    @State private var incoming: Incoming?
    // One counting at a time: it is the slowest thing the first screen asks.
    @State private var counting = false
    // The blogs, and the one that is open: its name, its colour and its limit
    // are kept from its last answer, so the app opens as that blog before
    // the server has said anything.
    private var blogs = Blogs.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $column) {
            home(roomy: false)
                // The system's key for the column is taken out everywhere:
                // where there is room for two columns the app puts its own
                // there, in the accent.
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if twoColumns { MenuKey(action: putMenuAway) }
                    }
                }
                .modifier(ColumnForType())
        } detail: {
            // A stack of its own: the screens push further screens (a post,
            // then its properties), and the split view's detail column does
            // not push by itself.
            NavigationStack {
                Group {
                    switch resumed {
                    case .text(let slug): TextEditView(slug: slug)
                    case .language(let slug, let lang): TranslateView(slug: slug, lang: lang)
                    case .new, nil: EmptyView()
                    }
                    if resumed == nil || resumed == .new { switch selection {
                    case .add: ComposeView()
                    case .post: PostPickerView(languages: otherLanguages)
                    case .queue: QueueView(languages: otherLanguages)
                    case .browse: ArchiveView(languages: otherLanguages, baseURL: identity?.site.url ?? "",
                                              initialState: archiveState, searching: archiveSearching)
                    case .restore: TrashView()
                    case .rebuild: SiteView()
                    case nil:
                        // A wide screen held upright is one large page: with
                        // nothing open, the menu is that page.
                        if single {
                            home(roomy: true)
                        } else {
                            EmptyNote(symbol: "terminal", title: "What do you want to do?", room: .welcome)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Theme.paper.ignoresSafeArea())
                        }
                    } }
                }
                // ...and from an open screen the way back to it is here,
                // where a phone has it. Beside the menu too, on a screen
                // wide enough for both: the way back there closes the open
                // screen and leaves the menu with nothing beside it.
                .toolbar {
                    if sizeClass == .regular && (selection != nil || resumed != nil) {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: close) { Image(systemName: "chevron.backward") }
                                .tint(Theme.accent)
                                .accessibilityLabel(Text(verbatim: "./blog.sh"))
                        }
                    }
                }
            }
            .id(visit)
            .toolbar(removing: .sidebarToggle)
            // With the menu put out of the way, every screen of the stack
            // carries the key that brings it back.
            .environment(\.showMenu, bringMenuBack)
        }
        // What was just done, and the site being brought up to date: under
        // whichever screen is open.
        .safeAreaInset(edge: .bottom, spacing: 0) { HeraldStrip() }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView() }
        }
        // A blog's settings are behind its row there: what was changed in
        // them is asked of the server again when the list closes.
        .sheet(isPresented: $showingBlogs, onDismiss: { Task { await load() } }) {
            NavigationStack { BlogsView() }
        }
        // The posts kept on the device for a silent server: a list of
        // their own, from which one can go back into the form.
        .sheet(isPresented: $showingWaiting, onDismiss: { Task { await loadGlance() } }) {
            NavigationStack { WaitingView(write: { open(.add) }) }
        }
        // A code read elsewhere -- a camera app, a note -- opens the app
        // with it: the way in for a blog, with the code already there.
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "blogsh" else { return }
            showingBlogs = false
            showingSettings = false
            showingWaiting = false
            incoming = Incoming(text: url.absoluteString)
        }
        .sheet(item: $incoming, onDismiss: { Task { await load() } }) { one in
            NavigationStack {
                AddBlogView(initialCode: one.text, close: { incoming = nil })
                    // Opened by a link, the screen stands on nothing to go back to.
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { incoming = nil } }
                    }
            }
        }
        .task { await load() }
        // The accent that is worn -- the blog's own, as /write/ wears it,
        // until something else is chosen: every control of the app, the
        // sheets included.
        .tint(Theme.accent)
        // The icon on the home screen wears the accent of the blog the app
        // was last opened with: it is set when the app comes to the front,
        // never while one is switching blogs inside it -- the system says
        // so every time an icon changes, and once a visit is enough. It
        // only changes an icon for an app that is in front, and not in the
        // very moment it comes there.
        .task(id: phase == .active) {
            guard phase == .active else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            AppIcon.follow(blogs.current?.accentLight ?? "")
        }
        // Off the screen the app is asked nothing, and the system may stop
        // it at any moment: the connection it keeps to the server is closed
        // now, in order, rather than left to die there unannounced.
        .onChange(of: phase) {
            if phase == .background { Engine.hangUp() }
            // Back in front with a server that was silent: asked again,
            // unprompted -- the device has most likely been somewhere else.
            if phase == .active, offline { Task { await load() } }
        }
        // A server heard from again by some other screen's call: what
        // waits for it goes now, and a first screen that never loaded
        // loads. Nothing else would notice -- every other asking-again
        // above is for a server still silent.
        .onChange(of: offline) { _, now in
            guard !now, !loading else { return }
            Task { if identity == nil { await load() } else { await sendWaiting() } }
        }
        // ...and so is it the moment the device finds a network.
        .task {
            // Watched from the start, so that it is known by the time a
            // picture is chosen.
            _ = NetworkWatch.hasNetwork
            for await _ in NetworkWatch.comes where offline { await load() }
        }
        // Another blog: nothing of the last one stays on the screen, and its
        // own name and colour are there before its server answers.
        .onChange(of: blogs.currentID) {
            identity = nil
            identityProblem = nil
            glance = nil
            selection = nil
            resumed = nil
            visit += 1
            column = .sidebar
            TagStore.shared.reset()
            // A build owed to the blog that was open waits for it; one
            // that waited for this blog is owed again.
            Herald.shared.opened(blogs.currentID)
            Task { await load() }
        }
        // Upright there is room for one column: the screen that is open, or
        // the menu as a page of its own when none is. On its side there is
        // room for both.
        .onGeometryChange(for: Bool.self) { $0.size.width < $0.size.height } action: { now in
            upright = now
            columns = now ? .detailOnly : .all
        }
        // ...and it stays one, whoever asks for two. Said once, at the turn,
        // it did not hold: the system finishes its own turning after this
        // one, and with a screen open it now and then put the menu back
        // beside it -- a narrow menu next to the menu as a page. A swipe
        // from the edge pulls the menu out the same way. So the one column
        // is kept, not only set.
        .onChange(of: columns) { _, now in
            if single, now != .detailOnly { columns = .detailOnly }
        }
        .onChange(of: single) { _, now in
            if now, columns != .detailOnly { columns = .detailOnly }
        }
        // ...and whenever a screen has changed the blog: on a wide screen
        // the menu stands beside it and is never come back to.
        .onChange(of: Desk.shared.writes) {
            Task { await loadGlance() }
        }
        // What changed on the way back is on the first screen again.
        .onChange(of: column) { _, now in
            if now == .sidebar { Task { await loadGlance() } }
        }
    }

    /// A wide screen held upright: one column, and the menu a page in it.
    private var single: Bool { upright && sizeClass == .regular }

    /// A wide screen on its side: room for the menu and a screen beside it.
    private var twoColumns: Bool { sizeClass == .regular && !single }

    private func putMenuAway() {
        withAnimation { columns = .detailOnly }
    }

    /// The way back to the menu, for the screens beside which it was put away.
    private var bringMenuBack: (@MainActor () -> Void)? {
        guard twoColumns, columns == .detailOnly else { return nil }
        return { withAnimation { columns = .all } }
    }

    /// The open blog's server did not answer the last time it was asked --
    /// this screen, or any other: the blog is offline until it does.
    private var offline: Bool { Reach.shared.isOffline(blogs.current) }

    /// What the first screen says of a silent server, whichever screen found it so.
    private var offlineWords: String {
        EngineError.unreachable(blogs.current?.host.trimmingCharacters(in: .whitespaces) ?? "", "").localizedDescription
    }

    /// The first screen, as the column beside the open one or as a page of its own.
    private func home(roomy: Bool) -> some View {
        HomeView(name: identity?.site.name ?? blogs.current?.label ?? "", claim: identity?.site.claim ?? blogs.current?.claim ?? "",
                 url: identity?.site.url ?? blogs.current?.url ?? "",
                 switchBlog: { showingBlogs = true },
                 identity: identity, problem: offline ? offlineWords : identityProblem, glance: glance,
                 offline: offline, retry: load,
                 waiting: waiting, sending: waiting.contains { $0.id == Outbox.shared.sending },
                 openWaiting: { showingWaiting = true },
                 begun: begun,
                 facts: blogs.current?.facts,
                 current: sizeClass == .regular && !roomy ? selection : nil,
                 roomy: roomy,
                 open: open,
                 resume: resume)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            // The menu has no bar over it, only the two keys: under a mouse
            // the bar's own ground and rule would light up above the name.
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable { await load() }
    }

    /// Back to the menu from an open screen, on a wide screen: upright,
    /// where the menu is then the page, and on its side, where the place
    /// beside the menu is left empty -- and the menu, if it was put out of
    /// the way, is brought back, or nothing would be left to choose from.
    private func close() {
        selection = nil
        resumed = nil
        if twoColumns, columns == .detailOnly { columns = .all }
        visit += 1
        Task { await loadGlance() }
    }

    /// What was begun on this device for the open blog and not finished.
    /// Read whenever the screen is drawn: it is a look into the device's
    /// own keeping, and the desk says when that changed.
    private var begun: [Begun] {
        _ = Desk.shared.changes
        guard let blog = blogs.currentID else { return [] }
        return Begun.all(for: blog)
    }

    /// The posts kept on this device for the open blog until its server answers.
    private var waiting: [Waiting] {
        _ = Desk.shared.changes
        guard let blog = blogs.currentID else { return [] }
        return WaitingRoom.all(for: blog)
    }

    /// The server has just answered: what waited for it goes now, as
    /// drafts, and the first screen counts its drafts again.
    private func sendWaiting() async {
        guard let blog = blogs.currentID, !WaitingRoom.all(for: blog).isEmpty else { return }
        let sent = await Outbox.shared.sendAll(for: blog)
        // Said, and counted, only on the blog they went to.
        guard sent > 0, blog == blogs.currentID else { return }
        Herald.shared.say(String(localized: "Sent to the blog as drafts: \(sent)"))
        await loadGlance()
    }

    /// Straight to where it waits: the new post's form, or the editor of
    /// the post -- or of its language -- that was being changed.
    private func resume(_ one: Begun) {
        guard one.what != .new else { return open(.add) }
        visit += 1
        selection = nil
        resumed = one.what
        column = .detail
        if upright { columns = .detailOnly }
    }

    private func open(_ entry: MenuEntry, state: ArchiveView.StateFilter? = nil, searching: Bool = false) {
        // The form that is asked for is the one already open beside the
        // menu: it stays as it is. Built again it would come back with its
        // words, which are kept, and without its pictures, which are not.
        // Only where it is seen to be open: on a narrow screen the way
        // back to the menu was a leaving, and the form opens afresh.
        if twoColumns, entry == .add, selection == .add, resumed == nil, !Desk.shared.holdsHanded {
            column = .detail
            return
        }
        archiveState = state
        archiveSearching = searching
        resumed = nil
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
        loading = true
        defer { loading = false }
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
                if let palette = answer.site.palette {
                    blog.tonesLight = palette.light
                    blog.tonesDark = palette.dark
                }
            }
            glance = Self.glance(queue: answers[1], drafts: answers[2])
            // The numbers under the search come after the screen itself:
            // counting the archive takes the engine seconds.
            Task {
                await sendWaiting()
                await loadFacts(whole: true)
            }
        } catch EngineError.notConfigured {
            identity = nil
            glance = nil
            identityProblem = String(localized: "Nothing to connect to yet — the name above leads to the blogs and their settings.")
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
        guard identity != nil, !offline,
              let answers = try? await Engine.shared.answers(to: [["queue"], ["list", "--drafts"]]),
              asked == blogs.currentID else { return }
        glance = Self.glance(queue: answers[0], drafts: answers[1]) ?? glance
        await loadFacts(whole: false)
    }

    /// The blog in numbers: the archive counted (`stats`), and what the
    /// trash and the versions hold -- `empty` asked without `--yes` says
    /// how much and touches nothing. Kept with the blog, so the next launch
    /// shows them at once. On the way back from a screen only the two that
    /// a screen can have changed are asked again; the archive is counted
    /// when the first screen is loaded whole.
    private func loadFacts(whole: Bool) async {
        let asked = blogs.currentID
        guard identity != nil, !counting else { return }
        counting = true
        defer {
            counting = false
            // Another blog was opened while this one was being counted,
            // and its own counting was turned away at the door: it is
            // counted now.
            if asked != blogs.currentID { Task { await loadFacts(whole: true) } }
        }
        var facts = blogs.current?.facts ?? Facts()
        let whole = whole || blogs.current?.facts == nil
        let commands: [[String]] = (whole ? [["stats"]] : []) + [["empty", "trash"], ["empty", "versions"]]
        guard let answers = try? await Engine.shared.answers(to: commands),
              answers.count == commands.count, asked == blogs.currentID else { return }
        if whole {
            guard let stats: StatsAnswer = try? Engine.decode(answers[0]) else { return }
            facts.posts = stats.posts.total
            facts.since = String(stats.span.first?.prefix(4) ?? "")
            facts.words = stats.words.total
            facts.readingHours = stats.words.readingHours
            facts.tags = stats.tags.unique
            facts.media = stats.media.files
            facts.mediaBytes = stats.media.bytes
        }
        if let trash: HeldAnswer = try? Engine.decode(answers[answers.count - 2]) {
            facts.trash = trash.count
            facts.trashBytes = trash.bytes
        }
        if let versions: HeldAnswer = try? Engine.decode(answers[answers.count - 1]) {
            facts.versions = versions.count
            facts.versionsBytes = versions.bytes
        }
        blogs.update { $0.facts = facts }
    }

    /// An engine too old to answer one of the two has no cards, not an error.
    private static func glance(queue: Data, drafts: Data) -> Glance? {
        guard let waiting: QueueAnswer = try? Engine.decode(queue),
              let unpublished: ListAnswer = try? Engine.decode(drafts) else { return nil }
        return Glance(queue: waiting.queue, drafts: unpublished.posts.filter { !$0.scheduled }.count)
    }
}

/// A link that opened the app, kept until its screen has taken it.
struct Incoming: Identifiable {
    let id = UUID()
    let text: String
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
    /// The blog's server is silent: what needs it is shown out of reach,
    /// and writing a new post -- which does not -- stays as it is.
    var offline = false
    /// Asks the server again.
    var retry: () async -> Void = {}
    /// The posts kept on this device until the server answers, and
    /// whether one of them is on its way just now.
    var waiting: [Waiting] = []
    var sending = false
    var openWaiting: () -> Void = {}
    /// What was begun on this device and not finished: each a way back to it.
    var begun: [Begun] = []
    /// The blog in numbers, once it has counted itself.
    let facts: Facts?
    /// The entry whose screen is open beside this one, where there is a beside.
    let current: MenuEntry?
    /// A page of its own on a wide screen: two thirds of its width, and
    /// everything on it larger by the same measure.
    var roomy = false
    let open: (MenuEntry, ArchiveView.StateFilter?, Bool) -> Void
    var resume: (Begun) -> Void = { _ in }

    @State private var mark: UIImage?
    @State private var trying = false

    private var k: CGFloat { roomy ? 1.35 : 1 }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8 * k), count: 3) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The blog's own mark beside its name, as /write/ wears it: the name
                // and the claim share one left edge, the mark stands before both.
                // The whole of it is a key: the other blogs are behind it.
                Button(action: switchBlog) {
                    HStack(alignment: .center, spacing: 14 * k) {
                        if let mark { SiteMark(image: mark) }
                        VStack(alignment: .leading, spacing: 2 * k) {
                            Text(verbatim: name.isEmpty ? "blog.sh" : name)
                                .font(.display(34 * k))
                                .textCase(.lowercase)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .accessibilityAddTraits(.isHeader)
                            if !claim.isEmpty { ClaimText(claim: claim) }
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 13 * k, weight: .semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityHint(Text("Blogs"))
                HStack(spacing: 8) {
                    Rectangle().fill(.tint).frame(width: 14 * k, height: 1)
                    Text(verbatim: "./blog.sh \(offline ? String(localized: "offline") : identity?.engine ?? "")")
                        .engineLabel(12 * k)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 14 * k)

                if offline {
                    // Said plainly, with the one thing there is to do about it.
                    HStack(alignment: .firstTextBaseline, spacing: 8 * k) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 13 * k, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .accessibilityHidden(true)
                        Text(verbatim: problem ?? "")
                            .font(.ui(14 * k))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 14 * k)
                    Button {
                        guard !trying else { return }
                        Task {
                            trying = true
                            await retry()
                            trying = false
                        }
                    } label: {
                        Card(capsule: true) {
                            if trying {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13 * k, weight: .semibold))
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                            Text("Try again").engineLabel(12 * k).wordUnderPointer(Theme.muted)
                        }
                    }
                    .buttonStyle(PressStyle())
                    .padding(.top, 10 * k)
                } else if identity == nil {
                    if let problem {
                        Text(verbatim: problem)
                            .font(.ui(14 * k))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 14 * k)
                    } else {
                        ProgressView().padding(.top, 14)
                    }
                }

                // What waits, in the order it wants a hand: the drafts on
                // the blog, then the writing kept on this device from the
                // last time -- said here, or nobody knows of it before
                // opening the form it waits in -- and last the queue, which
                // goes out by itself.
                if glance != nil || !begun.isEmpty || !waiting.isEmpty {
                    VStack(spacing: 8 * k) {
                        if let glance {
                            Button { open(.browse, .draft, false) } label: { draftsCard(glance) }
                                .outOfReach(offline)
                        }
                        ForEach(begun) { one in
                            // A new post is written on the device; changes to
                            // one the blog has need its text from the server.
                            Button { resume(one) } label: { begunCard(one) }
                                .outOfReach(offline && one.what != .new)
                        }
                        // What is finished and only waits for the server.
                        if !waiting.isEmpty {
                            Button(action: openWaiting) { waitingCard }
                        }
                        if let glance {
                            Button { open(.queue, nil, false) } label: { queueCard(glance) }
                                .outOfReach(offline)
                        }
                    }
                    .buttonStyle(PressStyle())
                    .padding(.top, 18 * k)
                }

                LazyVGrid(columns: columns, spacing: 8 * k) {
                    ForEach(MenuEntry.allCases) { entry in
                        Button { open(entry, nil, false) } label: {
                            Tile(entry: entry, highlighted: current == entry)
                        }
                        .outOfReach(offline && entry != .add)
                    }
                }
                .buttonStyle(PressStyle())
                .padding(.top, (glance == nil && begun.isEmpty && waiting.isEmpty ? 22 : 10) * k)

                Button { open(.browse, nil, true) } label: {
                    Card(capsule: true) {
                        // A glass, not the terminal's own key for it: a slash says
                        // "search" only to somebody who knows the terminal.
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13 * k, weight: .semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("Search the archive").engineLabel(12 * k).wordUnderPointer(Theme.muted)
                    }
                }
                .buttonStyle(PressStyle())
                .outOfReach(offline)
                .padding(.top, 14 * k)

                // The blog itself, as a reader has it.
                if let site = URL(string: url), ["http", "https"].contains(site.scheme?.lowercased() ?? ""), site.host != nil {
                    Link(destination: site) {
                        Card(capsule: true) {
                            Image(systemName: "safari")
                                .font(.system(size: 13 * k, weight: .semibold))
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                            Text("Open the blog in the browser").engineLabel(12 * k).wordUnderPointer(Theme.muted)
                        }
                    }
                    .buttonStyle(PressStyle())
                    .padding(.top, 8 * k)
                }

                if let facts { factLines(facts).padding(.top, 26 * k) }
            }
            .padding(.horizontal, roomy ? 0 : Theme.gutter)
            .padding(.top, roomy ? 40 : 4)
            .padding(.bottom, 24)
            .modifier(TwoThirds(on: roomy))
            .environment(\.scale, k)
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

    /// The blog in numbers, in the engine's voice: what the archive holds,
    /// and what waits in the trash and among the versions -- those two are
    /// keys, to the screen that empties them.
    private func factLines(_ facts: Facts) -> some View {
        // A line whose number is nought is not said at all, as on the
        // blog's own pages: there is nothing in it to read, and behind the
        // last two nothing to empty.
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14 * k, verticalSpacing: 7 * k) {
            if facts.posts > 0 {
                FactLine(label: String(localized: "facts.posts", defaultValue: "posts"), value: facts.posts.formatted(),
                         detail: facts.since.isEmpty ? nil : String(localized: "facts.since", defaultValue: "since \(facts.since)"))
            }
            if facts.words > 0 {
                FactLine(label: String(localized: "facts.words", defaultValue: "words"), value: facts.words.formatted(),
                         detail: facts.readingHours >= 1 ? String(localized: "facts.reading", defaultValue: "\(Self.hours(facts.readingHours)) of reading") : nil)
            }
            if facts.tags > 0 {
                FactLine(label: String(localized: "facts.tags", defaultValue: "tags"), value: facts.tags.formatted(), detail: nil)
            }
            if facts.media > 0 {
                FactLine(label: String(localized: "facts.media", defaultValue: "media"), value: facts.media.formatted(),
                         detail: Self.size(facts.mediaBytes))
            }
            if facts.trash > 0 {
                FactLine(label: String(localized: "facts.trash", defaultValue: "in the trash"), value: facts.trash.formatted(),
                         detail: Self.size(facts.trashBytes), action: offline ? nil : { open(.restore, nil, false) })
            }
            if facts.versions > 0 {
                FactLine(label: String(localized: "facts.versions", defaultValue: "versions"), value: facts.versions.formatted(),
                         detail: Self.size(facts.versionsBytes), action: offline ? nil : { open(.restore, nil, false) })
            }
        }
        // The block stands in the middle as one: its widest line centred,
        // the others keeping their places under it.
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private static func hours(_ hours: Double) -> String {
        Measurement(value: hours.rounded(), unit: UnitDuration.hours)
            .formatted(.measurement(width: .wide, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private static func size(_ bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }

    /// The next post to go out, and how many wait in all.
    private func queueCard(_ glance: Glance) -> some View {
        Card {
            Image(systemName: "clock").font(.system(size: 17 * k)).foregroundStyle(.tint)
            if let next = glance.queue.first {
                let when = ISO8601DateFormatter.engine.date(from: next.date).map(RowDate.soon) ?? ""
                Text(verbatim: "\(next.title.isEmpty ? next.slug : next.title) · \(when)")
                    .font(.ui(15 * k, weight: .medium))
                    .tone(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                CountBadge(count: glance.queue.count)
            } else {
                Text("Nothing scheduled").font(.ui(15 * k)).tone(Theme.muted)
            }
        }
    }

    /// One thing begun: what it is and when it was last written in, and
    /// under that what it is called.
    private func begunCard(_ one: Begun) -> some View {
        Card(warning: true) {
            Image(systemName: "square.and.pencil").font(.system(size: 17 * k)).tone(Theme.danger)
            VStack(alignment: .leading, spacing: 2 * k) {
                (kind(one) + Text(verbatim: " · \(one.at.spoken)"))
                    .font(.ui(12 * k, weight: .medium))
                    .tone(Theme.danger)
                    .lineLimit(1)
                if !one.title.isEmpty {
                    Text(verbatim: one.title)
                        .font(.ui(15 * k, weight: .medium))
                        .tone(Theme.ink)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 12 * k, weight: .semibold))
                .tone(Theme.muted)
                .accessibilityHidden(true)
        }
    }

    /// The posts kept on the device: how many, and the first by name.
    private var waitingCard: some View {
        Card(warning: true) {
            if sending {
                ProgressView().controlSize(.small).frame(width: 20 * k)
            } else {
                Image(systemName: "tray.and.arrow.up").font(.system(size: 17 * k)).foregroundStyle(Theme.danger)
            }
            VStack(alignment: .leading, spacing: 2 * k) {
                Text(sending ? "Sending…" : "Waiting to be sent")
                    .font(.ui(12 * k, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .lineLimit(1)
                if let first = waiting.first, !first.headline.isEmpty {
                    Text(verbatim: first.headline)
                        .font(.ui(15 * k, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            CountBadge(count: waiting.count)
        }
    }

    private func kind(_ one: Begun) -> Text {
        switch one.what {
        case .new: Text("Unsent new post")
        case .text: Text("Unsaved changes")
        case .language(_, let lang): Text("Unsaved translation, \(Locale.current.localizedString(forLanguageCode: lang) ?? lang)")
        }
    }

    private func draftsCard(_ glance: Glance) -> some View {
        Card {
            Image(systemName: "pencil").font(.system(size: 17 * k)).foregroundStyle(.tint)
            if glance.drafts > 0 {
                Text("Drafts in progress").font(.ui(15 * k, weight: .medium)).wordUnderPointer(Theme.ink)
                Spacer(minLength: 6)
                CountBadge(count: glance.drafts)
            } else {
                Text("No drafts in progress").font(.ui(15 * k)).tone(Theme.muted)
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
    @Environment(\.scale) private var scale

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: 56 * scale, height: 56 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous))
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

/// The claim under the blog's name, in the largest size that lets every
/// line of it stand whole: a short claim speaks up, a long one lowers its
/// voice. A claim the blog broke into lines keeps them; one too long even
/// for the smallest size wraps at it.
struct ClaimText: View {
    let claim: String
    @Environment(\.scale) private var scale

    var body: some View {
        let lines = claim.split(separator: "\n").map(String.init)
        ViewThatFits(in: .horizontal) {
            block(lines, size: 20)
            block(lines, size: 19)
            block(lines, size: 18)
            block(lines, size: 17)
            block(lines, size: 16)
            block(lines, size: 15)
            block(lines, size: 14)
            block(lines, size: 13)
            block(lines, size: 13, wraps: true)
        }
    }

    private func block(_ lines: [String], size: CGFloat, wraps: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .font(.ui(size * scale))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(wraps ? nil : 1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: !wraps, vertical: true)
            }
        }
    }
}

/// One number of the blog: what is counted, how many, and what else there
/// is to say of it. With an action the line is a key, and says so by the
/// accent on its number.
struct FactLine: View {
    let label: String
    let value: String
    let detail: String?
    var action: (() -> Void)?
    @Environment(\.scale) private var scale

    var body: some View {
        GridRow {
            Text(verbatim: label)
                .engineLabel(12 * scale)
                .foregroundStyle(Theme.muted)
            Group {
                if let action {
                    Button(action: action) { words(tappable: true) }.buttonStyle(PressStyle())
                } else {
                    words(tappable: false)
                }
            }
        }
    }

    /// The number and what is said to it on one line; where large type
    /// leaves the line too short for both, the second under the first.
    private func words(tappable: Bool) -> some View {
        let number = Text(verbatim: value)
            .font(.mono(12 * scale))
            .foregroundStyle(tappable ? AnyShapeStyle(.tint) : AnyShapeStyle(Theme.ink))
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                number
                if let detail { said(" · " + detail) }
            }
            VStack(alignment: .leading, spacing: 1) {
                number
                if let detail { said(detail) }
            }
        }
        .lineLimit(1)
        .contentShape(Rectangle())
    }

    private func said(_ words: String) -> some View {
        Text(verbatim: words)
            .font(.mono(12 * scale, bold: false))
            .foregroundStyle(Theme.muted)
    }
}

/// Two thirds of the screen's width, in its middle: the first screen as a
/// page of its own on a wide screen held upright.
/// Type the app enlarges by its own hand needs a wider column to stand
/// in; where the system enlarges it, the column is the system's too.
private struct ColumnForType: ViewModifier {
    func body(content: Content) -> some View {
        if TypeScale.ownHand {
            content.navigationSplitViewColumnWidth(ideal: 320 * (1 + (TypeScale.shared.factor - 1) * 0.6))
        } else {
            content
        }
    }
}

private struct TwoThirds: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            // The outer frame keeps the scroll view as wide as its place: left
            // to its content's width it would measure itself against itself.
            content
                .containerRelativeFrame(.horizontal) { width, _ in width * 2 / 3 }
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

/// One entry of the menu: its mark and its word.
struct Tile: View {
    let entry: MenuEntry
    var highlighted = false
    @Environment(\.scale) private var scale
    @Environment(\.outOfReach) private var out

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.corner * scale, style: .continuous)
        // Out of reach a tile is not the open one either: no fill, the plain outline.
        let highlighted = highlighted && !out
        VStack(spacing: 8 * scale) {
            // A tile is an action: its mark is in the accent, its word in
            // ink -- as the cards over the tiles have it.
            Image(systemName: entry.symbol)
                .font(.system(size: 21 * scale, weight: .regular))
                .frame(height: 24 * scale)
                .foregroundStyle(.tint)
            Text(verbatim: entry.short)
                .font(.ui(13 * scale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .wordUnderPointer(Theme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16 * scale)
        .padding(.bottom, 12 * scale)
        .background { if out { shape.fill(.clear) } else if highlighted { shape.fill(.tint.opacity(0.12)) } else { shape.fill(Theme.card) } }
        .overlay { if highlighted { shape.strokeBorder(.tint, lineWidth: 1) } else { KeyOutline(shape: shape) } }
        .contentShape(shape)
        .underPointer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(entry.name))
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ContentView()
}
