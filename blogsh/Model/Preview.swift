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
    /// The line that splits a post in two -- what a list of posts shows of
    /// it, and the rest -- as the engine reads it: alone on its line.
    private static let teaserEnd = regex(#"^[ \t]*//--more--//[ \t]*$"#)
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
            // The one place this leaves the page's own rendering: there the
            // line is printed as words. Here it is what it means on the
            // blog -- nothing to read, a place where the post is cut -- so
            // it is drawn as a hairline.
            if has(teaserEnd, line) {
                flush()
                html.append("<hr class=\"teaser-end\">")
                i += 1; continue
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
                    i += 1; continue
                }
                func figure(_ m: [String]) -> String {
                    if let shown = shots[m[2]] {
                        return "<figure><img src=\"" + escape(shown.source) + "\" alt=\"" + escape(m[1]) + "\"></figure>"
                    }
                    return box(words.missing(m[2]))
                }
                // The second place this leaves the page's rendering, and
                // follows the blog's: pictures in a row, with nothing but
                // blank lines between them, are a gallery there -- two side
                // by side, an odd last one across both -- in the markup the
                // engine writes (build/blocks.rb, render_photo_grid).
                var row = [figure(m)]
                var next = i + 1
                while true {
                    var k = next
                    while k < lines.count, blank(k) { k += 1 }
                    guard k < lines.count, let more = groups(picture, lines[k]), k + 1 >= lines.count || blank(k + 1) else { break }
                    row.append(figure(more))
                    next = k + 1
                }
                if row.count > 1 {
                    if row.count % 2 == 1, let range = row[row.count - 1].range(of: "<figure>") {
                        row[row.count - 1].replaceSubrange(range, with: "<figure class=\"span-2\">")
                    }
                    html.append("<div class=\"photo-grid\">" + row.joined() + "</div>")
                } else {
                    html.append(row[0])
                }
                i = next; continue
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
    /// skin does -- and built the way the engine's own post page is
    /// (templates/post.html.erb): a card, in it the header, in the header
    /// the body with the title over the content. The nesting is what the
    /// stylesheet is written for: the header's negative margins are the
    /// card's padding taken back, and without the card around it the title
    /// stood outside the window; the text's own headings are sized as
    /// `.content` sizes them, not as a card's.
    static func document(title: String, body: String, lang: String, stylesheets: [String] = Preview.stylesheets) -> String {
        let links = stylesheets.map { "<link rel=\"stylesheet\" href=\"" + escape($0) + "\">" }.joined()
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = name.isEmpty ? "" : "<h1>" + escape(name) + "</h1>"
        return "<!doctype html><html lang=\"" + escape(lang) + "\"><head><meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><base href=\"/\">"
            // The gallery as the engine's own stylesheet lays it out, said
            // before that stylesheet so the blog's -- or a skin's -- wins:
            // it holds where the blog cannot be reached.
            + "<style>.photo-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:4px;margin:1rem 0}"
            + ".photo-grid figure{margin:0;display:flex;flex-direction:column}"
            + ".photo-grid img{width:100%;flex:1 1 auto;min-height:0;object-fit:cover;display:block}"
            + ".photo-grid .span-2{grid-column:1/-1}</style>" + links
            + "<style>body{margin:0;padding:1rem;background:var(--card-bg,transparent)}"
            + "figure{margin:1rem 0}figure img,figure video{max-width:100%;height:auto}"
            + ".no-preview{padding:1rem;border:1px dashed currentColor;opacity:.6;font-size:.9em}"
            + "hr.teaser-end{border:0;border-top:1px solid currentColor;opacity:.3;margin:1.5rem 0}</style></head>"
            + "<body><main><div class=\"card\"><article><div class=\"post-header\"><div class=\"post-body\">" + heading
            + "<div class=\"content\">" + body + "</div></div></div></article></div></main></body></html>"
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

/// How a post begins, in plain words: what stands under its title where a
/// post is picked, to tell it from the one beside it. The part before the
/// line that cuts the post in two, where it has one; its first paragraph
/// where it has none. The marks are taken off -- this is read, not
/// rendered -- and a post that is only a picture is known by the
/// picture's description.
nonisolated struct Lede: Equatable, Sendable {
    /// The words, or nothing when the post has none of its own.
    let words: String
    /// The first picture's or video's description, for a post without words.
    let picture: String?

    static let limit = 600

    private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }
    private static let cut = regex(#"^[ \t]*//--more--//[ \t]*$"#)
    private static let media = regex(#"^!{1,2}\[([^\n]*)\]\(([^)\s]+)\)\s*$"#)
    private static let fence = regex("^```")
    private static let labelled = regex(#"!{0,2}\[([^\]]*)\]\((?:\([^()\s]*\)|[^)\s])+\)"#)
    private static let lead = regex(#"^\s*(?:#{1,6}\s+|>\s?)"#)
    private static let emphasis = regex(#"(^|[^*])\*([^*\n]+)\*(?!\*)"#)

    private static func has(_ re: NSRegularExpression, _ line: String) -> Bool {
        re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    private static func sub(_ re: NSRegularExpression, _ text: String, _ template: String) -> String {
        re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// A line of the text as words: a link is its label, a heading or a
    /// quote its text, and what was bold or struck is just said.
    static func plain(_ line: String) -> String {
        var out = sub(lead, line, "")
        out = sub(labelled, out, "$1")
        out = out.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "~~", with: "")
        out = sub(emphasis, out, "$1$2")
        return out.replacingOccurrences(of: "`", with: "")
    }

    /// Of a text as the editor opens it, header and all.
    static func of(_ text: String) -> Lede {
        let body = Preview.parts(of: text).body.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = body.components(separatedBy: "\n")
        let teaser = lines.firstIndex { has(cut, $0) }
        if let teaser { lines = Array(lines[..<teaser]) }
        var paragraphs: [String] = [], current: [String] = []
        var picture: String?
        var fenced = false
        func close() {
            if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
            current = []
        }
        for line in lines {
            if has(fence, line) { close(); fenced.toggle(); continue }
            if fenced { continue }
            if let match = media.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                close()
                let alt = Range(match.range(at: 1), in: line).map { String(line[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
                if picture == nil, !alt.isEmpty { picture = alt }
                continue
            }
            let words = plain(line).trimmingCharacters(in: .whitespaces)
            if words.isEmpty { close() } else { current.append(words) }
        }
        close()
        // Up to the cut the author made, all of it; without one, the first paragraph.
        var words = (teaser == nil ? paragraphs.first ?? "" : paragraphs.joined(separator: "\n\n"))
        // A cut at the very top leaves nothing above it: then the post begins after it.
        if words.isEmpty, teaser != nil {
            let rest = Lede.of(body.components(separatedBy: "\n").filter { !has(cut, $0) }.joined(separator: "\n"))
            return Lede(words: rest.words, picture: picture ?? rest.picture)
        }
        if words.count > limit {
            let head = words.prefix(limit)
            let end = head.lastIndex(where: { $0 == " " || $0 == "\n" }) ?? head.endIndex
            words = head[..<end].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return Lede(words: words, picture: picture)
    }
}
