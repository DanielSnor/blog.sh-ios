import SwiftUI

/// What the trash holds, as `restore --json` lists it -- the rows the
/// terminal offers when `restore` is run with no slug -- and what a row
/// does: it restores its post. A draft comes back with its preview
/// rebuilt, as the terminal rebuilds it; a published post is asked about,
/// as the terminal asks. Under the rows, the clearing out the terminal
/// has two commands for: `empty trash` and `empty versions`. Both are for
/// good, both say how much before they ask, and each is asked over its
/// own key.
struct TrashView: View {
    @State private var rows: [TrashRow] = []
    @State private var problem: String?
    @State private var loading = false
    @State private var busy = false
    @State private var restoring: TrashRow?
    /// How much the trash and the older versions hold, as `empty` counts them.
    @State private var held: HeldAnswer?
    @State private var older: HeldAnswer?
    @State private var emptying: Clearing?

    enum Clearing: String { case trash, versions }
    /// What the screen says after a restore -- one thing, its question in it.
    @State private var said: Said?

    var body: some View {
        List {
            ScreenHeader(title: String(localized: "tile.restore", defaultValue: "Trash"),
                         count: rows.isEmpty ? nil : rows.count.formatted())
                .padding(.top, 2)
                .padding(.bottom, 6)
                .paperRow()
            if let problem {
                Text(problem).font(.ui(14)).foregroundStyle(Theme.muted).paperRow()
            }
            ForEach(rows) { row in
                Button { restoring = row } label: {
                    TrashRowView(row: row)
                }
                .buttonStyle(PressStyle())
                // Asked over the row it is asked about, not at the head of the screen.
                .confirmationDialog("Restore '\(row.slug)'?", isPresented: asking(row), titleVisibility: .visible) {
                    Button("Restore") { Task { await restore(row) } }
                } message: {
                    Text(row.mediaOnly
                         ? "Only media are in the trash for this post; the terminal restores those."
                         : "The post, its media and its history come back where they were.")
                }
                .paperRow()
                .swipeActions(edge: .trailing) {
                    Button { restoring = row } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                        .tint(.accentColor)
                }
            }
            if (held?.count ?? 0) > 0 || (older?.count ?? 0) > 0 {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Clearing out")
                    // What cannot be taken back, set apart and last.
                    Plate {
                        if let held, held.count > 0 {
                            Command(text: Text("Empty the trash — \(held.count) item(s), \(Self.size(held.bytes))"),
                                    symbol: "trash.slash", danger: true) { emptying = .trash }
                                .confirmationDialog("Delete \(held.count) item(s) from the trash for good, freeing \(Self.size(held.bytes))? This cannot be undone.",
                                                    isPresented: asking(.trash), titleVisibility: .visible) {
                                    Button("Empty the trash", role: .destructive) { Task { await empty(.trash) } }
                                }
                        }
                        if let older, older.count > 0 {
                            Command(text: Text("Remove older versions — \(older.count) file(s), \(Self.size(older.bytes))"),
                                    symbol: "clock.badge.xmark", danger: true) { emptying = .versions }
                                .confirmationDialog("Remove \(older.count) older version(s), freeing \(Self.size(older.bytes))? Every post keeps its newest one. This cannot be undone.",
                                                    isPresented: asking(.versions), titleVisibility: .visible) {
                                    Button("Remove older versions", role: .destructive) { Task { await empty(.versions) } }
                                }
                        }
                    }
                    Hint("What is cleared out is gone for good. Older versions are what a post said before its recent saves; each post keeps its newest.")
                }
                .padding(.bottom, 18)
                .paperRow(rule: false)
            }
        }
        .overlay {
            if loading && rows.isEmpty {
                ProgressView()
            } else if !loading && rows.isEmpty && problem == nil {
                EmptyNote(symbol: "trash", title: "Trash is empty")
            }
        }
        .paperList()
        .disabled(busy)
        .navigationTitle("Trash")
        .task { await load() }
        .refreshable { await load() }
        .says($said)
    }

    private func asking(_ row: TrashRow) -> Binding<Bool> {
        Binding(get: { restoring?.id == row.id }, set: { if !$0 { restoring = nil } })
    }

    private func asking(_ what: Clearing) -> Binding<Bool> {
        Binding(get: { emptying == what }, set: { if !$0 { emptying = nil } })
    }

    private static func size(_ bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }

    /// `empty trash --yes` / `empty versions --yes`: gone for good. The
    /// answer says how much went; the screen reads itself again.
    private func empty(_ what: Clearing) async {
        busy = true
        defer { busy = false }
        do {
            let answer: HeldAnswer = try await Engine.shared.call(["empty", what.rawValue, "--yes"])
            await load()
            switch what {
            case .trash:
                said = Said(text: String(localized: "Trash emptied: \(answer.count) item(s), \(Self.size(answer.bytes)) freed."))
            case .versions:
                said = Said(text: String(localized: "Older versions removed: \(answer.count), \(Self.size(answer.bytes)) freed. Every post kept its newest."))
            }
        } catch {
            if !error.isCalledOff { said = Said(text: error.localizedDescription) }
        }
    }

    // The row as a value: the dialog's binding has cleared the state by the
    // time this runs.
    private func restore(_ row: TrashRow) async {
        busy = true
        defer { busy = false }
        do {
            // A draft's preview is rebuilt without asking, the way the terminal
            // does it; a published post's page is asked about.
            let args = ["restore", row.slug] + (row.state == "draft" ? ["--rebuild"] : [])
            let answer: ActionAnswer = try await Engine.shared.call(args)
            // The engine's own lines say it; the address only when it said nothing.
            let lines = (answer.warnings ?? []).plain
            let words = lines.isEmpty ? String(localized: "Restored: \(answer.url ?? row.slug)") : lines.joined(separator: "\n")
            await load()
            // A published post is back in the archive and not yet on the site:
            // that it is back, and the question about the site, as one.
            if answer.state == .published {
                said = Said(title: String(localized: "Rebuild and deploy the site now?"), text: words,
                            ask: Said.Ask(button: String(localized: "Rebuild"), cancel: String(localized: "Not now")) { await rebuild() })
            } else {
                said = Said(text: words)
            }
        } catch {
            if !error.isCalledOff { said = Said(text: error.localizedDescription) }
        }
    }

    private func rebuild() async {
        busy = true
        defer { busy = false }
        do {
            let answer: RebuildAnswer = try await Engine.shared.call(["rebuild"])
            said = Said(text: answer.deploy == "done" ? String(localized: "Rebuilt and deployed.") : String(localized: "Rebuilt; the deploy is owed to the next scheduled run."))
        } catch {
            if !error.isCalledOff { said = Said(text: error.localizedDescription) }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            // One connection: the rows, and how much there is to clear out --
            // `empty` without `--yes` counts and touches nothing.
            let answers = try await Engine.shared.answers(to: [["restore"], ["empty", "trash"], ["empty", "versions"]])
            let answer: TrashAnswer = try Engine.decode(answers[0])
            rows = answer.trash
            held = answers.count > 1 ? try? Engine.decode(answers[1]) : nil
            older = answers.count > 2 ? try? Engine.decode(answers[2]) : nil
            problem = nil
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}

struct TrashRowView: View {
    let row: TrashRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title ?? row.slug)
                    .font(.ui(15, weight: row.title == nil ? .medium : .bold))
                    .foregroundStyle(row.title == nil ? Theme.muted : Theme.ink)
                    .lineLimit(2)
                Group {
                    if row.mediaOnly {
                        Text("media only")
                    } else {
                        Text(verbatim: [row.type ?? "", row.slug].filter { !$0.isEmpty }.joined(separator: " · "))
                    }
                }
                .font(.ui(13))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let when = ISO8601DateFormatter.engine.date(from: row.date ?? "") {
                Text(verbatim: RowDate.short(when))
                    .font(.mono(11, bold: false))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { TrashView() }
}
