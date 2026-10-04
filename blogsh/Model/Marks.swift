import Foundation

/// The marks the text takes, from the row of buttons above it -- the
/// /write/ page's own (write/app.js, applyMark), rule for rule, so a text
/// marked on the phone reads the way one marked on the page does. Each is
/// a function of the text and the selection alone. A paired mark wraps
/// what is selected and, applied again to the same selection, takes itself
/// off; with nothing selected it puts the pair in and leaves the caret
/// between. A line mark goes to the start of every line the selection
/// touches, and comes off the same way.
///
/// Positions are UTF-16 offsets, as on the page: a selection is counted
/// the way the text view counts it.
nonisolated enum Marks {
    enum Kind: String, CaseIterable, Sendable {
        case bold, italic, strike, code, link, h2, quote, ul, ol, fence
    }

    /// The two placeholders a link is made with, in the reader's language.
    struct Words: Sendable {
        var text = "text"
        var url = "https://"
    }

    private static let paired: [Kind: String] = [.bold: "**", .italic: "*", .strike: "~~", .code: "`"]
    private static let lined: [Kind: String] = [.h2: "## ", .quote: "> ", .ul: "- "]

    static func apply(_ value: String, selection: NSRange, kind: Kind, words: Words = Words()) -> (value: String, selection: NSRange) {
        let v = value as NSString
        let length = v.length
        var start = max(0, min(selection.location, length))
        var end = max(start, min(selection.location + selection.length, length))
        func slice(_ a: Int, _ b: Int) -> String { b > a ? v.substring(with: NSRange(location: a, length: b - a)) : "" }
        func unit(_ i: Int) -> String { i >= 0 && i < length ? v.substring(with: NSRange(location: i, length: 1)) : "" }
        func count(_ s: String) -> Int { (s as NSString).length }
        func range(_ a: Int, _ b: Int) -> NSRange { NSRange(location: a, length: max(0, b - a)) }
        var sel = slice(start, end)

        if let mark = paired[kind] {
            let n = count(mark)
            // A mark of one character next to another of the same character
            // is part of a longer mark -- the * of **bold** -- and not this
            // one: italic on a bold word must not un-bold it.
            func edge(_ a: Int, _ b: Int) -> Bool { n == 1 && (unit(a - 1) == mark || unit(b) == mark) }
            // Selected together with its marks, or between them: either way
            // the second tap takes them off.
            if count(sel) >= 2 * n, sel.hasPrefix(mark), sel.hasSuffix(mark), !edge(start, end) {
                let inner = (sel as NSString).substring(with: NSRange(location: n, length: count(sel) - 2 * n))
                return (slice(0, start) + inner + slice(end, length), range(start, end - 2 * n))
            }
            if start >= n, slice(start - n, start) == mark, slice(end, min(length, end + n)) == mark, !edge(start - n, end + n) {
                return (slice(0, start - n) + sel + slice(end + n, length), range(start - n, end - n))
            }
            return (slice(0, start) + mark + sel + mark + slice(end, length), range(start + n, end + n))
        }

        if kind == .link {
            func blank(_ s: String) -> Bool { s.isEmpty || s.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) }
            // The whole word, when the selection stops inside one: a phone
            // selects a word up to its dot, so "sean.cz" arrives as "sean."
            // -- and half an address is no address.
            while start > 0, !blank(unit(start - 1)) { start -= 1 }
            while end < length, !blank(unit(end)) { end += 1 }
            let whole = slice(start, end)
            // Inside a link that already is one, there is nothing to make.
            if whole.range(of: #"^\[[^\]]*\]\([^)]*\)$"#, options: .regularExpression) != nil || whole.contains("](") {
                return (value, range(start, end))
            }
            // Brackets and the punctuation a sentence puts around a word
            // stay outside the link.
            while start < end, "([{\"'".contains(unit(start)) { start += 1 }
            while end > start, ")]}.,;:!?\"'".contains(unit(end - 1)) { end -= 1 }
            sel = slice(start, end)
            let isURL = sel.range(of: #"^(https?://|mailto:)\S+$"#, options: [.regularExpression, .caseInsensitive]) != nil
            // A bare domain is an address too, and its own best label.
            let isDomain = !isURL && sel.range(of: #"^(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}(/\S*)?$"#,
                                               options: [.regularExpression, .caseInsensitive]) != nil
            let label = isURL ? words.text : (sel.isEmpty ? words.text : sel)
            let url = isURL ? sel : isDomain ? "https://" + sel : words.url
            let out = "[\(label)](\(url))"
            // What is left selected is what the author may still want to
            // type: the words for an address, the address for words.
            let onLabel = isURL || isDomain
            let from = onLabel ? start + 1 : start + 1 + count(label) + 2
            let span = onLabel ? count(label) : count(url)
            return (slice(0, start) + out + slice(end, length), NSRange(location: from, length: span))
        }

        if kind == .fence {
            let open = (start > 0 && unit(start - 1) != "\n" ? "\n" : "") + "```\n"
            let close = "\n```" + (end < length && unit(end) != "\n" ? "\n" : "")
            return (slice(0, start) + open + sel + close + slice(end, length),
                    NSRange(location: start + count(open), length: count(sel)))
        }

        // Line marks: the lines the selection touches, whole.
        let before = v.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: start))
        let lineStart = before.location == NSNotFound ? 0 : before.location + 1
        let probe = end > start ? end - 1 : end
        let after = v.range(of: "\n", options: [], range: NSRange(location: probe, length: length - probe))
        let lineEnd = max(lineStart, after.location == NSNotFound ? length : after.location)
        let old = slice(lineStart, lineEnd).components(separatedBy: "\n")
        var lines = old
        // Added, a mark goes on every line once -- a line that already had
        // it is not given a second one -- and every line loses it when they
        // all had it.
        if kind == .ol {
            let numbered = #"^\d+\. "#
            let has = lines.allSatisfy { $0.range(of: numbered, options: .regularExpression) != nil }
            lines = lines.enumerated().map { index, line in
                let bare = line.replacingOccurrences(of: numbered, with: "", options: .regularExpression)
                return has ? bare : "\(index + 1). \(bare)"
            }
        } else {
            guard let prefix = lined[kind] else { return (value, range(start, end)) }
            let has = lines.allSatisfy { $0.hasPrefix(prefix) }
            lines = lines.map { line in
                let bare = line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line
                return has ? bare : prefix + bare
            }
        }
        let block = lines.joined(separator: "\n")
        let changed = slice(0, lineStart) + block + slice(lineEnd, length)
        if end > start { return (changed, NSRange(location: lineStart, length: count(block))) }
        // A bare caret stays on its line, moved by what the line gained or
        // lost before it.
        let delta = count(lines[0]) - count(old[0])
        return (changed, NSRange(location: max(lineStart, start + delta), length: 0))
    }
}
