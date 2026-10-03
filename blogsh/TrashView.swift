import SwiftUI

/// What the trash holds, as `restore --json` lists it -- the rows the
/// terminal offers when `restore` is run with no slug -- and the one
/// action the screen has: a row restores its post. A draft comes back
/// with its preview rebuilt, as the terminal rebuilds it; a published
/// post is asked about, as the terminal asks.
struct TrashView: View {
    @State private var rows: [TrashRow] = []
    @State private var problem: String?
    @State private var loading = false
    @State private var busy = false
    @State private var restoring: TrashRow?
    @State private var askingRebuild = false
    @State private var notice: String?

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
                .paperRow()
                .swipeActions(edge: .trailing) {
                    Button { restoring = row } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                        .tint(.accentColor)
                }
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
        .confirmationDialog("Restore '\(restoring?.slug ?? "")'?",
                            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), titleVisibility: .visible) {
            if let row = restoring {
                Button("Restore") { Task { await restore(row) } }
            }
        } message: {
            Text(restoring?.mediaOnly == true
                 ? "Only media are in the trash for this post; the terminal restores those."
                 : "The post, its media and its history come back where they were.")
        }
        .alert("Rebuild and deploy the site now?", isPresented: $askingRebuild) {
            Button("Rebuild") { Task { await rebuild() } }
            Button("Not now", role: .cancel) {}
        }
        .alert("", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") {}
        } message: {
            Text(notice ?? "")
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
            let said = answer.warnings ?? []
            notice = said.isEmpty ? "Restored: \(answer.url ?? row.slug)" : said.joined(separator: "\n")
            await load()
            if answer.state == .published { askingRebuild = true }
        } catch {
            notice = error.isCalledOff ? notice : error.localizedDescription
        }
    }

    private func rebuild() async {
        busy = true
        defer { busy = false }
        do {
            let answer: RebuildAnswer = try await Engine.shared.call(["rebuild"])
            notice = answer.deploy == "done" ? "Rebuilt and deployed." : "Rebuilt; the deploy is owed to the next scheduled run."
        } catch {
            notice = error.isCalledOff ? notice : error.localizedDescription
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let answer: TrashAnswer = try await Engine.shared.call(["restore"])
            rows = answer.trash
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
