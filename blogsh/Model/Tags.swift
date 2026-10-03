import SwiftUI

/// A tag the blog has used, with two counts: all time, and the last twelve
/// months.
nonisolated struct TagUse: Sendable, Equatable {
    let name: String
    let count: Int
    let recent: Int
}

/// The tags the blog has used, offered as the author types -- the mechanism
/// of the /write/ page, rule for rule. There the build hands the counts out
/// in site.js; here they are counted from the rows `list` answers with, the
/// published ones, as the build counts them.
@Observable
final class TagStore {
    static let shared = TagStore()

    private(set) var tags: [TagUse] = []
    private var asked = false

    /// Once per run of the app; a screen that already holds the archive
    /// hands its rows over with `take` instead.
    func loadIfNeeded() async {
        guard !asked else { return }
        asked = true
        guard let answer: ListAnswer = try? await Engine.shared.call(["list"]) else {
            asked = false
            return
        }
        take(answer.posts)
    }

    func take(_ posts: [PostRow]) {
        asked = true
        let since = Date.now.addingTimeInterval(-365 * 24 * 60 * 60)
        var counts: [String: (count: Int, recent: Int)] = [:]
        for post in posts where post.state == .published {
            let recent = post.date.flatMap { ISO8601DateFormatter.engine.date(from: $0) }.map { $0 >= since } ?? false
            for tag in post.tags {
                var use = counts[tag] ?? (0, 0)
                use.count += 1
                if recent { use.recent += 1 }
                counts[tag] = use
            }
        }
        tags = counts.map { TagUse(name: $0.key, count: $0.value.count, recent: $0.value.recent) }
    }

    /// The tags field as the author has it: the ones finished, and the one
    /// being typed after the last comma.
    nonisolated static func parts(_ value: String) -> (done: [String], typing: String) {
        var pieces = value.components(separatedBy: ",")
        let typing = pieces.removeLast().trimmingCharacters(in: .whitespaces)
        let done = pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return (done, typing)
    }

    /// Those that begin with what is typed first, then those that merely
    /// contain it, each group by how often the blog has used them. With
    /// nothing typed yet, the ones used in the last twelve months, most
    /// used first -- not the most used of all time, which on an imported
    /// archive are the places it came from, and nobody tags a new post
    /// with those. Never one the post already carries.
    func suggest(typed: String, taken: [String], limit: Int = 8) -> [TagUse] {
        let query = typed.trimmingCharacters(in: .whitespaces).lowercased()
        let have = Set(taken.map { $0.lowercased() })
        let byName: (TagUse, TagUse) -> Bool = { $0.name.lowercased() < $1.name.lowercased() }
        let byUse: (TagUse, TagUse) -> Bool = { $0.count != $1.count ? $0.count > $1.count : byName($0, $1) }
        let byRecent: (TagUse, TagUse) -> Bool = { $0.recent != $1.recent ? $0.recent > $1.recent : byUse($0, $1) }
        let free = tags.filter { !have.contains($0.name.lowercased()) }
        if query.isEmpty {
            return Array(free.filter { $0.recent > 0 }.sorted(by: byRecent).prefix(limit))
        }
        let starts = free.filter { $0.name.lowercased().hasPrefix(query) }.sorted(by: byUse)
        let holds = free.filter { !$0.name.lowercased().hasPrefix(query) && $0.name.lowercased().contains(query) }.sorted(by: byUse)
        return Array((starts + holds).prefix(limit))
    }
}

/// The row of pills under a tags field: a tag is tapped rather than typed,
/// and typed as it was before, instead of the blog growing a second
/// spelling of it. The chosen tag replaces whatever was being typed, and
/// the comma after it invites the next one.
struct TagSuggestions: View {
    @Binding var text: String
    private var store = TagStore.shared

    init(text: Binding<String>) {
        _text = text
    }

    var body: some View {
        let parts = TagStore.parts(text)
        let offered = store.suggest(typed: parts.typing, taken: parts.done)
        if !offered.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(offered, id: \.name) { tag in
                    Button {
                        text = (parts.done + [tag.name]).joined(separator: ", ") + ", "
                    } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: tag.name)
                            Text(verbatim: "\(tag.count)").foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)
                }
            }
        }
    }
}

/// Pills one after another, on to the next line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in rows.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (points, widest, y + rowHeight)
    }
}
