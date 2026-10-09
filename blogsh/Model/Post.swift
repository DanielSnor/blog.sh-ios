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

/// A delivery's own name, as the engine takes one: sixteen lowercase hex
/// digits. A post keeps the one it was given for as long as it is the same
/// post; the next post gets another -- the engine writes a delivery with a
/// receipt it knows over the draft it wrote for it.
nonisolated enum Receipt {
    static func mint() -> String {
        (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    static func isOne(_ text: String) -> Bool {
        text.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil
    }
}

/// The post as a markdown file, the way /write/ writes it: a header of
/// what the form has fields for, then the text.
nonisolated enum Markdown {
    /// `written`: when the post was written, where that is not when it is
    /// sent -- one that waited on the device for its blog. The engine dates
    /// a post by the moment it arrives unless its header says otherwise.
    ///
    /// `receipt`: the delivery's own name, by which the engine knows a
    /// delivery it has seen before -- one whose answer was lost on the way
    /// back and which is sent again -- and answers with the post it
    /// already wrote instead of writing a second.
    static func frontMatter(title: String, tags: String, publish: Bool = false, written: Date? = nil, receipt: String? = nil) -> String {
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
        if let written { lines.append("date: \(stamp(written))") }
        if let receipt, Receipt.isOne(receipt) { lines.append("receipt: \(receipt)") }
        return lines.isEmpty ? "" : "---\n" + lines.joined(separator: "\n") + "\n---\n\n"
    }

    /// A moment as the header says it: to the second, with the device's
    /// own offset -- the day it was where it was written.
    static func stamp(_ moment: Date, zone: TimeZone = .current) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime]
        format.timeZone = zone
        return format.string(from: moment)
    }

    static func file(title: String, tags: String, body: String, publish: Bool = false, written: Date? = nil, receipt: String? = nil) -> String {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let header = frontMatter(title: title, tags: tags, publish: publish, written: written, receipt: receipt)
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

    // A picture's description is ONE thing with two places to write it:
    // the card, and the mark the text has for the picture. Whichever is
    // written in, the other follows, at every letter -- so it does not
    // matter where one happens to be when a word comes to mind. Two
    // functions, one for each way; each leaves alone what already says
    // the same, which is what keeps the two from chasing each other and
    // keeps a space typed at the end of a word where it was typed.

    /// What the text says of a picture: the words of its first mark, as
    /// they stand there -- nothing at all where the text has no mark for
    /// it, the empty string where the mark says nothing.
    ///
    /// Read the way the engine reads a picture: a mark is a line of its
    /// own, and its description runs to the last "](" before the name --
    /// so a square bracket in it is part of it, as it is for the engine.
    /// A mark that shares its line with prose, which the engine refuses
    /// but the text may hold while it is being written, is read too, up
    /// to its first closing bracket.
    static func described(_ name: String, in text: String) -> String? {
        let file = NSRegularExpression.escapedPattern(for: name)
        let whole = NSRange(text.startIndex..., in: text)
        func first(_ pattern: String, _ options: NSRegularExpression.Options = []) -> (words: String, at: Int)? {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: options),
                  let match = expression.firstMatch(in: text, range: whole),
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return (String(text[range]), match.range.location)
        }
        var line = first(#"^[ \t]*!{1,2}\[(.*)\]\(\#(file)\)[ \t]*$"#, .anchorsMatchLines)
        // A line that holds another mark before this one is not this mark's line:
        // what was read as its description has the other's end in it.
        if let words = line?.words, words.contains("](") { line = nil }
        let inline = first(#"!\[([^\]\n]*)\]\(\#(file)\)"#)
        // Whichever stands first in the text is the picture's first mark.
        if let line, let inline { return line.at <= inline.at ? line.words : inline.words }
        return (line ?? inline)?.words
    }

    /// The text was written in: every card takes what the text now says of
    /// its picture. A card whose picture the text does not name keeps its
    /// own words -- they go in with the mark when it is put there.
    static func heard(_ shots: [Shot], from text: String) -> [Shot] {
        shots.map { shot in
            guard let words = described(shot.name, in: text), oneLine(words) != oneLine(shot.alt) else { return shot }
            var shot = shot
            shot.alt = words
            return shot
        }
    }

    /// A card was written on: the mark the text has for its picture says
    /// the same -- that mark, and any other of the picture that said what
    /// it said. A text with no mark for the picture is let be. (A video's
    /// two marks end in the same one, so the one rule serves both.)
    static func typed(_ text: String, name: String, after: String) -> String {
        guard let words = described(name, in: text), oneLine(words) != oneLine(after) else { return text }
        return text.replacingOccurrences(of: "![\(words)](\(name))", with: "![\(oneLine(after))](\(name))")
    }

    /// The same for every card at once: the shots as they are now, their
    /// descriptions as they were. With a shot added or taken away between
    /// the two there is nothing to compare, and the text is let be.
    static func retitled(_ text: String, shots: [Shot], before: [String]) -> String {
        guard shots.count == before.count else { return text }
        var text = text
        for (shot, was) in zip(shots, before) where shot.alt != was {
            text = typed(text, name: shot.name, after: shot.alt)
        }
        return text
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
