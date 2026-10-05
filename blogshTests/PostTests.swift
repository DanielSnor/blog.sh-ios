import Foundation
import Testing
@testable import blogsh

/// A post on its way to the blog: its file, its pictures' names, and how
/// much all of it weighs against the server's limit.
@Suite struct PostTests {
    // MARK: the markdown file

    @Test func theHeaderHoldsWhatTheFormHasFieldsFor() {
        #expect(Markdown.frontMatter(title: " Hello ", tags: "a, b") == "---\ntitle: Hello\ntags: a, b\n---\n\n")
        #expect(Markdown.frontMatter(title: "Hello", tags: "", publish: true) == "---\ntitle: Hello\npublish: yes\n---\n\n")
    }

    @Test func nothingFilledInIsNoHeader() {
        #expect(Markdown.frontMatter(title: "  ", tags: " , ") == "")
    }

    /// A title in quotes or tags written the YAML way would be read by the
    /// engine as something else than the words.
    @Test func quotesBracketsAndHashesAreTakenOff() {
        #expect(Markdown.frontMatter(title: #""Hello""#, tags: "") == "---\ntitle: Hello\n---\n\n")
        #expect(Markdown.frontMatter(title: "", tags: "#ruby, [blog.sh], 'x'") == "---\ntags: ruby, blog.sh, x\n---\n\n")
        #expect(Markdown.frontMatter(title: "", tags: "[a, b]") == "---\ntags: a, b\n---\n\n")
    }

    @Test func theFileIsItsHeaderAndItsTextWithOneNewlineAtTheEnd() {
        #expect(Markdown.file(title: "T", tags: "", body: "\n  text \n\n") == "---\ntitle: T\n---\n\ntext\n")
        #expect(Markdown.file(title: "", tags: "", body: "text") == "text\n")
    }

    /// A text that itself opens with --- would be read as a header.
    @Test func aTextOpeningWithDashesGetsAnEmptyHeaderBeforeIt() {
        #expect(Markdown.file(title: "", tags: "", body: "--- and so on") == "---\n---\n\n--- and so on\n")
    }

    @Test func theFileIsNamedByItsTitleFolded() {
        #expect(Markdown.fileName(title: "Žluťoučký kůň úpěl", body: "x") == "zlutoucky-kun-upel.md")
        #expect(Markdown.fileName(title: "", body: "one two three four five six seven") == "one-two-three-four-five-six.md")
        #expect(Markdown.fileName(title: "", body: "") == "post.md")
        #expect(Markdown.fileName(title: "!!!", body: "") == "post.md")
        let long = Markdown.fileName(title: String(repeating: "abcdefghij ", count: 6), body: "")
        #expect(long.count == 43)
    }

    // MARK: names of pictures and videos

    @Test func aPictureKeepsItsOwnNameFolded() {
        #expect(Pictures.safeName("IMG 1234.HEIC", index: 1) == "img-1234.jpg")
        #expect(Pictures.safeName("Žába na prameni.png", index: 1) == "zaba-na-prameni.jpg")
        #expect(Pictures.safeName("a.b.c.jpeg", index: 1) == "a-b-c.jpg")
    }

    @Test func aPictureWithoutANameIsNumbered() {
        #expect(Pictures.safeName(nil, index: 3) == "photo-3.jpg")
        #expect(Pictures.safeName("???.jpg", index: 2) == "photo-2.jpg")
        #expect(Pictures.safeName(nil, index: 1, stem: "video", ext: "mp4") == "video-1.mp4")
    }

    @Test func twoPicturesFoldingToOneNameAreToldApart() {
        #expect(Pictures.freeName("a.jpg", taken: []) == "a.jpg")
        #expect(Pictures.freeName("a.jpg", taken: ["a.jpg"]) == "a-2.jpg")
        #expect(Pictures.freeName("a.jpg", taken: ["a.jpg", "a-2.jpg"]) == "a-3.jpg")
    }

    // MARK: the mark of a shot in the text

    private func shot(_ name: String, bytes: Int = 10, alt: String = "", kind: Shot.Kind = .picture) -> Shot {
        Shot(name: name, data: Data(count: bytes), width: 10, height: 10, alt: alt, kind: kind)
    }

    @Test func aPictureIsOneMarkAVideoTwo() {
        #expect(shot("cat.jpg", alt: " a cat ").mark == "![a cat](cat.jpg)")
        #expect(shot("clip.mp4", alt: "", kind: .video).mark == "!![](clip.mp4)")
    }

    @Test func aShotsMarkIsFoundWhateverItsDescriptionSays() throws {
        let pattern = try NSRegularExpression(pattern: shot("cat.jpg").markPattern)
        func found(_ text: String) -> Bool { pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
        #expect(found("before ![a cat](cat.jpg) after"))
        #expect(found("!![](cat.jpg)"))
        #expect(!found("![a cat](cat2.jpg)"))
        // The dot of the name is a dot, not any letter.
        #expect(!found("![a cat](catxjpg)"))
    }

    // MARK: what an edit may do to a post's pictures

    /// The engine refuses an edit from the app that leaves a post with
    /// fewer pictures than it had; the app says so before the save.
    @Test func takingAPictureOutIsFewer() {
        let media = ["01.jpg", "02.jpg"]
        #expect(!Kept.fewer(media: media, shots: [], text: "![a](01.jpg) ![b](02.jpg)"))
        #expect(Kept.fewer(media: media, shots: [], text: "![a](01.jpg)"))
        #expect(Kept.fewer(media: media, shots: [], text: "no pictures at all"))
        #expect(Kept.dropped(media: media, text: "![a](01.jpg)") == ["02.jpg"])
    }

    @Test func oneOutAndAnotherInIsAsManyAsBefore() {
        let new = shot("photo-3.jpg")
        #expect(!Kept.fewer(media: ["01.jpg", "02.jpg"], shots: [new], text: "![a](01.jpg) ![c](photo-3.jpg)"))
    }

    /// A picture chosen but not put into the text is not in the post.
    @Test func aNewPictureCountsOnlyOnceItIsNamed() {
        let new = shot("photo-3.jpg")
        #expect(Kept.fewer(media: ["01.jpg", "02.jpg"], shots: [new], text: "![a](01.jpg)"))
    }

    /// The engine counts pictures and videos apart: a picture does not
    /// stand in for a video taken out.
    @Test func aPictureDoesNotStandInForAVideo() {
        let picture = shot("photo-2.jpg")
        let video = shot("clip.mp4", kind: .video)
        #expect(Kept.fewer(media: ["01.mov"], shots: [picture], text: "![a](photo-2.jpg)"))
        #expect(!Kept.fewer(media: ["01.mov"], shots: [video], text: "!![a](clip.mp4)"))
        #expect(Kept.isVideo("01.MOV") && Kept.isVideo("a.mp4") && !Kept.isVideo("a.jpg") && !Kept.isVideo("mov"))
    }

    @Test func aPostWithoutPicturesHasNothingToLose() {
        #expect(!Kept.fewer(media: [], shots: [], text: "text"))
        #expect(Kept.dropped(media: [], text: "text").isEmpty)
    }

    // MARK: the weight of a delivery

    @Test func base64IsAThirdLargerAndCountsItsLineBreaks() {
        #expect(encodedSize(0) == 1)
        #expect(encodedSize(3) == 5)
        #expect(encodedSize(57) == 78)
    }

    @Test func aDeliveryOfTextAloneStillWeighsItsEnvelope() {
        #expect(Delivery.wireBytes(shots: [], textBytes: 0) == 352)
    }

    /// The server measures the encoded stream: of a limit of one megabyte
    /// about three quarters are room for files.
    @Test func theLimitIsMeasuredOnTheEncodedStream() {
        #expect(!Delivery.over(shots: [shot("a.jpg", bytes: 700 * 1024)], textBytes: 100, maxMb: 1))
        #expect(Delivery.over(shots: [shot("a.jpg", bytes: 800 * 1024)], textBytes: 100, maxMb: 1))
        #expect(Delivery.over(shots: [shot("a.jpg", bytes: 400 * 1024), shot("b.jpg", bytes: 400 * 1024)], textBytes: 100, maxMb: 1))
    }

    @Test func aServerThatNamesNoLimitRefusesNothing() {
        #expect(!Delivery.over(shots: [shot("a.jpg", bytes: 5 * 1_048_576)], textBytes: 100, maxMb: 0))
    }

    @Test func sizesAreSaidInKilobytesThenMegabytes() {
        #expect(Delivery.size(0) == "0 kB")
        #expect(Delivery.size(1) == "1 kB")
        #expect(Delivery.size(1536) == "2 kB")
        #expect(Delivery.size(1023 * 1024) == "1023 kB")
        // The decimal mark is the reader's own; the unit is not.
        #expect(Delivery.size(5 * 1_048_576).hasPrefix("5"))
        #expect(Delivery.size(5 * 1_048_576).hasSuffix(" MB"))
    }

    @Test func whatIsOnTheWayEndsWithItsSize() {
        #expect(Delivery.describe(shots: [], textBytes: 10).hasSuffix(", 1 kB"))
        let said = Delivery.describe(shots: [shot("a.jpg", bytes: 1024), shot("b.jpg", bytes: 1024), shot("c.mp4", bytes: 1024, kind: .video)], textBytes: 0)
        #expect(said.hasPrefix("2 "))
        #expect(said.contains(", 1 "))
        #expect(said.hasSuffix(", 3 kB"))
    }
}
