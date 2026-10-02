import SwiftUI

/// The wizard's main menu, row for row: what `./blog.sh` with no command
/// shows. The order, the words and the number of entries are the engine's
/// (locales/*.yml, wizard_menu_*); the app adds nothing to it. Settings
/// are not a menu entry -- the terminal has none -- so they sit in the
/// toolbar.
enum MenuEntry: String, CaseIterable, Identifiable {
    case add, post, queue, browse, restore, rebuild

    var id: String { rawValue }

    /// The entry as the wizard prints it: a name, then what it leads to.
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

    var detail: LocalizedStringKey? {
        switch self {
        case .add: nil
        case .post: "edit the text, its properties and the actions on it"
        case .queue: "reorder, publish now, remove"
        case .browse: "filters, search, preview"
        case .restore: "restore a deleted post"
        case .rebuild: "rebuild and deploy after a settings change"
        }
    }

    /// The digit the terminal's quick pick uses, kept as a visible cue.
    var number: Int { MenuEntry.allCases.firstIndex(of: self)! + 1 }
}

struct ContentView: View {
    @State private var selection: MenuEntry?
    @State private var showingSettings = false
    @State private var identity: VersionAnswer?
    @State private var identityProblem: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    IdentityHeader(identity: identity, problem: identityProblem)
                        .listRowBackground(Color.clear)
                }
                Section("What do you want to do?") {
                    ForEach(MenuEntry.allCases) { entry in
                        MenuRow(entry: entry)
                            .tag(entry)
                    }
                }
            }
            .navigationTitle("blog.sh")
            // The header below is the title, the way it is in the terminal.
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: { Task { await loadIdentity() } }) {
                NavigationStack { SettingsView() }
            }
            .task { await loadIdentity() }
            .refreshable { await loadIdentity() }
        } detail: {
            // A stack of its own: the screens push further screens (a post,
            // then its properties), and the split view's detail column does
            // not push by itself.
            NavigationStack {
                switch selection {
                case .add: ComposeView(maxMb: identity?.maxMb ?? 24)
                case .post: PostPickerView(languages: otherLanguages)
                case .queue: QueueView()
                case .browse: ArchiveView()
                case .restore: TrashView()
                case .rebuild: SiteView()
                case .some(let entry): PlaceholderView(entry: entry)
                case nil: ContentUnavailableView("What do you want to do?", systemImage: "terminal")
                }
            }
        }
    }

    /// The languages the site publishes beyond its own.
    private var otherLanguages: [String] {
        guard let identity else { return [] }
        return identity.site.locales.filter { $0 != identity.site.lang }
    }

    /// The identity block, from the server: `version --json`. Without a
    /// server set up the header says so and the settings are one tap away.
    private func loadIdentity() async {
        do {
            identity = try await Engine.shared.call(["version"])
            identityProblem = nil
        } catch EngineError.notConfigured {
            identity = nil
            identityProblem = String(localized: "No server yet — set one up under the gear.")
        } catch {
            identity = nil
            identityProblem = error.localizedDescription
        }
    }
}

/// What the header says above every screen of the terminal: which engine,
/// which site, where it is.
struct IdentityHeader: View {
    let identity: VersionAnswer?
    let problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("./blog.sh").bold()
                Text(identity?.engine ?? "").foregroundStyle(.secondary)
            }
            if let identity {
                // One run of text, so it wraps the way the terminal wraps it.
                (Text(identity.site.name).bold() + Text(identity.site.claim.isEmpty ? "" : " — \(identity.site.claim)"))
                if !identity.site.url.isEmpty {
                    Text(identity.site.url).foregroundStyle(.secondary)
                }
            } else if let problem {
                Text(problem).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .font(.callout.monospaced())
    }
}

struct MenuRow: View {
    let entry: MenuEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(entry.number)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Until a screen is built, its name and nothing else -- so every entry
/// leads somewhere and the shape of the app can be judged before its
/// contents exist.
struct PlaceholderView: View {
    let entry: MenuEntry

    var body: some View {
        ContentUnavailableView(entry.name, systemImage: "hammer")
            .navigationTitle(entry.name)
    }
}

#Preview {
    ContentView()
}
