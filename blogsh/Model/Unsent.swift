import Foundation

/// A post being written and not sent yet: its title, its tags, its text.
/// Kept on the device at every letter, for the blog it is written for --
/// so an app that was closed, or stopped by the system behind another,
/// or a way back taken by mistake, costs nothing that was written.
///
/// The pictures are not kept: they are large, and come back from the
/// library in a moment. The marks the text has for them are text, and
/// stay; a picture chosen again takes its name and its description back
/// from its mark.
nonisolated struct Unsent: Codable, Equatable, Sendable {
    var title = ""
    var tags = ""
    var text = ""
    /// When it was last written in.
    var at = Date.distantPast

    /// Nothing worth keeping: spaces and line breaks are not writing.
    var isEmpty: Bool {
        [title, tags, text].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The text names a picture or a video, which was not kept with it.
    var namesPictures: Bool {
        text.range(of: #"!{1,2}\[[^\n]*\]\([^)\s]+\)"#, options: .regularExpression) != nil
    }

    static func key(_ blog: UUID) -> String { "unsent.\(blog.uuidString)" }

    /// What is kept for this blog; nothing where nothing is, or where
    /// what is there does not read.
    static func kept(for blog: UUID, in defaults: UserDefaults = .standard) -> Unsent? {
        guard let data = defaults.data(forKey: key(blog)),
              let unsent = try? JSONDecoder().decode(Unsent.self, from: data),
              !unsent.isEmpty else { return nil }
        return unsent
    }

    /// Keeps it for this blog -- or, emptied, keeps nothing: a form that
    /// was sent, or cleared by hand, leaves no post behind to bring back.
    func keep(for blog: UUID, in defaults: UserDefaults = .standard) {
        guard !isEmpty, let data = try? JSONEncoder().encode(self) else {
            defaults.removeObject(forKey: Self.key(blog))
            return
        }
        defaults.set(data, forKey: Self.key(blog))
    }

    static func forget(for blog: UUID, in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(blog))
    }
}
