import SwiftUI

/// The scheduled-post queue as `queue --json` hands it out: one row per
/// post in publish order, its position, time and slug -- the rows the
/// terminal's screen draws, with the "(waiting for the cron)" mark on a
/// post whose time has passed. The keys of that screen come later.
struct QueueView: View {
    @State private var rows: [QueueRow] = []
    @State private var problem: String?
    @State private var loading = false

    var body: some View {
        List {
            if let problem {
                Text(problem).foregroundStyle(.secondary)
            }
            if !rows.isEmpty {
                Section("The queue (\(rows.count) scheduled):") {
                    ForEach(rows) { row in
                        QueueRowView(row: row)
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
        .navigationTitle("The scheduled-post queue")
        .task { await load() }
        .refreshable { await load() }
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
