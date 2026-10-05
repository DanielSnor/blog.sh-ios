import Foundation

/// The post as the blog would show it, near enough: the markdown the
/// /write/ page knows -- paragraphs, headings, bold, italic,
/// strikethrough, code, links, quotes, lists, fenced code, and a picture
/// or a video on a line of its own -- rendered here the way that page
/// renders it, and dressed in the blog's own stylesheets. Near enough, not
/// exact: the engine renders the real thing, and the draft's preview after
/// sending is that. This is for seeing the shape of a post before it
/// leaves the device.
nonisolated enum Preview {
    /// What stands where the text names a picture or a video.
    enum Shown: Sendable, Equatable {
        /// A picture, by the address the page can load it from.
        case picture(String)
        /// A video the page can play.
        case video(String)
        /// A video shown by one frame of it, when its bytes are too many to hand a page.
        case frame(String)

        var source: String {
            switch self {
            case .picture(let source), .video(let source), .frame(let source): source
            }
        }
    }

    /// The two sentences the preview may have to say, in the reader's language.
    struct Words: Sendable {
        var missing: @Sendable (String) -> String = { "Picture \($0) -- no preview on this device" }
        var glued: @Sendable (String) -> String = {
            "\($0): a picture has to stand on a line of its own, with a blank line before it and after it -- the blog refuses the post otherwise"
        }
    }

    /// The stylesheets a post page wears, in order, unless the site adds its own.
    static let stylesheets = ["/assets/css/colors.css", "/assets/css/site.css"]

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - inline

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // The patterns are the page's own, written out here: one that does not compile is a mistake in this file.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let codeSpan = regex("`[^`]+`")
    private static let strong = regex(#"\*\*(.+?)\*\*"#)
    private static let emphasis = regex(#"(^|[^*])\*([^*\n]+)\*(?!\*)"#)
    private static let deleted = regex("~~(.+?)~~")
    private static let link = regex(#"\[([^\]]+)\]\(((?:\([^()\s]*\)|[^)\s])+)\)"#)
    private static let linkable = regex("^(https?://|mailto:|/)", .caseInsensitive)

    private static func replace(_ re: NSRegularExpression, in text: String, with template: String) -> String {
        re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// Code spans first and kept apart, so a * inside one is not emphasis.
    static func inline(_ text: String) -> String {
        var out = ""
        var at = text.startIndex
        func words(_ piece: Substring) -> String {
            var html = escape(String(piece))
            html = replace(strong, in: html, with: "<strong>$1</strong>")
            html = replace(emphasis, in: html, with: "$1<em>$2</em>")
            html = replace(deleted, in: html, with: "<del>$1</del>")
            // A link only to somewhere a link may go; anything else stays words.
            let ns = html as NSString
            var linked = ""
            var from = 0
            for match in link.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                linked += ns.substring(with: NSRange(location: from, length: match.range.location - from))
                let label = ns.substring(with: match.range(at: 1)), url = ns.substring(with: match.range(at: 2))
                let goes = linkable.firstMatch(in: url, range: NSRange(location: 0, length: (url as NSString).length)) != nil
                linked += goes ? "<a href=\"\(url)\">\(label)</a>" : label
                from = match.range.location + match.range.length
            }
            return linked + ns.substring(from: from)
        }
        for match in codeSpan.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            out += words(text[at..<range.lowerBound])
            out += "<code>" + escape(String(text[range].dropFirst().dropLast())) + "</code>"
            at = range.upperBound
        }
        return out + words(text[at...])
    }

    // MARK: - blocks

    private static let fence = regex("^```")
    private static let heading = regex(#"^(#{1,3})\s+(.+)$"#)
    private static let clip = regex(#"^!!\[([^\n]*)\]\(([^)\s]+)\)\s*$"#)
    private static let picture = regex(#"^!\[([^\n]*)\]\(([^)\s]+)\)\s*$"#)
    private static let quoted = regex(#"^>\s?"#)
    private static let listed = regex(#"^\s*([-*+]|\d+\.)\s+"#)
    private static let numbered = regex(#"^\s*\d+\."#)

    private static func has(_ re: NSRegularExpression, _ line: String) -> Bool {
        re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    private static func groups(_ re: NSRegularExpression, _ line: String) -> [String]? {
        guard let match = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: line).map { String(line[$0]) } ?? "" }
    }

    /// The text as the body of a post page. `shots` is what each name the
    /// text may use stands for; a name it does not know is said so, in the
    /// box where the picture would stand.
    static func render(_ markdown: String, shots: [String: Shown] = [:], words: Words = Words()) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var html: [String] = [], para: [String] = []
        var i = 0
        func blank(_ index: Int) -> Bool { lines[index].trimmingCharacters(in: .whitespaces).isEmpty }
        func flush() {
            if !para.isEmpty { html.append("<p>" + inline(para.joined(separator: "\n")) + "</p>") }
            para = []
        }
        func box(_ sentence: String) -> String { "<figure><div class=\"no-preview\">" + escape(sentence) + "</div></figure>" }
        while i < lines.count {
            let line = lines[i]
            if has(fence, line) {
                flush()
                var code: [String] = []
                i += 1
                while i < lines.count, !has(fence, lines[i]) { code.append(lines[i]); i += 1 }
                i += 1
                html.append("<pre class=\"code-block\"><code>" + escape(code.joined(separator: "\n")) + "</code></pre>")
                continue
            }
            if let m = groups(heading, line) {
                flush()
                let level = m[1].count + 1   // a post's own title is the h1
                html.append("<h\(level)>" + inline(m[2]) + "</h\(level)>")
                i += 1; continue
            }
            // The engine takes a picture only as a paragraph of its own: a
            // blank line before it and after it.
            let glued = (i > 0 && !blank(i - 1)) || (i + 1 < lines.count && !blank(i + 1))
            if let m = groups(clip, line) {
                flush()
                if glued {
                    html.append(box(words.glued(m[2])))
                } else if case .frame(let source)? = shots[m[2]] {
                    html.append("<figure><img src=\"" + escape(source) + "\" alt=\"" + escape(m[1]) + "\">"
                                + (m[1].isEmpty ? "" : "<figcaption>" + escape(m[1]) + "</figcaption>") + "</figure>")
                } else if let shown = shots[m[2]] {
                    // By the mark, as the page does it: two marks are a video, whatever the name ends in.
                    html.append("<figure><video controls playsinline src=\"" + escape(shown.source) + "\"></video>"
                                + (m[1].isEmpty ? "" : "<figcaption>" + escape(m[1]) + "</figcaption>") + "</figure>")
                } else {
                    html.append(box(words.missing(m[2])))
                }
                i += 1; continue
            }
            if let m = groups(picture, line) {
                flush()
                if glued {
                    html.append(box(words.glued(m[2])))
                } else if let shown = shots[m[2]] {
                    html.append("<figure><img src=\"" + escape(shown.source) + "\" alt=\"" + escape(m[1]) + "\"></figure>")
                } else {
                    html.append(box(words.missing(m[2])))
                }
                i += 1; continue
            }
            if has(quoted, line) {
                flush()
                var quote: [String] = []
                while i < lines.count, has(quoted, lines[i]) {
                    quote.append(replace(quoted, in: lines[i], with: ""))
                    i += 1
                }
                html.append("<blockquote><p>" + inline(quote.joined(separator: "\n")) + "</p></blockquote>")
                continue
            }
            if has(listed, line) {
                flush()
                let ordered = has(numbered, line)
                var items: [String] = []
                while i < lines.count, has(listed, lines[i]) {
                    items.append("<li>" + inline(replace(listed, in: lines[i], with: "")) + "</li>")
                    i += 1
                }
                html.append((ordered ? "<ol>" : "<ul>") + items.joined() + (ordered ? "</ol>" : "</ul>"))
                continue
            }
            if blank(i) { flush(); i += 1; continue }
            para.append(line)
            i += 1
        }
        flush()
        return html.joined(separator: "\n")
    }

    // MARK: - the page

    /// A whole page wearing the stylesheets a post page wears -- the same
    /// paths, resolved against the site, so the preview changes when the
    /// skin does.
    static func document(title: String, body: String, lang: String, stylesheets: [String] = Preview.stylesheets) -> String {
        let links = stylesheets.map { "<link rel=\"stylesheet\" href=\"" + escape($0) + "\">" }.joined()
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = name.isEmpty ? "" : "<h1>" + escape(name) + "</h1>"
        return "<!doctype html><html lang=\"" + escape(lang) + "\"><head><meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><base href=\"/\">" + links
            + "<style>body{margin:0;padding:1rem}figure{margin:1rem 0}figure img,figure video{max-width:100%;height:auto}"
            + ".no-preview{padding:1rem;border:1px dashed currentColor;opacity:.6;font-size:.9em}</style></head>"
            + "<body><main><article><div class=\"post-header\">" + heading + "</div><div class=\"post-body\">"
            + body + "</div></article></main></body></html>"
    }

    /// What the names of a form's own shots stand for: a picture rides in
    /// the page as a data address, the way the /write/ page hands it over;
    /// a video is shown by a frame of it -- its bytes are too many.
    static func shown(for shots: [Shot]) -> [String: Shown] {
        var map: [String: Shown] = [:]
        for shot in shots {
            if shot.kind == .video {
                if let frame = shot.poster ?? shot.thumb { map[shot.name] = .frame("data:image/jpeg;base64," + frame.base64EncodedString()) }
            } else {
                map[shot.name] = .picture("data:image/jpeg;base64," + shot.data.base64EncodedString())
            }
        }
        return map
    }

    /// What the names of a post's own media stand for: the files the build
    /// keeps beside the post's page, at the address the engine gave.
    static func shown(media: [String], beside address: String) -> [String: Shown] {
        var map: [String: Shown] = [:]
        for name in media {
            let source = address + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)
            map[name] = Kept.isVideo(name) ? .video(source) : .picture(source)
        }
        return map
    }

    /// The two sentences in the reader's language, in the page's own words.
    static var spoken: Words {
        Words(missing: { String(localized: "Picture \($0) -- no preview on this device") },
              glued: { String(localized: "\($0): a picture has to stand on a line of its own, with a blank line before it and after it -- the blog refuses the post otherwise") })
    }

    /// A text that opens with a header, as the editor opens a post: the
    /// title the header gives, and the text under it.
    static func parts(of text: String) -> (title: String, body: String) {
        guard text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else {
            return ("", text)
        }
        // An empty header closes on the very line that opened it.
        let start = text.index(text.startIndex, offsetBy: 4)
        let header = end.lowerBound >= start ? text[start..<end.lowerBound] : ""
        var title = ""
        for line in header.split(separator: "\n") where line.hasPrefix("title:") {
            title = line.dropFirst("title:".count).trimmingCharacters(in: .whitespaces)
        }
        return (title, String(text[end.upperBound...]))
    }
}
