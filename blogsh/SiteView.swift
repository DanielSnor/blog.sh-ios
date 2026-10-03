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
        Form {
            Section {
                Toggle("Build every page again", isOn: $full)
                Toggle("Let the deploy past its guards", isOn: $force)
            } footer: {
                Text("Without the first, only the pages that changed are built; the second uploads everything, which the deploy's own guard asks for when it refuses.")
            }
            Section {
                Button {
                    Task { await rebuild() }
                } label: {
                    if running {
                        HStack { ProgressView(); Text("Rebuilding…") }
                    } else {
                        Label("Rebuild and deploy", systemImage: "hammer")
                    }
                }
                .disabled(running)
            }
            if let result {
                Section("Result") {
                    Text(result.deploy == "done" ? "Rebuilt and deployed." : "Rebuilt; the deploy is owed to the next scheduled run.")
                    ForEach(result.warnings, id: \.self) { line in
                        Text(line).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let problem {
                Section { Text(problem).foregroundStyle(.red) }
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
