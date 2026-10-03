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
    // The site's accent, kept from the last answer so the app opens in
    // the blog's colour before the server has said anything.
    @AppStorage("site.accent.light") private var accentLight = ""
    @AppStorage("site.accent.dark") private var accentDark = ""
    @Environment(\.colorScheme) private var colorScheme

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
            // The header sits right under the title, as the terminal's second
            // line sits under its first: the list's own top margin is dropped.
            .contentMargins(.top, 0, for: .scrollContent)
            // The terminal's first line is the title: the command and the
            // engine's version, in the type the terminal sets them in.
            .navigationTitle(Text(verbatim: "./blog.sh"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text(verbatim: "./blog.sh").bold()
                        Text(identity?.engine ?? "").foregroundStyle(.secondary)
                    }
                    .font(.callout.monospaced())
                }
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
                case .browse: ArchiveView(languages: otherLanguages, baseURL: identity?.site.url ?? "")
                case .restore: TrashView()
                case .rebuild: SiteView()
                case .some(let entry): PlaceholderView(entry: entry)
                case nil: ContentUnavailableView("What do you want to do?", systemImage: "terminal")
                }
            }
        }
        // The blog's own accent, as /write/ wears it: every control of the
        // app, the sheets included. Nothing set, or not a hex colour, and
        // the system's stays.
        .tint(Color(hex: colorScheme == .dark ? accentDark : accentLight))
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
            let answer: VersionAnswer = try await Engine.shared.call(["version"])
            identity = answer
            identityProblem = nil
            if let accent = answer.site.accent {
                accentLight = accent.light
                accentDark = accent.dark
            }
        } catch EngineError.notConfigured {
            identity = nil
            identityProblem = String(localized: "No server yet — set one up under the gear.")
        } catch {
            // Called off: the header keeps what it was showing.
            if error.isCalledOff { return }
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

extension Color {
    /// `#rrggbb` or `#rgb`, the way a palette writes a colour; anything
    /// else -- rgb(), a name, nothing -- is nil, and a nil tint is the
    /// system's own.
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
