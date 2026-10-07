import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picture or a video chosen for a post: its bytes as they will travel
/// (a picture as JPEG with the long edge capped, the way /write/ shrinks a
/// phone photograph; a video as H.264 in an MP4), the name the markdown
/// refers to it by, and its description.
nonisolated struct Shot: Identifiable, Sendable {
    enum Kind: Sendable { case picture, video }

    let id = UUID()
    let name: String
    let data: Data
    let width: Int
    let height: Int
    var alt: String = ""
    var kind: Kind = .picture
    /// A frame of a video, for its card.
    var poster: Data?
    /// False for a video that could not be converted and goes as it came.
    var converted = true
    /// The shot small, for its card: drawn again with every letter typed
    /// beside it, which the whole picture is too heavy for.
    var thumb: Data?

    /// The shot as a line of markdown, a paragraph of its own. One mark or
    /// two: a picture is ![…](name), a video !![…](name).
    var mark: String { (kind == .video ? "!!" : "!") + "[\(Kept.oneLine(alt))](\(name))" }

    /// The shot's mark wherever the text has it, whatever it says there.
    var markPattern: String { #"!{1,2}\[[^\]]*\]\(\#(NSRegularExpression.escapedPattern(for: name))\)"# }
}

/// What /write/ does to a picture and to a name, so a post from the app
/// is the same post a post from the page would be.
nonisolated enum Pictures {
    /// Long edge; a phone photo is far larger than any blog needs.
    static let maxEdge = 2560
    static let quality = 0.88

    /// The bytes shrunk and re-encoded as JPEG; a picture already small
    /// enough is re-encoded all the same, which also drops its GPS tags.
    static func shrink(_ original: Data) -> (data: Data, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(original as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let sink = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(sink, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(sink) else { return nil }
        return (out as Data, image.width, image.height)
    }

    /// The picture small, as JPEG: what a card shows.
    static func thumbnail(_ original: Data, edge: Int = 480) -> Data? {
        guard let source = CGImageSourceCreateWithData(original as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let sink = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(sink, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        return CGImageDestinationFinalize(sink) ? out as Data : nil
    }

    /// A file name the receiver takes and a reader recognises: the
    /// original's stem, folded to a-z0-9 and dashes, `.jpg` on the end.
    static func safeName(_ original: String?, index: Int, stem: String = "photo", ext: String = "jpg") -> String {
        var base = (original ?? "").replacingOccurrences(of: #"\.[^.]*$"#, with: "", options: .regularExpression)
        base = base.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        base = base.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        base = String(base.prefix(100))
        return (base.isEmpty ? "\(stem)-\(index)" : base) + "." + ext
    }

    /// Two photographs can fold to one name; the second gets a number.
    static func freeName(_ name: String, taken: [String]) -> String {
        guard taken.contains(name) else { return name }
        let dot = name.lastIndex(of: ".")
        let stem = dot.map { String(name[..<$0]) } ?? name
        let ext = dot.map { String(name[$0...]) } ?? ""
        var n = 2
        while taken.contains("\(stem)-\(n)\(ext)") { n += 1 }
        return "\(stem)-\(n)\(ext)"
    }
}

/// The post as a markdown file, the way /write/ writes it: a header of
/// what the form has fields for, then the text.
nonisolated enum Markdown {
    static func frontMatter(title: String, tags: String, publish: Bool = false) -> String {
        var lines: [String] = []
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(["'])(.*)\1$"#, with: "$2", options: .regularExpression)
            .replacingOccurrences(of: #"^\[(.*)\]$"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if !cleanTitle.isEmpty { lines.append("title: \(cleanTitle)") }
        let cleanTags = tags.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"^\[|\]$"#, with: "", options: .regularExpression)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: #"^#"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\[|\]$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^["']|["']$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !cleanTags.isEmpty { lines.append("tags: \(cleanTags.joined(separator: ", "))") }
        if publish { lines.append("publish: yes") }
        return lines.isEmpty ? "" : "---\n" + lines.joined(separator: "\n") + "\n---\n\n"
    }

    static func file(title: String, tags: String, body: String, publish: Bool = false) -> String {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let header = frontMatter(title: title, tags: tags, publish: publish)
        // A body that itself opens with --- would be read as a header.
        let guarded = header.isEmpty && text.hasPrefix("---") ? "---\n---\n\n" : header
        return guarded + text + "\n"
    }

    /// The file's name: the first words of the title or the text, folded.
    static func fileName(title: String, body: String) -> String {
        let source = title.trimmingCharacters(in: .whitespaces).isEmpty ? body : title
        var base = source.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace }).prefix(6).joined(separator: " ")
        base = base.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        base = base.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((base.isEmpty ? "post" : base).prefix(40)) + ".md"
    }
}

/// What an edit sent from the app may do to a post's pictures. The engine
/// asks before a save that would lose something, and a file has nobody to
/// answer: it refuses one that leaves the post with fewer pictures, or
/// fewer videos, than it had. One taken out and another put in is as many
/// as before, and that it takes.
nonisolated enum Kept {
    private static let videoEndings: Set<String> = ["mov", "mp4", "m4v", "webm", "mkv", "avi"]

    static func isVideo(_ name: String) -> Bool {
        videoEndings.contains((name as NSString).pathExtension.lowercased())
    }

    static func named(_ name: String, in text: String) -> Bool { text.contains("(\(name))") }

    /// A shot's mark put into the text where the caret is -- at its end
    /// when the text was never touched. A blank line on each side, counted:
    /// the blog renders a picture only as a paragraph of its own and
    /// refuses one on the line straight after a sentence, so a mark put in
    /// the middle of a line breaks the line there; and counted so that a
    /// blank line already standing is not doubled. The rule of /write/
    /// (spacedMark). Positions are UTF-16 offsets, as the text view counts;
    /// the caret comes back after the mark and its gap, where one goes on
    /// writing.
    static func placed(_ mark: String, in text: String, at position: Int?) -> (text: String, caret: Int) {
        let whole = text as NSString
        let at = max(0, min(position ?? whole.length, whole.length))
        let before = whole.substring(to: at), after = whole.substring(from: at)
        let gaps = ["\n\n", "\n", ""]
        let trailing = before.reversed().prefix { $0 == "\n" }.count
        let leading = after.prefix { $0 == "\n" }.count
        let gapBefore = before.isEmpty ? "" : gaps[min(2, trailing)]
        let gapAfter = after.isEmpty ? "\n" : gaps[min(2, leading)]
        let put = gapBefore + mark + gapAfter
        return (before + put + after, at + (put as NSString).length)
    }

    /// A description is one line in the markdown, whatever its field held:
    /// a line break inside ![…](name) is a picture the engine refuses, with
    /// a reason that names the wrong thing.
    static func oneLine(_ words: String) -> String {
        words.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A description changed on its card follows the mark the text already
    /// has -- where that mark still says what the card said before. Anything
    /// else there is the author's own wording, typed into the text, and is
    /// not the card's to overwrite: the rule of /write/. (A video's two
    /// marks end in the same one, so the one rule serves both.)
    static func retitled(_ text: String, name: String, before: String, after: String) -> String {
        let was = "![\(oneLine(before))](\(name))"
        guard text.contains(was) else { return text }
        return text.replacingOccurrences(of: was, with: "![\(oneLine(after))](\(name))")
    }

    /// The same for every card at once: the shots as they are now, their
    /// descriptions as they were. With a shot added or taken away between
    /// the two there is nothing to compare, and the text is let be.
    static func retitled(_ text: String, shots: [Shot], before: [String]) -> String {
        guard shots.count == before.count else { return text }
        var text = text
        for (shot, was) in zip(shots, before) where shot.alt != was {
            text = retitled(text, name: shot.name, before: was, after: shot.alt)
        }
        return text
    }

    /// What the text itself says of a picture, where it says anything: a
    /// description typed into the mark and not onto the card.
    static func said(of name: String, in text: String) -> String? {
        let pattern = #"!\[([^\]]*)\]\(\#(NSRegularExpression.escapedPattern(for: name))\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let words = oneLine(String(text[range]))
        return words.isEmpty ? nil : words
    }

    /// What travels with the text: the shots it names. One picked and
    /// never put into the text would arrive, stand in no post and lie in
    /// the blog's incoming/ for good.
    static func sent(_ shots: [Shot], text: String) -> [Shot] {
        shots.filter { named($0.name, in: text) }
    }

    /// The post's own media the text has stopped naming.
    static func dropped(media: [String], text: String) -> [String] {
        media.filter { !named($0, in: text) }
    }

    /// True when the text names fewer pictures, or fewer videos, than the
    /// post has -- counting what it has and still names, and what is new
    /// and named. That save the engine refuses.
    static func fewer(media: [String], shots: [Shot], text: String) -> Bool {
        func count(video: Bool) -> (before: Int, after: Int) {
            let had = media.filter { isVideo($0) == video }
            let kept = had.filter { named($0, in: text) }.count
            let new = shots.filter { ($0.kind == .video) == video && named($0.name, in: text) }.count
            return (had.count, kept + new)
        }
        let pictures = count(video: false), videos = count(video: true)
        return pictures.after < pictures.before || videos.after < videos.before
    }
}

/// How much a delivery weighs on the wire: base64 is a third larger, and
/// the receiver measures the encoded stream.
nonisolated func encodedSize(_ bytes: Int) -> Int { (bytes + 2) / 3 * 4 + bytes / 57 + 1 }
