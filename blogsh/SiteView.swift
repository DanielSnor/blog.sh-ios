import SwiftUI

/// "The site": the wizard's last entry, `./blog.sh rebuild` -- the whole
/// site built and deployed, not tied to a post. With the two switches the
/// command has: every page again, and the deploy past its guards.
struct SiteView: View {
    @State private var full = false
    @State private var force = false
    @State private var running = false
    @State private var result: RebuildAnswer?
    @State private var problem: String?

    var body: some View {
        PaperScreen {
            ScreenHeader(title: MenuEntry.rebuild.short)
            Plate {
                SwitchRow(label: "Build every page again", isOn: $full)
                SwitchRow(label: "Let the deploy past its guards", isOn: $force)
            }
            .padding(.top, 14)
            Hint("Without the first, only the pages that changed are built; the second uploads everything, which the deploy's own guard asks for when it refuses.")
            Button {
                Task { await rebuild() }
            } label: {
                PrimaryLabel(label: running ? "Rebuilding…" : "Rebuild and deploy", busy: running)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(running)
            .padding(.top, 22)
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
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { SiteView() }
}
