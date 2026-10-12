import Foundation
import UniformTypeIdentifiers

/// A finished text taken into the New post form from a file: one written
/// elsewhere -- dictated, kept in a cloud folder, come back to more than
/// once -- which was carried over through the clipboard until now. The
/// file is read and left as it is; nothing goes back into it.
///
/// All of it is the post's text: a title is not guessed from its first
/// line. Only where the file opens with a header between two `---` are
/// its `title` and `tags` read out, for the form's own fields, and the
/// rest of the header is left behind -- the form writes the header the
/// blog gets, and the blog reads one.
nonisolated enum TextFile {
    /// What was read: the text, and what a header said of it.
    struct Read: Equatable, Sendable {
        var title: String?
        var tags: String?
        var body: String

        /// What a field of the form holds once the file was taken: a
        /// field written in is left as it is, an empty one takes what
        /// the header said.
        func filling(_ field: String, with said: KeyPath<Read, String?>) -> String {
            guard field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let said = self[keyPath: said] else { return field }
            return said
        }
    }

    enum Failure: Error, Equatable {
        case unreadable
        /// Not plain text: a document of a word processor, or anything else.
        case notText
        case empty
        case tooLarge

        /// The sentence for it, in the reader's language.
        var words: String {
            switch self {
            case .unreadable:
                String(localized: "The file could not be read.")
            case .notText:
                String(localized: "This file is not plain text. A document of a word processor (.docx, .rtf) has to be saved as plain text or Markdown first.")
            case .empty:
                String(localized: "There is no text in the file.")
            case .tooLarge:
                String(localized: "The file is too large to be the text of a post.")
            }
        }
    }

    /// What the picker offers: plain text and Markdown. A word
    /// processor's document is not among them, and stays grey there.
    static var kinds: [UTType] {
        [.plainText] + ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }
    }

    /// More than this is no post's text; a file that large was picked by mistake.
    static let ceiling = 1_000_000

    /// The file the picker lent, read whole -- one kept in a cloud folder
    /// is fetched first -- and taken apart.
    @concurrent static func read(at url: URL) async throws(Failure) -> Read {
        let lent = url.startAccessingSecurityScopedResource()
        defer { if lent { url.stopAccessingSecurityScopedResource() } }
        var data: Data?
        var failed: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &failed) { at in
            data = try? Data(contentsOf: at)
        }
        guard failed == nil, let data else { throw .unreadable }
        return try read(data)
    }

    static func read(_ data: Data) throws(Failure) -> Read {
        guard data.count <= ceiling else { throw .tooLarge }
        guard let text = text(from: data) else { throw .notText }
        let read = read(text)
        guard !read.body.isEmpty || read.title != nil || read.tags != nil else { throw .empty }
        return read
    }

    /// The bytes as text, whatever wrote them: UTF-8 with its mark or
    /// without, UTF-16 with its mark, and -- for a file from an older
    /// Windows -- the code pages Central and Western Europe wrote in.
    /// Nil for what is not text at all.
    static func text(from data: Data) -> String? {
        var decoded: String?
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            decoded = String(data: data.dropFirst(3), encoding: .utf8)
        } else if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            decoded = String(data: data, encoding: .utf16)
        } else if let wide = unmarkedUTF16(data) {
            decoded = wide
        } else if let plain = String(data: data, encoding: .utf8) {
            decoded = plain
        } else {
            var guessed: NSString?
            let found = NSString.stringEncoding(for: data, encodingOptions: [
                .suggestedEncodingsKey: [String.Encoding.windowsCP1250.rawValue, String.Encoding.windowsCP1252.rawValue,
                                      String.Encoding.isoLatin2.rawValue, String.Encoding.utf16.rawValue],
                .useOnlySuggestedEncodingsKey: true,
                .allowLossyKey: false,
            ], convertedString: &guessed, usedLossyConversion: nil)
            decoded = found == 0 ? nil : guessed as String?
        }
        guard var text = decoded else { return nil }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        // What a word processor saves under a text file's name, and
        // anything with a byte no text has.
        guard !text.hasPrefix("{\\rtf"), !text.unicodeScalars.contains(where: { $0.value == 0 }) else { return nil }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// UTF-16 written without its mark: every other byte of a text in
    /// Latin letters is a zero there, and which half says which end comes
    /// first. Read as UTF-8, such a file would pass for text full of
    /// bytes no text has.
    private static func unmarkedUTF16(_ data: Data) -> String? {
        guard data.count >= 4, data.count.isMultiple(of: 2) else { return nil }
        var even = 0, odd = 0
        for (at, byte) in data.prefix(4096).enumerated() where byte == 0 {
            if at.isMultiple(of: 2) { even += 1 } else { odd += 1 }
        }
        let half = min(data.count, 4096) / 2
        if odd * 10 > half * 3, even * 10 < half { return String(data: data, encoding: .utf16LittleEndian) }
        if even * 10 > half * 3, odd * 10 < half { return String(data: data, encoding: .utf16BigEndian) }
        return nil
    }

    /// The text taken apart: a header, where the text opens with one and
    /// closes it, gives its title and its tags and is gone from the text.
    /// A `---` that nothing closes is a line of the text.
    static func read(_ text: String) -> Read {
        let lines = text.components(separatedBy: "\n")
        func isFence(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces) == "---" }
        guard let first = lines.first, isFence(first),
              let end = lines.dropFirst().firstIndex(where: isFence) else {
            return Read(body: trimmed(text))
        }
        let header = Array(lines[1..<end])
        return Read(title: title(in: header), tags: tags(in: header),
                    body: trimmed(lines[(end + 1)...].joined(separator: "\n")))
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What stands after `key:` on its own line of the header, and where.
    private static func value(of key: String, in header: [String]) -> (at: Int, value: String)? {
        for (at, line) in header.enumerated() where line.hasPrefix(key + ":") {
            return (at, line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else { return value }
        return String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    private static func title(in header: [String]) -> String? {
        guard let found = value(of: "title", in: header) else { return nil }
        let title = unquoted(found.value)
        return title.isEmpty ? nil : title
    }

    /// The tags as the form's field holds them, comma separated --
    /// whether the header lists them on the line, in brackets, or one to
    /// a line under it.
    private static func tags(in header: [String]) -> String? {
        guard let found = value(of: "tags", in: header) else { return nil }
        var raw: [String]
        if found.value.isEmpty {
            raw = header[(found.at + 1)...].prefix { $0.trimmingCharacters(in: .whitespaces).hasPrefix("-") }
                .map { String($0.trimmingCharacters(in: .whitespaces).dropFirst()) }
        } else {
            var inner = found.value
            if inner.hasPrefix("["), inner.hasSuffix("]") { inner = String(inner.dropFirst().dropLast()) }
            raw = inner.components(separatedBy: ",")
        }
        let tags = raw.map { unquoted($0.trimmingCharacters(in: .whitespaces)) }
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
        return tags.isEmpty ? nil : tags.joined(separator: ", ")
    }
}
