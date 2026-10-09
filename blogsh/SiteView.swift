import SwiftUI

/// "The site": the wizard's last entry, `./blog.sh rebuild` -- the whole
/// site built and deployed, not tied to a post. With the two switches the
/// command has: every page again, and the whole site uploaded past the
/// deploy's guards. Under it the two looks that only read: `check` and
/// `doctor` (see `DiagnosisView`).
struct SiteView: View {
    /// The blog this screen was opened for. An answer can come after
    /// another blog has been opened; what follows from it -- a build owed,
    /// a build paid -- is this blog's all the same.
    @State private var home = Blogs.shared.currentID
    @State private var full = false
    @State private var force = false
    @State private var running = false
    @State private var result: RebuildAnswer?
    @State private var problem: String?

    var body: some View {
        PaperScreen(name: MenuEntry.rebuild.short, symbol: MenuEntry.rebuild.symbol) {
            // Each switch with what it is for under it: the engine's own
            // names for them (--full, --force) say what they do to the
            // engine, not when somebody would want them.
            Plate {
                SwitchRow(label: "Build every page again", isOn: $full)
            }
            .gap(14)
            Hint("Usually only the pages that changed are built. With this on the whole site is built again, which takes longer.")
            Plate {
                SwitchRow(label: "Upload the whole site unchecked", isOn: $force)
            }
            .gap(14)
            Hint("A deploy uploads what changed, and stops by itself when the site has suddenly lost or gained a lot: that is what a broken build looks like. Turn this on only when it stopped and the change is right (many posts deleted, a large import). The whole site is then uploaded without that check.")
            Button {
                Task { await rebuild() }
            } label: {
                PrimaryLabel(label: running ? "Rebuilding…" : "Rebuild and deploy", busy: running)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(running)
            .gap(22)
            if let problem {
                ProblemLine(text: problem)
            }
            if let result {
                SectionLabel("Result")
                Plate {
                    Text(result.deploy == "done" ? "Rebuilt and deployed." : "Rebuilt; the deploy is owed to the next scheduled run.")
                        .font(.ui(15)).foregroundStyle(Theme.ink)
                    ForEach(result.warnings.plain, id: \.self) { line in
                        Text(verbatim: line).font(.ui(13)).foregroundStyle(Theme.muted)
                    }
                }
            }

            // A look that changes nothing, beside the two things that do.
            SectionLabel("Diagnostics")
            Plate {
                NavigationLink { DiagnosisView(what: .archive) } label: {
                    CommandRow("Check the archive", symbol: "checklist", leads: true)
                }
                .buttonStyle(PressStyle())
                NavigationLink { DiagnosisView(what: .installation) } label: {
                    CommandRow("Check the installation", symbol: "stethoscope", leads: true)
                }
                .buttonStyle(PressStyle())
            }
            Hint("Both only read. The first goes through the posts, their pictures, links and addresses; the second through the blog's configuration, its announcing, its schedule and its deploy.")
        }
        .navigationTitle("The site")
    }

    private func rebuild() async {
        running = true
        defer { running = false }
        var args = ["rebuild"]
        if full { args.append("--full") }
        if force { args.append("--force") }
        do {
            result = try await Engine.shared.call(args)
            problem = nil
            // Built here, by hand: nothing is owed, and a build that
            // failed before this one has been tried again.
            Herald.shared.settled(for: home)
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { SiteView() }
}
