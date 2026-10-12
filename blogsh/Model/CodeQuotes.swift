import Foundation

/// Quotes in code are the straight ones. The system writes a typed quote
/// as a typographic one -- which is what prose wants and what the blog
/// reads in a caption or a link's title -- and does so in code too, where
/// `echo “hi”` is no longer a command. So the quotes of code are made
/// straight -- once the writing has stopped: when the editor is left, and
/// again when the post goes.
///
/// Where code is, is the blog's to say, and this reads it as the blog's
/// own parser does: a block between two lines of three or more backticks
/// -- however far indented, the closing one at least as long as the
/// opening one and alone on its line, a block nobody closed running to
/// the end; and within a paragraph, what stands between a run of
/// backticks and the next run of as many, across a line break but not
/// across an empty line. Tildes fence nothing there, and neither does an
/// indent of four spaces.
///
/// Not while somebody types: the text under a keyboard is the keyboard's
/// too. Doing it at the keystroke was tried (12 Oct 2026) and not shown
/// to be safe -- writing the text over after a key, and telling the
/// keyboard anew to write quotes as typed while the caret stands in code
/// (the editor's trait changed without telling the keyboard changes
/// nothing). In the simulator, typed by a machine, words went missing
/// under both; they also went missing with neither, to the keyboard's own
/// autocorrection, so the two could not be told apart there. Until it is
/// tried by hand on a device, the text is left alone while it is written.
/// One mark stands for one, so the text stays as long as it was.
/// Positions are UTF-16 offsets, as the text view counts.
nonisolated enum CodeQuotes {
    private static let tick: unichar = 0x60

    /// One line of the text, as the blocks see it.
    private enum Line {
        /// Three backticks or more, and what follows them on the line.
        case fence(length: Int, bare: Bool)
        case blank
        case words
    }

    private static func kind(_ text: NSString, _ line: NSRange) -> Line {
        var at = line.location
        var end = NSMaxRange(line)
        func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }
        while at < end, isSpace(text.character(at: at)) { at += 1 }
        while end > at, isSpace(text.character(at: end - 1)) { end -= 1 }
        guard at < end else { return .blank }
        var run = at
        while run < end, text.character(at: run) == tick { run += 1 }
        guard run - at >= 3 else { return .words }
        return .fence(length: run - at, bare: run == end)
    }

    /// The text taken apart: its blocks' contents, and its paragraphs --
    /// the stretches a run of backticks can be answered in.
    private static func parts(of text: NSString) -> (blocks: [NSRange], paragraphs: [NSRange]) {
        var blocks: [NSRange] = [], paragraphs: [NSRange] = []
        var open: Int?
        var paragraph: NSRange?
        func close() {
            if let one = paragraph { paragraphs.append(one) }
            paragraph = nil
        }
        var at = 0
        while at < text.length {
            let line = text.lineRange(for: NSRange(location: at, length: 0))
            at = NSMaxRange(line)
            let what = kind(text, line)
            if let length = open {
                if case .fence(let closing, true) = what, closing >= length { open = nil } else { blocks.append(line) }
                continue
            }
            switch what {
            case .fence(let length, _):
                close()
                open = length
            case .blank:
                close()
            case .words:
                paragraph = paragraph.map { NSUnionRange($0, line) } ?? line
            }
        }
        close()
        return (blocks, paragraphs)
    }

    /// Where the text is code.
    static func code(in text: String) -> [NSRange] {
        let whole = text as NSString
        let parts = parts(of: whole)
        return (parts.blocks + parts.paragraphs.flatMap { spans(whole, $0) }).sorted { $0.location < $1.location }
    }

    /// The code within one paragraph: what stands between a run of
    /// backticks and the first as many after it. A run nothing answers
    /// is itself.
    private static func spans(_ text: NSString, _ paragraph: NSRange) -> [NSRange] {
        var found: [NSRange] = []
        let end = NSMaxRange(paragraph)
        var at = paragraph.location
        while at < end {
            guard text.character(at: at) == tick else { at += 1; continue }
            var open = at
            while open < end, text.character(at: open) == tick { open += 1 }
            let count = open - at
            // What closes it: the first run of at least as many.
            var seek = open
            var closed: Int?
            while seek < end {
                guard text.character(at: seek) == tick else { seek += 1; continue }
                var run = seek
                while run < end, text.character(at: run) == tick { run += 1 }
                if run - seek >= count { closed = seek; break }
                seek = run
            }
            guard let closed else { at = open; continue }
            found.append(NSRange(location: open, length: closed - open))
            at = closed + count
        }
        return found
    }

    private static func straight(_ mark: unichar) -> unichar? {
        switch mark {
        case 0x201C, 0x201D, 0x201E, 0x201F: 0x22
        case 0x2018, 0x2019, 0x201A, 0x201B: 0x27
        default: nil
        }
    }

    /// The text with the quotes of its code made straight, on the lines
    /// `touched` reaches into and on no others: what was not just made
    /// code is left as its author has it.
    static func straightened(_ text: String, touched: NSRange) -> String {
        let whole = text as NSString
        guard touched.location <= whole.length else { return text }
        let reach = NSRange(location: touched.location, length: min(touched.length, whole.length - touched.location))
        let lines = whole.lineRange(for: reach)
        var units = Array(text.utf16)
        var changed = false
        for span in code(in: text) {
            let here = NSIntersectionRange(span, lines)
            guard here.length > 0 else { continue }
            for at in here.location..<NSMaxRange(here) {
                if let plain = straight(units[at]) {
                    units[at] = plain
                    changed = true
                }
            }
        }
        return changed ? String(utf16CodeUnits: units, count: units.count) : text
    }

    /// The text as it is left once the writing has stopped -- the editor
    /// was left, or the post is on its way: the quotes of its code made
    /// straight. Over a post that came from the blog, only on the lines
    /// the blog's text does not have; what nobody wrote here is left as
    /// its author has it, or a post merely opened would read as changed.
    static func settled(_ text: String, over original: String? = nil) -> String {
        let had = Set((original ?? "").components(separatedBy: "\n"))
        let whole = text as NSString
        var units = Array(text.utf16)
        var changed = false
        for span in code(in: text) {
            var at = span.location
            while at < NSMaxRange(span) {
                let line = whole.lineRange(for: NSRange(location: at, length: 0))
                let here = NSIntersectionRange(span, line)
                at = NSMaxRange(line)
                if original != nil {
                    let words = whole.substring(with: line).trimmingCharacters(in: .newlines)
                    if had.contains(words) { continue }
                }
                guard here.length > 0 else { continue }
                for one in here.location..<NSMaxRange(here) {
                    if let plain = straight(units[one]) {
                        units[one] = plain
                        changed = true
                    }
                }
            }
        }
        return changed ? String(utf16CodeUnits: units, count: units.count) : text
    }
}
