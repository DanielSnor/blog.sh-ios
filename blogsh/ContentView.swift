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

/// What the header says above every screen of the terminal: which engine,
/// which site, where it is. Until the connection exists it shows what a
/// fresh install would.
struct SiteIdentity {
    var engineVersion = "1.10"
    var siteName = "./blog.sh"
    var tagline = "just ./blog.sh — no database • no gems • no admin"
    var baseURL = "https://blogsh.app"

    static let sample = SiteIdentity()
}

struct ContentView: View {
    @State private var selection: MenuEntry?
    @State private var showingSettings = false
    private let identity = SiteIdentity.sample

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    IdentityHeader(identity: identity)
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
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
            }
        } detail: {
            switch selection {
            case .browse: ArchiveView()
            case .some(let entry): PlaceholderView(entry: entry)
            case nil: ContentUnavailableView("What do you want to do?", systemImage: "terminal")
            }
        }
    }
}

struct IdentityHeader: View {
    let identity: SiteIdentity

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("./blog.sh").bold()
                Text(identity.engineVersion).foregroundStyle(.secondary)
            }
            // One run of text, so it wraps the way the terminal wraps it.
            (Text(identity.siteName).bold() + Text(" — \(identity.tagline)"))
            Text(identity.baseURL).foregroundStyle(.secondary)
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

/// The one thing the terminal never asks for: where the blog is. Filled
/// in when the connection exists; the fields are the ones it will need.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Host", value: "—")
                LabeledContent("User", value: "—")
                LabeledContent("Installation", value: "—")
            }
            Section("Key") {
                Text("The app's own key, made on this device, goes into the server's authorized_keys. Not yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

#Preview {
    ContentView()
}
