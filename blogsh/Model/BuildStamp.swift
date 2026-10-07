import Foundation

/// Which build this is: the commit it was made from and when it was made.
/// Written into the bundle by the build itself (the project's "Stamp the
/// build" phase: a line with the commit, a line with the time), so one
/// copy of the app can be told from another -- on a tablet, on a desk --
/// without asking the machine that built it.
nonisolated struct BuildStamp: Equatable, Sendable {
    /// The short commit; a plus after it for a tree that had changes not committed.
    let commit: String?
    let built: Date?

    /// The two lines of the stamp file. Anything else is no stamp.
    init(text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let first = lines.first ?? ""
        let valid = !first.isEmpty && first.count <= 41 && first.allSatisfy { $0.isHexDigit || $0 == "+" }
        commit = valid ? first : nil
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        built = lines.count > 1 ? formatter.date(from: lines[1]) : nil
    }

    init(commit: String?, built: Date?) {
        self.commit = commit
        self.built = built
    }

    /// This app's own: the stamp in its bundle, or -- a build nobody
    /// stamped -- at least when its code was written to disk.
    static let own: BuildStamp = {
        if let url = Bundle.main.url(forResource: "BuildStamp", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            let stamp = BuildStamp(text: text)
            if stamp.commit != nil || stamp.built != nil { return stamp }
        }
        let made = Bundle.main.executableURL.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        return BuildStamp(commit: nil, built: made)
    }()
}
