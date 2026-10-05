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
    @State private var said: Said?
    @State private var rebuilding = false

    /// A post about to leave the queue, and which way.
    struct Leaving: Identifiable {
        let row: QueueRow
        let publish: Bool
        var id: String { row.id }
    }

    var body: some View {
        List {
            ScreenHeader(title: String(localized: "tile.queue", defaultValue: "Queue"),
                         count: rows.isEmpty ? nil : rows.count.formatted())
                .padding(.top, 2)
                .padding(.bottom, 6)
                .paperRow()
            if let problem {
                Text(problem).font(.ui(14)).foregroundStyle(Theme.muted).paperRow()
            }
            if dirty {
                Button {
                    Task { await rebuild() }
                } label: {
                    Card(highlighted: true) {
                        Image(systemName: "hammer").foregroundStyle(.tint)
                        Text("The preview is behind the queue — rebuild and deploy now")
                            .font(.ui(14, weight: .medium))
                            .foregroundStyle(Theme.ink)
                    }
                }
                .buttonStyle(PressStyle())
                .disabled(rebuilding)
                .padding(.vertical, 10)
                .paperRow(rule: false)
            }
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        QueueRowView(row: row)
                            // Asked over the row it is asked about.
                            .confirmationDialog(leavingTitle, isPresented: asking(row), titleVisibility: .visible) {
                                if let leaving {
                                    let behind = rows.count - leaving.row.position
                                    Button(leaving.publish ? "Publish now" : "Return to drafts", role: leaving.publish ? nil : .destructive) {
                                        Task { await leave(leaving, compact: false) }
                                    }
                                    if behind > 0 && !leaving.row.overdue {
                                        Button(leaving.publish ? "Publish now and shift the rest (\(behind)) a slot earlier"
                                                               : "Return to drafts and shift the rest (\(behind)) a slot earlier") {
                                            Task { await leave(leaving, compact: true) }
                                        }
                                    }
                                }
                            } message: {
                                if let leaving {
                                    Text(leaving.publish
                                         ? "The same as publishing a draft by hand, announcement included."
                                         : "The post keeps its text and loses only the plan.")
                                }
                            }
                            .paperRow()
                            // A post waiting for the cron has no slot to trade.
                            .moveDisabled(row.overdue)
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
                    // [m] with a finger: the row is carried to where it is dropped. It
                    // is shown there at once; the engine's answer is what stays.
                    .onMove { source, destination in
                        guard let from = source.first, rows.indices.contains(from) else { return }
                        let row = rows[from]
                        let position = destination > from ? destination : destination + 1
                        guard position != row.position else { return }
                        rows.move(fromOffsets: source, toOffset: destination)
                        Task { await carry(row, to: position) }
                    }
                }
            }
        }
        .overlay {
            if loading && rows.isEmpty {
                ProgressView()
            } else if !loading && rows.isEmpty && problem == nil {
                EmptyNote(symbol: "calendar", title: "The queue is empty",
                          detail: "A draft is scheduled from its properties, or with ./blog.sh schedule.")
            }
        }
        .paperList()
        .disabled(busy)
        .navigationTitle("The scheduled-post queue")
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $rescheduling) { row in
            NavigationStack { ScheduleSheet(slug: row.slug, offered: nil, current: row.date, scheduled: true) { await changed() } }
        }
        .alert("Carry to which position?", isPresented: Binding(get: { carrying != nil }, set: { if !$0 { carrying = nil } })) {
            TextField("Position, 1 to \(rows.count)", value: $carryTo, format: .number)
                .keyboardType(.numberPad)
            Button("Carry") { if let row = carrying { Task { await carry(row, to: carryTo) } } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The posts in between step back one slot each; the same times stay occupied.")
        }
        .says($said)
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
        return leaving.publish ? String(localized: "Publish '\(leaving.row.slug)' now?")
                               : String(localized: "Return '\(leaving.row.slug)' to the drafts?")
    }

    private func asking(_ row: QueueRow) -> Binding<Bool> {
        Binding(get: { leaving?.row.id == row.id }, set: { if !$0 { leaving = nil } })
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
            notice = error.isCalledOff ? notice : error.localizedDescription
        }
    }

    private func carry(_ row: QueueRow, to position: Int) async {
        busy = true
        defer { busy = false }
        do {
            let answer: QueueAnswer = try await Engine.shared.call(["queue", "--move", "\(row.year)/\(row.slug)", "--to", "\(position)"])
            rows = answer.queue
            dirty = true
        } catch {
            notice = error.isCalledOff ? notice : error.localizedDescription
            // The row was shown where it was dropped; the queue is as the engine has it.
            await load()
        }
    }

    private func leave(_ leaving: Leaving, compact: Bool, anyway: Bool = false) async {
        busy = true
        defer { busy = false }
        var args = leaving.publish ? ["publish", leaving.row.slug, "--yes"] : ["schedule", leaving.row.slug, "--cancel"]
        if compact { args.append("--compact") }
        if anyway { args.append("--allow-partial") }
        do {
            let answer: ActionAnswer = try await Engine.shared.call(args)
            // The engine says what it did in its own words (the warnings carry
            // the screen's lines); the app adds only the address a publish gave.
            var said: [String] = []
            if leaving.publish { said.append(String(localized: "Published: \(answer.url ?? leaving.row.slug)")) }
            if let warnings = answer.warnings?.plain, !warnings.isEmpty { said.append(contentsOf: warnings) }
            if !said.isEmpty { notice = said.joined(separator: "\n") }
            // Publishing rebuilds by itself; a plan cancelled leaves the preview behind.
            if !leaving.publish { dirty = true }
            await load()
        } catch EngineError.refused(let refusal) where refusal.error == Partial.code && leaving.publish && !anyway {
            // Not written in every language the site publishes: asked, as the properties screen asks it.
            said = Said(text: Partial.words, ask: Said.Ask(button: String(localized: "Publish anyway")) {
                await leave(leaving, compact: compact, anyway: true)
            })
        } catch {
            notice = error.isCalledOff ? notice : error.localizedDescription
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
            notice = answer.deploy == "done" ? String(localized: "Rebuilt and deployed.") : String(localized: "Rebuilt; the deploy is owed to the next scheduled run.")
        } catch {
            notice = error.isCalledOff ? notice : error.localizedDescription
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
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}

/// A post in the queue: its place as a key, its title, and when it goes
/// out -- the hour at the edge, the whole date with its zone under the
/// title, because the queue is the blog's clock and a phone abroad would
/// otherwise show an hour nobody scheduled.
struct QueueRowView: View {
    let row: QueueRow

    var body: some View {
        let when = ISO8601DateFormatter.engine.date(from: row.date)
        HStack(alignment: .top, spacing: 12) {
            KeyChip(text: "\(row.position)")
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title.isEmpty ? row.slug : row.title)
                    .font(.ui(15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Group {
                    if let when {
                        Text(when, format: .dateTime.year().month().day().hour().minute().timeZone())
                    } else {
                        Text(row.date)
                    }
                }
                .font(.ui(13))
                .foregroundStyle(Theme.muted)
                if row.overdue {
                    Text("(waiting for the cron)").font(.ui(13)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            if let when {
                Text(verbatim: RowDate.soon(when))
                    .font(.mono(11))
                    .foregroundStyle(.tint)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 11)
    }
}

#Preview {
    NavigationStack { QueueView() }
}
