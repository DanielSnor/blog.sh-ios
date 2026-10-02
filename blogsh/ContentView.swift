import SwiftUI

/// The three screens somebody reads before acting, in the order the
/// engine's own wizard puts them, plus the one place the app is set up.
/// On an iPad they sit in the sidebar; on a phone the split view folds
/// into a stack by itself.
enum Screen: String, CaseIterable, Identifiable {
    case archive, drafts, queue, settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .archive: "Archive"
        case .drafts: "Drafts"
        case .queue: "Queue"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .archive: "books.vertical"
        case .drafts: "pencil.and.list.clipboard"
        case .queue: "calendar.badge.clock"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var selection: Screen? = .archive

    var body: some View {
        NavigationSplitView {
            List(Screen.allCases, selection: $selection) { screen in
                Label(screen.title, systemImage: screen.symbol)
            }
            .navigationTitle("blog.sh")
        } detail: {
            switch selection {
            case .archive: ArchiveView()
            case .drafts: PlaceholderView(screen: .drafts)
            case .queue: PlaceholderView(screen: .queue)
            case .settings: PlaceholderView(screen: .settings)
            case nil: ContentUnavailableView("Choose a screen", systemImage: "sidebar.left")
            }
        }
    }
}

/// Until a screen is built, its name and nothing else -- so every entry
/// in the sidebar leads somewhere and the shape of the app can be judged
/// before its contents exist.
struct PlaceholderView: View {
    let screen: Screen

    var body: some View {
        ContentUnavailableView(screen.title, systemImage: screen.symbol)
            .navigationTitle(screen.title)
    }
}

#Preview {
    ContentView()
}
