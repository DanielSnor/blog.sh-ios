import SwiftUI

/// The scheduled-post queue as `queue --json` hands it out, with the keys
/// of the terminal's screen on each row: [u] and [d] trade times with the
/// neighbour, [m] carries the post to a position, [p] publishes it now,
/// [s] asks for another time, [n] returns it to the drafts. When a post
/// leaves the queue the screen asks whether the rest should step forward
/// into the gap; the app asks the same, before the call, because the
/// engine answers both in one. The preview is rebuilt once, when you are
/// done -- the screen does it on the way out, the app offers it.
struct QueueView: View {
    @State private var rows: [QueueRow] = []
    @State private var problem: String?
    @State private var loading = false
    @State private var busy = false
    @State private var dirty = false

    @State private var leaving: Leaving?
    @State private var rescheduling: QueueRow?
    @State private var carrying: QueueRow?
    @State private var carryTo = 1
    @State private var notice: String?
    @State private var rebuilding = false

    /// A post about to leave the queue, and which way.
    struct Leaving: Identifiable {
        let row: QueueRow
        let publish: Bool
        var id: String { row.id }
    }

    var body: some View {
        List {
            if let problem {
                Text(problem).foregroundStyle(.secondary)
            }
            if dirty {
                Section {
                    Button {
                        Task { await rebuild() }
                    } label: {
                        Label("The preview is behind the queue — rebuild and deploy now", systemImage: "hammer")
                    }
                    .disabled(rebuilding)
                }
            }
            if !rows.isEmpty {
                Section("The queue (\(rows.count) scheduled):") {
                    ForEach(rows) { row in
                        QueueRowView(row: row)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button { Task { await move(row, "--up") } } label: { Label("Up", systemImage: "arrow.up") }
                                    .disabled(row.position == 1 || row.overdue)
                                Button { Task { await move(row, "--down") } } label: { Label("Down", systemImage: "arrow.down") }
                                    .disabled(row.position == rows.count || row.overdue)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { leaving = Leaving(row: row, publish: false) } label: {
                                    Label("Return to drafts", systemImage: "tray.and.arrow.down")
                                }
                                Button { leaving = Leaving(row: row, publish: true) } label: {
                                    Label("Publish now", systemImage: "paperplane")
                                }
                            }
                            .contextMenu { rowMenu(row) }
                    }
                }
            }
        }
        .overlay {
            if loading && rows.isEmpty {
                ProgressView()
            } else if !loading && rows.isEmpty && problem == nil {
                ContentUnavailableView("The queue is empty", systemImage: "calendar.badge.clock",
                                       description: Text("A draft is scheduled from its properties, or with ./blog.sh schedule."))
            }
        }
        .disabled(busy)
        .navigationTitle("The scheduled-post queue")
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(leavingTitle, isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
                            titleVisibility: .visible) {
            if let leaving {
                let behind = rows.count - leaving.row.position
                let verb = leaving.publish ? "Publish now" : "Return to drafts"
                Button(verb, role: leaving.publish ? nil : .destructive) { Task { await leave(leaving, compact: false) } }
                if behind > 0 && !leaving.row.overdue {
                    Button("\(verb) and shift the rest (\(behind)) a slot earlier") { Task { await leave(leaving, compact: true) } }
                }
            }
        } message: {
            if let leaving {
                Text(leaving.publish
                     ? "The same as publishing a draft by hand, announcement included."
                     : "The post keeps its text and loses only the plan.")
            }
        }
        .sheet(item: $rescheduling) { row in
            NavigationStack { ScheduleSheet(slug: row.slug, offered: nil, scheduled: true) { await changed() } }
        }
        .alert("Carry to which position?", isPresented: Binding(get: { carrying != nil }, set: { if !$0 { carrying = nil } })) {
            TextField("Position, 1 to \(rows.count)", value: $carryTo, format: .number)
                .keyboardType(.numberPad)
            Button("Carry") { Task { await carry() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The posts in between step back one slot each; the same times stay occupied.")
        }
        .alert("", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") {}
        } message: {
            Text(notice ?? "")
        }
    }

    @ViewBuilder
    private func rowMenu(_ row: QueueRow) -> some View {
        Button { Task { await move(row, "--up") } } label: { Label("Up — a slot earlier", systemImage: "arrow.up") }
            .disabled(row.position == 1 || row.overdue)
        Button { Task { await move(row, "--down") } } label: { Label("Down — a slot later", systemImage: "arrow.down") }
            .disabled(row.position == rows.count || row.overdue)
        Button { carryTo = row.position; carrying = row } label: { Label("Carry to a position…", systemImage: "arrow.up.arrow.down") }
            .disabled(row.overdue || rows.count < 2)
        Divider()
        Button { leaving = Leaving(row: row, publish: true) } label: { Label("Publish now", systemImage: "paperplane") }
        Button { rescheduling = row } label: { Label("Another time", systemImage: "calendar.badge.clock") }
        Button(role: .destructive) { leaving = Leaving(row: row, publish: false) } label: {
            Label("Return to drafts", systemImage: "tray.and.arrow.down")
        }
    }

    private var leavingTitle: String {
        guard let leaving else { return "" }
        return leaving.publish ? "Publish '\(leaving.row.slug)' now?" : "Return '\(leaving.row.slug)' to the drafts?"
    }

    // MARK: - The keys

    private func move(_ row: QueueRow, _ direction: String) async {
        busy = true
        defer { busy = false }
        do {
            let answer: QueueAnswer = try await Engine.shared.call(["queue", direction, "\(row.year)/\(row.slug)"])
            rows = answer.queue
            dirty = true
        } catch {
            notice = error.localizedDescription
        }
    }

    private func carry() async {
        guard let row = carrying else { return }
        busy = true
        defer { busy = false }
        do {
            let answer: QueueAnswer = try await Engine.shared.call(["queue", "--move", "\(row.year)/\(row.slug)", "--to", "\(carryTo)"])
            rows = answer.queue
            dirty = true
        } catch {
            notice = error.localizedDescription
        }
    }

    private func leave(_ leaving: Leaving, compact: Bool) async {
        busy = true
        defer { busy = false }
        var args = leaving.publish ? ["publish", leaving.row.slug, "--yes"] : ["schedule", leaving.row.slug, "--cancel"]
        if compact { args.append("--compact") }
        do {
            let answer: ActionAnswer = try await Engine.shared.call(args)
            // The engine says what it did in its own words (the warnings carry
            // the screen's lines); the app adds only the address a publish gave.
            var said: [String] = []
            if leaving.publish { said.append("Published: \(answer.url ?? leaving.row.slug)") }
            if let warnings = answer.warnings, !warnings.isEmpty { said.append(contentsOf: warnings) }
            if !said.isEmpty { notice = said.joined(separator: "\n") }
            // Publishing rebuilds by itself; a plan cancelled leaves the preview behind.
            if !leaving.publish { dirty = true }
            await load()
        } catch {
            notice = error.localizedDescription
        }
    }

    private func changed() async {
        dirty = true
        await load()
    }

    private func rebuild() async {
        rebuilding = true
        defer { rebuilding = false }
        do {
            let answer: RebuildAnswer = try await Engine.shared.call(["rebuild"])
            dirty = false
            notice = answer.deploy == "done" ? "Rebuilt and deployed." : "Rebuilt; the deploy is owed to the next scheduled run."
        } catch {
            notice = error.localizedDescription
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let answer: QueueAnswer = try await Engine.shared.call(["queue"])
            rows = answer.queue
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}

struct QueueRowView: View {
    let row: QueueRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(row.position).")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title.isEmpty ? row.slug : row.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let when = ISO8601DateFormatter.engine.date(from: row.date) {
                        Text(when, format: .dateTime.year().month().day().hour().minute())
                    } else {
                        Text(row.date)
                    }
                    Text(row.slug).lineLimit(1)
                    if row.overdue {
                        Text("(waiting for the cron)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack { QueueView() }
}
