import SwiftUI

/// What the trash holds, as `restore --json` lists it -- the rows the
/// terminal offers when `restore` is run with no slug. Restoring one is
/// the action, and comes with the rest of the actions.
struct TrashView: View {
    @State private var rows: [TrashRow] = []
    @State private var problem: String?
    @State private var loading = false

    var body: some View {
        List {
            if let problem {
                Text(problem).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                TrashRowView(row: row)
            }
        }
        .overlay {
            if loading && rows.isEmpty {
                ProgressView()
            } else if !loading && rows.isEmpty && problem == nil {
                ContentUnavailableView("Trash is empty", systemImage: "trash")
            }
        }
        .navigationTitle("Trash")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let answer: TrashAnswer = try await Engine.shared.call(["restore"])
            rows = answer.trash
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}

struct TrashRowView: View {
    let row: TrashRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title ?? row.slug)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 8) {
                if let when = ISO8601DateFormatter.engine.date(from: row.date ?? "") {
                    Text(when, format: .dateTime.year().month().day())
                }
                if row.mediaOnly {
                    Text("media only")
                } else {
                    Text(row.type ?? "")
                    Text(row.slug).lineLimit(1)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack { TrashView() }
}
