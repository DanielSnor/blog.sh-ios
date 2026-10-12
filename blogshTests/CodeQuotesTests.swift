import Foundation
import Testing
@testable import blogsh

/// Quotes typed into code stay the straight ones; prose keeps the
/// typographic ones the system writes.
@Suite struct CodeQuotesTests {
    private func all(_ text: String) -> String {
        CodeQuotes.straightened(text, touched: NSRange(location: 0, length: (text as NSString).length))
    }

    @Test func proseKeepsItsQuotes() {
        let prose = "Řekl „ahoj“ a šel. She said “hi”, didn’t she?"
        #expect(all(prose) == prose)
        #expect(CodeQuotes.code(in: prose).isEmpty)
    }

    @Test func codeOnALineHasStraightQuotes() {
        #expect(all("Spusť `echo “ahoj”` a pak „hotovo“.") == "Spusť `echo \"ahoj\"` a pak „hotovo“.")
        #expect(all("`a ‘b’` a `c „d“`") == "`a 'b'` a `c \"d\"`")
        // Two backticks around a text that has one of its own.
        #expect(all("``it’s `x` “y”`` a “z”") == "``it's `x` \"y\"`` a “z”")
    }

    /// A span runs across a line break within its paragraph, as the blog
    /// reads it, and not across an empty line.
    @Test func aSpanCrossesALineAndNotAnEmptyOne() {
        #expect(all("Spusť `echo “a”\na “b”` hned.") == "Spusť `echo \"a\"\na \"b\"` hned.")
        #expect(all("Jeden ` a “a”\n\ndruhý ` a “b”") == "Jeden ` a “a”\n\ndruhý ` a “b”")
        // The first run of as many closes, the rest of it stays text.
        #expect(all("`“a”`` “b”") == "`\"a\"`` “b”")
    }

    /// A backtick nothing answers makes no code: the quote after it is prose's.
    @Test func anUnclosedBacktickIsNoCode() {
        let text = "Cena je 5` a “víc”"
        #expect(all(text) == text)
    }

    @Test func aBlockBetweenFencesIsCode() {
        let text = "Úvod s “uvozovkami”.\n\n```sh\necho “a” ‘b’\n```\n\nZávěr s “uvozovkami”."
        #expect(all(text) == "Úvod s “uvozovkami”.\n\n```sh\necho \"a\" 'b'\n```\n\nZávěr s “uvozovkami”.")
        // A block nobody closed runs to the end, as the blog reads it.
        #expect(all("```\nx = “1”\ny = “2”") == "```\nx = \"1\"\ny = \"2\"")
        // Tildes fence nothing on the blog: its lines are prose.
        #expect(all("~~~\n“a”\n~~~") == "~~~\n“a”\n~~~")
        // However far the fence is indented; four spaces alone make no code.
        #expect(all("      ```\n“a”\n\t```\n“b”") == "      ```\n\"a\"\n\t```\n“b”")
        #expect(all("    x = “a”") == "    x = “a”")
        // A longer run closes, a shorter one or one with words after it does not.
        #expect(all("````\n“a”\n```\n“b”\n`````\n“c”") == "````\n\"a\"\n```\n\"b\"\n`````\n“c”")
        #expect(all("```\n“a”\n``` konec\n“b”") == "```\n\"a\"\n``` konec\n\"b\"")
    }

    /// The header of a post is not code: a title's quotes are prose.
    @Test func aHeaderIsLeftAlone() {
        let text = "---\ntitle: Jak jsem „skoro“ vyhrál\n---\n\nText."
        #expect(all(text) == text)
    }

    /// The text is as long as it was: one mark stands for one.
    @Test func theTextKeepsItsLength() {
        let text = "`“a” ‘b’ „c“`"
        #expect((all(text) as NSString).length == (text as NSString).length)
    }

    /// Only the lines just written into are looked over.
    @Test func onlyTheTouchedLinesAreLookedOver() {
        let text = "`“stará”`\n`“nová”`"
        let second = (text as NSString).range(of: "nová")
        #expect(CodeQuotes.straightened(text, touched: second) == "`“stará”`\n`\"nová\"`")
    }

    /// A new post is its writer's whole: all its code is put right.
    @Test func aNewTextIsSettledWhole() {
        #expect(CodeQuotes.settled("Řekl „ahoj“ a `echo “ahoj”`.\n\n```\nx = ‘1’\n```") == "Řekl „ahoj“ a `echo \"ahoj\"`.\n\n```\nx = '1'\n```")
        #expect(CodeQuotes.settled("Jen „próza“.") == "Jen „próza“.")
    }

    /// Over a post from the blog, only what was written here is put
    /// right: a post merely opened does not read as changed.
    @Test func aPostFromTheBlogIsSettledOnlyWhereItWasWritten() {
        let blogs = "Starý řádek s `“kódem”`.\n\n```\na = “1”\n```"
        #expect(CodeQuotes.settled(blogs, over: blogs) == blogs)
        let edited = "Starý řádek s `“kódem”`.\nNový s `echo “x”`.\n\n```\na = “1”\nb = “2”\n```"
        #expect(CodeQuotes.settled(edited, over: blogs) == "Starý řádek s `“kódem”`.\nNový s `echo \"x\"`.\n\n```\na = “1”\nb = \"2\"\n```")
    }
}
