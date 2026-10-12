import Foundation

/// The practice blog: a blog that lives in the app. It has no server --
/// what it answers was said once by a real engine about a small blog of
/// seven posts, and is carried in the app (`Practice.json`). It is there
/// to be looked around in before a blog of one's own is connected: by
/// somebody who has none yet, and by whoever is to judge the app without
/// a server to try it on.
///
/// It can be read, and nothing can be written to it: every command that
/// would change a blog is answered with a no that says why. An answer
/// that pretended -- "published" over a list that stayed as it was --
/// would be a lie the next screen gives away.
nonisolated enum Practice {
    /// What the blog says to what cannot be done to it.
    static var refusal: String {
        String(localized: "This is the practice blog: it lives in the app, and nothing is written to it or sent anywhere. Add a blog of your own to do this.")
    }

    /// Each answer as it would come over the wire, under the command it answers.
    private static let answers: [String: Data] = {
        guard let url = Bundle.main.url(forResource: "Practice", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let read = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return read.compactMapValues { try? JSONSerialization.data(withJSONObject: $0) }
    }()

    private static func data(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }

    private static var no: Data {
        data(["ok": false, "error": "practice", "message": refusal])
    }

    /// The answer to one command, as the engine's door would give it.
    static func answer(to args: [String]) -> Data {
        // A search is the list, with the rows the words are found in.
        if args.first == "list", let search = args.dropFirst().first(where: { $0.hasPrefix("--search=") }) {
            return data(found(String(search.dropFirst("--search=".count))))
        }
        if let kept = answers[args.joined(separator: " ")] { return kept }
        // The devices a code let in: none, and nobody to tell apart.
        if args == ["pair", "--list"] { return data(["ok": true, "devices": [] as [Any], "self": NSNull()]) }
        return no
    }

    /// A delivery: nothing is taken.
    static var delivered: [Data] { [no] }

    private static func found(_ words: String) -> [String: Any] {
        guard let kept = answers["list"], var list = try? JSONSerialization.jsonObject(with: kept) as? [String: Any],
              let posts = list["posts"] as? [[String: Any]] else {
            return ["ok": true, "posts": [] as [Any]]
        }
        let wanted = words.lowercased().split(separator: " ").map(String.init)
        list["posts"] = posts.filter { post in
            let hay = ([post["title"] as? String ?? "", post["slug"] as? String ?? ""] + (post["tags"] as? [String] ?? []))
                .joined(separator: " ").lowercased()
            return wanted.allSatisfy(hay.contains)
        }
        return list
    }
}
