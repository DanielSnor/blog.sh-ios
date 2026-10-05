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
        #expect(page.contains("<div class=\"post-header\"><h1>A &lt;Title&gt;</h1></div><div class=\"post-body\"><p>x</p></div>"))
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
