import Foundation
import Testing
import UniformTypeIdentifiers
@testable import blogsh

/// A finished text taken from a file: all of it is the post's text, and
/// only a header says a title and tags.
@Suite struct TextFileTests {
    /// The first line stays a line of the text: a title is not guessed.
    @Test func allOfAPlainTextIsTheBody() throws {
        let read = try TextFile.read(Data("Sobota v lese\n\nŠli jsme ráno.\nBylo mokro.\n".utf8))
        #expect(read.title == nil)
        #expect(read.tags == nil)
        #expect(read.body == "Sobota v lese\n\nŠli jsme ráno.\nBylo mokro.")
    }

    /// The title and the tags are read out of a header; the rest of it
    /// is left behind, and none of it stays in the text.
    @Test func aHeaderGivesItsTitleAndTags() throws {
        let file = "---\ntitle: \"Sobota v lese\"\ndate: 2026-10-12\ntags: [les, #houby, 'ráno']\npublish: yes\n---\n\nŠli jsme ráno.\n"
        let read = try TextFile.read(Data(file.utf8))
        #expect(read.title == "Sobota v lese")
        #expect(read.tags == "les, houby, ráno")
        #expect(read.body == "Šli jsme ráno.")
    }

    @Test func tagsAreReadHoweverTheHeaderListsThem() {
        #expect(TextFile.read("---\ntags: les, houby\n---\ntext").tags == "les, houby")
        #expect(TextFile.read("---\ntags:\n  - les\n  - \"houby\"\ntitle: T\n---\ntext").tags == "les, houby")
        #expect(TextFile.read("---\ntags:\n  - les\n  - \"houby\"\ntitle: T\n---\ntext").title == "T")
        #expect(TextFile.read("---\ntags: []\ntitle:\n---\ntext").tags == nil)
        #expect(TextFile.read("---\ntags: []\ntitle:\n---\ntext").title == nil)
        // A longer key that begins the same is another key.
        #expect(TextFile.read("---\ntitles: no\ntagset: a\n---\ntext").title == nil)
        #expect(TextFile.read("---\ntitles: no\ntagset: a\n---\ntext").tags == nil)
    }

    /// A field written in is left as it is; only an empty one takes
    /// what the header said.
    @Test func aHeaderFillsOnlyEmptyFields() {
        let read = TextFile.Read(title: "Ze souboru", tags: "les, houby", body: "text")
        #expect(read.filling("", with: \.title) == "Ze souboru")
        #expect(read.filling("  \n", with: \.title) == "Ze souboru")
        #expect(read.filling("Můj titulek", with: \.title) == "Můj titulek")
        #expect(read.filling("", with: \.tags) == "les, houby")
        #expect(read.filling("ráno", with: \.tags) == "ráno")
        // A file with no header changes neither.
        let plain = TextFile.Read(body: "text")
        #expect(plain.filling("", with: \.title) == "")
        #expect(plain.filling("ráno", with: \.tags) == "ráno")
    }

    /// A rule at the top of a text that nothing closes is the text's own.
    @Test func aRuleThatNothingClosesIsNoHeader() {
        let read = TextFile.read("---\n\nPo čáře.\n")
        #expect(read.title == nil)
        #expect(read.body == "---\n\nPo čáře.")
    }

    /// A header alone still says its title; a file with nothing says so.
    @Test func whatHasNothingIsSaidEmpty() throws {
        #expect(try TextFile.read(Data("---\ntitle: Jen titulek\n---\n".utf8)) == TextFile.Read(title: "Jen titulek", tags: nil, body: ""))
        #expect(throws: TextFile.Failure.empty) { try TextFile.read(Data(" \n\n".utf8)) }
        #expect(throws: TextFile.Failure.empty) { try TextFile.read(Data()) }
    }

    /// Whatever wrote the file: the mark at its head is no part of the
    /// text, a Windows line end is a line end, and a file in two bytes to
    /// a letter is read as what it is.
    @Test func theTextIsReadWhateverWroteIt() throws {
        let words = "Žluťoučký kůň\núpěl"
        #expect(TextFile.text(from: Data([0xEF, 0xBB, 0xBF]) + Data(words.utf8)) == words)
        #expect(TextFile.text(from: Data("Žluťoučký kůň\r\núpěl".utf8)) == words)
        #expect(TextFile.text(from: Data("Žluťoučký kůň\rúpěl".utf8)) == words)
        #expect(TextFile.text(from: Data([0xFF, 0xFE]) + words.data(using: .utf16LittleEndian)!) == words)
        #expect(TextFile.text(from: Data([0xFE, 0xFF]) + words.data(using: .utf16BigEndian)!) == words)
        #expect(TextFile.text(from: words.data(using: .utf16LittleEndian)!) == words)
        #expect(TextFile.text(from: words.data(using: .utf16BigEndian)!) == words)
        #expect(TextFile.text(from: words.data(using: .windowsCP1250)!) == words)
        // A header behind the mark is still a header.
        let marked = Data([0xEF, 0xBB, 0xBF]) + Data("---\r\ntitle: T\r\n---\r\ntext\r\n".utf8)
        #expect(try TextFile.read(marked) == TextFile.Read(title: "T", tags: nil, body: "text"))
    }

    /// A word processor's document is not text, under whatever name.
    @Test func whatIsNotTextIsTurnedAway() {
        #expect(throws: TextFile.Failure.notText) { try TextFile.read(Data(#"{\rtf1\ansi Sobota}"#.utf8)) }
        #expect(throws: TextFile.Failure.notText) { try TextFile.read(Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00, 0x08, 0x00, 0x00, 0x00, 0x21])) }
        #expect(throws: TextFile.Failure.tooLarge) { try TextFile.read(Data(repeating: 0x61, count: TextFile.ceiling + 1)) }
    }

    /// The picker offers plain text and Markdown, and no document of a
    /// word processor.
    @Test func thePickerOffersTextAndMarkdown() throws {
        let offered = TextFile.kinds
        func taken(_ ext: String) -> Bool {
            guard let kind = UTType(filenameExtension: ext) else { return false }
            return offered.contains { kind.conforms(to: $0) }
        }
        #expect(taken("txt"))
        #expect(taken("md"))
        #expect(!taken("docx"))
        #expect(!taken("rtf"))
        #expect(!taken("pdf"))
        #expect(!taken("jpg"))
    }

    /// A file is read where it lies, and is left as it was.
    @Test func aFileIsReadAndLeftAsItIs() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("text-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Diktát z procházky.txt")
        let written = Data("---\ntitle: Procházka\n---\nPrvní odstavec.\n\nDruhý.\n".utf8)
        try written.write(to: file)
        let read = try await TextFile.read(at: file)
        #expect(read == TextFile.Read(title: "Procházka", tags: nil, body: "První odstavec.\n\nDruhý."))
        #expect(try Data(contentsOf: file) == written)
        await #expect(throws: TextFile.Failure.unreadable) { try await TextFile.read(at: folder.appendingPathComponent("není.txt")) }
    }

    /// Into a text already begun, the file's text goes where the caret
    /// is, as paragraphs of its own, and nothing written is lost.
    @Test func theTextGoesInWhereTheCaretIs() {
        let put = Kept.placed("Ze souboru.\n\nDruhý odstavec.", in: "Začátek.\n\nKonec.", at: ("Začátek." as NSString).length)
        #expect(put.text == "Začátek.\n\nZe souboru.\n\nDruhý odstavec.\n\nKonec.")
        let alone = Kept.placed("Ze souboru.", in: "", at: nil)
        #expect(alone.text == "Ze souboru.\n")
    }
}
