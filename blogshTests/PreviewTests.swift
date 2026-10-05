import Foundation
import Testing
@testable import blogsh

/// The preview of a post while it is written. It is a port of the /write/
/// page's own `renderMarkdown`, and the two have to draw the same page.
@Suite struct PreviewTests {
    private struct Case: Decodable {
        let markdown: String
        let html: String
    }

    private let shots: [String: Preview.Shown] = [
        "cat.jpg": .picture("data:image/jpeg;base64,AAAA"),
        "clip.mp4": .video("data:video/mp4;base64,BBBB"),
        "a&b.jpg": .picture("data:x\"y"),
    ]

    /// Every case as the page's own JavaScript rendered it: the fixture is
    /// its output, not this port's.
    @Test func everyCaseAsThePageRendersIt() throws {
        let cases = try JSONDecoder().decode([Case].self, from: Fixture.data("preview-cases"))
        #expect(cases.count > 80)
        for (index, one) in cases.enumerated() {
            #expect(Preview.render(one.markdown, shots: shots) == one.html, "case \(index): \(one.markdown.debugDescription)")
        }
    }

    /// The one departure from the page: the line that cuts a post in two
    /// is drawn as a hairline, not printed as words.
    @Test func theLineThatCutsAPostIsAHairline() {
        #expect(Preview.render("Intro.\n\n//--more--//\n\nRest.") == "<p>Intro.</p>\n<hr class=\"teaser-end\">\n<p>Rest.</p>")
        // Alone on its line is enough, as the engine reads it: no blank lines needed, spaces around it allowed.
        #expect(Preview.render("Intro.\n  //--more--//\t\nRest.") == "<p>Intro.</p>\n<hr class=\"teaser-end\">\n<p>Rest.</p>")
    }

    @Test func theSameWordsElsewhereStayWords() {
        #expect(Preview.render("see //--more--// here") == "<p>see //--more--// here</p>")
        #expect(Preview.render("```\n//--more--//\n```") == "<pre class=\"code-block\"><code>//--more--//</code></pre>")
        #expect(Preview.document(title: "", body: "", lang: "en").contains("hr.teaser-end{"))
    }

    // MARK: pictures in a row

    private let three: [String: Preview.Shown] = ["a.jpg": .picture("A"), "b.jpg": .picture("B"), "c.jpg": .picture("C"),
                                                   "clip.mp4": .video("V")]
    private func fig(_ source: String, _ alt: String = "", span: Bool = false) -> String {
        "<figure\(span ? " class=\"span-2\"" : "")><img src=\"\(source)\" alt=\"\(alt)\"></figure>"
    }

    /// The second departure from the page, and toward the blog: pictures
    /// in a row are a gallery, in the markup the engine writes.
    @Test func twoPicturesInARowAreAGallery() {
        #expect(Preview.render("![x](a.jpg)\n\n![y](b.jpg)", shots: three)
                == "<div class=\"photo-grid\">" + fig("A", "x") + fig("B", "y") + "</div>")
    }

    @Test func anOddLastPictureSpansBothColumns() {
        #expect(Preview.render("![](a.jpg)\n\n![](b.jpg)\n\n\n![](c.jpg)\n", shots: three)
                == "<div class=\"photo-grid\">" + fig("A") + fig("B") + fig("C", span: true) + "</div>")
    }

    @Test func onePictureAloneIsNoGallery() {
        #expect(Preview.render("![](a.jpg)", shots: three) == fig("A"))
        #expect(Preview.render("text\n\n![](a.jpg)\n\ntext", shots: three) == "<p>text</p>\n" + fig("A") + "\n<p>text</p>")
    }

    /// Text between two pictures keeps them one under another, as the
    /// engine's cheat sheet says; so does a video, which is no picture.
    @Test func textOrAVideoBetweenPicturesBreaksTheRow() {
        #expect(Preview.render("![](a.jpg)\n\ntext\n\n![](b.jpg)", shots: three) == fig("A") + "\n<p>text</p>\n" + fig("B"))
        let withClip = Preview.render("![](a.jpg)\n\n!![](clip.mp4)\n\n![](b.jpg)", shots: three)
        #expect(!withClip.contains("photo-grid"))
        #expect(withClip.contains("<video"))
    }

    @Test func twoGalleriesStayTwo() {
        let html = Preview.render("![](a.jpg)\n\n![](b.jpg)\n\n## h\n\n![](c.jpg)\n\n![](a.jpg)", shots: three)
        #expect(html == "<div class=\"photo-grid\">" + fig("A") + fig("B") + "</div>\n<h3>h</h3>\n<div class=\"photo-grid\">" + fig("C") + fig("A") + "</div>")
    }

    /// A picture the device cannot show still holds its place in the row;
    /// one glued to a line of text is no part of it -- the blog would
    /// refuse that post, and the box says so.
    @Test func aMissingPictureHoldsItsPlaceAGluedOneDoesNot() {
        let missing = Preview.render("![](a.jpg)\n\n![](nowhere.jpg)", shots: three)
        #expect(missing.hasPrefix("<div class=\"photo-grid\">" + fig("A") + "<figure><div class=\"no-preview\">"))
        let glued = Preview.render("![](a.jpg)\n\n![](b.jpg)\ntext", shots: three)
        #expect(!glued.contains("photo-grid"))
        #expect(glued.hasPrefix(fig("A") + "\n<figure><div class=\"no-preview\">b.jpg: a picture has to stand"))
    }

    @Test func thePageKnowsHowToLayAGalleryOutWithoutTheBlog() {
        let page = Preview.document(title: "", body: "", lang: "en")
        let own = try! #require(page.range(of: ".photo-grid{display:grid"))
        let blogs = try! #require(page.range(of: "<link rel=\"stylesheet\""))
        // Before the blog's stylesheets, so theirs has the last word.
        #expect(own.lowerBound < blogs.lowerBound)
        #expect(page.contains(".photo-grid .span-2{grid-column:1/-1}"))
    }

    @Test func whatWasTypedCannotBecomeMarkup() {
        #expect(Preview.render("<script>alert(1)</script>") == "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>")
        #expect(!Preview.render("[x](javascript:alert(1))").contains("href"))
        #expect(!Preview.render("![a\" onerror=\"x](cat.jpg)", shots: shots).contains("\" onerror=\"x\""))
    }

    /// A picture glued to a line of text is a post the blog refuses; the
    /// preview says so where the picture would stand.
    @Test func aPictureNotOnALineOfItsOwnIsSaidSo() {
        let html = Preview.render("text\n![a](cat.jpg)", shots: shots)
        #expect(html.contains("no-preview"))
        #expect(html.contains("cat.jpg: a picture has to stand on a line of its own"))
        #expect(!html.contains("<img"))
    }

    /// A video too large to hand a page is shown by one frame of it.
    @Test func aVideoMayBeShownByAFrame() {
        let html = Preview.render("!![a clip](clip.mp4)", shots: ["clip.mp4": .frame("data:image/jpeg;base64,CCCC")])
        #expect(html == "<figure><img src=\"data:image/jpeg;base64,CCCC\" alt=\"a clip\"><figcaption>a clip</figcaption></figure>")
    }

    @Test func theSentencesComeInTheReadersLanguage() {
        let words = Preview.Words(missing: { "chybí \($0)" }, glued: { "přilepený \($0)" })
        #expect(Preview.render("![a](x.jpg)", words: words).contains("chybí x.jpg"))
        #expect(Preview.render("a\n![a](x.jpg)", words: words).contains("přilepený x.jpg"))
    }

    @Test func thePageWearsTheBlogsStylesheetsAndItsTitle() {
        let page = Preview.document(title: " A <Title> ", body: "<p>x</p>", lang: "cs")
        #expect(page.contains("<html lang=\"cs\">"))
        #expect(page.contains("<base href=\"/\">"))
        #expect(page.contains("<link rel=\"stylesheet\" href=\"/assets/css/colors.css\"><link rel=\"stylesheet\" href=\"/assets/css/site.css\">"))
        // Nested as the engine's post page is: the stylesheet's margins count on it.
        #expect(page.contains("<main><div class=\"card\"><article><div class=\"post-header\"><div class=\"post-body\">"
                              + "<h1>A &lt;Title&gt;</h1><div class=\"content\"><p>x</p></div></div></div></article></div></main>"))
        #expect(!Preview.document(title: "  ", body: "", lang: "en").contains("<h1>"))
    }

    /// A post opened for editing comes with its header; the preview shows
    /// the title the header gives and the text under it.
    @Test func aTextWithAHeaderIsItsTitleAndItsBody() {
        let both = Preview.parts(of: "---\ntitle: Nouzovka\ntags: a, b\n---\n\nText.\n")
        #expect(both.title == "Nouzovka")
        #expect(both.body == "\nText.\n")
        #expect(Preview.parts(of: "Just text.").title == "")
        #expect(Preview.parts(of: "Just text.").body == "Just text.")
        #expect(Preview.parts(of: "---\n---\n\nText.").body == "\nText.")
        #expect(Preview.parts(of: "---\nnever closed").body == "---\nnever closed")
    }
}

/// How a post begins, where a post is picked.
@Suite struct LedeTests {
    @Test func upToTheCutTheAuthorMade() {
        let lede = Lede.of("---\ntitle: T\n---\n\nFirst.\n\nSecond.\n\n//--more--//\n\nThird.")
        #expect(lede.words == "First.\n\nSecond.")
    }

    @Test func withoutACutTheFirstParagraph() {
        #expect(Lede.of("First line\nstill first.\n\nSecond.").words == "First line still first.")
    }

    @Test func theMarksAreTakenOff() {
        let lede = Lede.of("## A **bold** [link](https://x.cz/a_(b)) with `code`, *em* and ~~gone~~\n\nrest")
        #expect(lede.words == "A bold link with code, em and gone")
        #expect(Lede.of("> quoted words").words == "quoted words")
    }

    /// A post that opens with its picture begins with its words all the
    /// same; one that is only a picture is known by the description.
    @Test func aPictureIsNotWordsButItsDescriptionIsKept() {
        let both = Lede.of("![a cat](cat.jpg)\n\nThe words.")
        #expect(both.words == "The words.")
        #expect(both.picture == "a cat")
        let only = Lede.of("---\ntags: x\n---\n\n![](one.jpg)\n\n!![the waterfall](clip.mp4)\n")
        #expect(only.words == "")
        #expect(only.picture == "the waterfall")
    }

    @Test func aPostWithNothingHasNothing() {
        #expect(Lede.of("---\ntitle: T\n---\n\n") == Lede(words: "", picture: nil))
        #expect(Lede.of("![](one.jpg)") == Lede(words: "", picture: nil))
    }

    @Test func codeIsNotHowAPostBegins() {
        #expect(Lede.of("```\nputs 1\n```\n\nThen the words.").words == "Then the words.")
    }

    /// A cut on the first line leaves nothing above it: the post begins after it.
    @Test func aCutAtTheVeryTopIsStepedOver() {
        #expect(Lede.of("//--more--//\n\nAfter the cut.\n\nMore.").words == "After the cut.")
    }

    @Test func aLongBeginningEndsOnAWord() {
        let long = Array(repeating: "slovo", count: 300).joined(separator: " ")
        let words = Lede.of(long).words
        #expect(words.count <= Lede.limit + 1)
        #expect(words.hasSuffix("slovo…"))
    }
}
