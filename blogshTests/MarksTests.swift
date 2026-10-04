import Foundation
import Testing
@testable import blogsh

/// The marks over the text. They are a port of the /write/ page's own
/// `applyMark`, and the two have to agree: a post marked up on the phone
/// is the post the page would have made.
@Suite struct MarksTests {
    private struct Case: Decodable {
        let text: String
        let start: Int
        let end: Int
        let kind: String
    }

    private struct Expected: Decodable, Equatable {
        let value: String
        let start: Int
        let end: Int
    }

    private func apply(_ text: String, _ start: Int, _ end: Int, _ kind: Marks.Kind) -> Expected {
        let out = Marks.apply(text, selection: NSRange(location: start, length: end - start), kind: kind)
        return Expected(value: out.value, start: out.selection.location, end: out.selection.location + out.selection.length)
    }

    /// Every kind, on every text and every selection of the set the port
    /// was first checked against. The expected answers are the page's own
    /// for all but sixteen cases -- a line mark on an empty first line,
    /// where the page was wrong and the port is not.
    @Test func everyCaseOfTheSet() throws {
        let cases = try JSONDecoder().decode([Case].self, from: Fixture.data("marks-cases"))
        let expected = try JSONDecoder().decode([Expected].self, from: Fixture.data("marks-expected"))
        #expect(cases.count == expected.count)
        #expect(cases.count > 1500)
        for (index, one) in cases.enumerated() {
            let kind = try #require(Marks.Kind(rawValue: one.kind))
            let got = apply(one.text, one.start, one.end, kind)
            #expect(got == expected[index], "case \(index): \(one.kind) on \(one.text.debugDescription) [\(one.start), \(one.end)]")
        }
    }

    @Test func boldOnNothingLeavesTheCaretBetweenTheStars() {
        #expect(apply("", 0, 0, .bold) == Expected(value: "****", start: 2, end: 2))
    }

    @Test func aLinkOnNothingSelectsItsAddress() {
        #expect(apply("", 0, 0, .link) == Expected(value: "[text](https://)", start: 7, end: 15))
    }

    @Test func aHeadingStartsItsLine() {
        #expect(apply("", 0, 0, .h2) == Expected(value: "## ", start: 3, end: 3))
    }

    @Test func aFenceOpensWithTheCaretInside() {
        #expect(apply("", 0, 0, .fence) == Expected(value: "```\n\n```", start: 4, end: 4))
    }

    /// A selection is counted the way the text field counts it, in UTF-16:
    /// a letter with a hook is one, and the mark lands around the word.
    @Test func aSelectionWithCzechLettersIsWrappedWhole() {
        let text = "žluťoučký kůň"
        let got = apply(text, 0, (text as NSString).length, .bold)
        #expect(got.value == "**žluťoučký kůň**")
    }
}
