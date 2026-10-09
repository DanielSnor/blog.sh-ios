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

    // MARK: a description, on its card and in the text -- one thing

    /// Typed on a card after the picture went into the text: the mark
    /// there takes it, letter by letter.
    @Test func aDescriptionTypedOnACardGoesIntoItsMark() {
        var text = "Before.\n\n![](cat.jpg)\n\nAfter."
        text = Kept.typed(text, name: "cat.jpg", after: "a")
        text = Kept.typed(text, name: "cat.jpg", after: "a cat")
        #expect(text == "Before.\n\n![a cat](cat.jpg)\n\nAfter.")
    }

    /// The other way: typed into the mark in the text, it is on the card.
    @Test func aDescriptionTypedIntoTheTextGoesOntoItsCard() {
        let cards = [shot("dog.jpg"), shot("clip.mp4", alt: "old", kind: .video), shot("unused.jpg", alt: "kept")]
        let heard = Kept.heard(cards, from: "![A dog in the grass](dog.jpg)\n\n!![the clip](clip.mp4)\n")
        #expect(heard.map(\.alt) == ["A dog in the grass", "the clip", "kept"])
        // A mark that says nothing empties its card; a picture the text
        // does not name keeps its own words for when it is put in.
        #expect(Kept.heard([shot("dog.jpg", alt: "x")], from: "![](dog.jpg)")[0].alt == "")
        #expect(Kept.heard([shot("dog.jpg", alt: "x")], from: "No picture here.")[0].alt == "x")
    }

    /// The report this is pinned for, both halves of it. Written in the
    /// text, the words are on the card; on the card they are added to,
    /// not typed again from the start; and added to in the text once
    /// more, the card has that too.
    @Test func writtenHereOrThereItIsOneDescription() {
        var cards = [shot("dog.jpg")]
        var text = "![Pes v trávě](dog.jpg)\n\nText.\n"
        cards = Kept.heard(cards, from: text)
        #expect(cards[0].alt == "Pes v trávě")

        // On the card: ", plazí se" after what is there.
        var before = cards.map(\.alt)
        cards[0].alt += ", plazí se"
        text = Kept.retitled(text, shots: cards, before: before)
        #expect(text == "![Pes v trávě, plazí se](dog.jpg)\n\nText.\n")
        // ...which the card hears back and has nothing to change.
        #expect(Kept.heard(cards, from: text).map(\.alt) == cards.map(\.alt))

        // Back in the text: " a schovává se".
        text = text.replacingOccurrences(of: "plazí se]", with: "plazí se a schovává se]")
        cards = Kept.heard(cards, from: text)
        #expect(cards[0].alt == "Pes v trávě, plazí se a schovává se")

        // And from the card once more.
        before = cards.map(\.alt)
        cards[0].alt = "Pes"
        text = Kept.retitled(text, shots: cards, before: before)
        #expect(text == "![Pes](dog.jpg)\n\nText.\n")
    }

    /// Neither way undoes a space just typed at the end of a word: what
    /// says the same but for its spaces is left as it is, in both places.
    @Test func aSpaceTypedAtTheEndIsNotTakenBack() {
        // In the text: "![Pes ](dog.jpg)" while the card still has "Pes".
        let card = shot("dog.jpg", alt: "Pes")
        #expect(Kept.heard([card], from: "![Pes ](dog.jpg)")[0].alt == "Pes")
        #expect(Kept.typed("![Pes ](dog.jpg)", name: "dog.jpg", after: "Pes") == "![Pes ](dog.jpg)")
        // On the card: "Pes " while the text still has "![Pes](dog.jpg)".
        #expect(Kept.typed("![Pes](dog.jpg)", name: "dog.jpg", after: "Pes ") == "![Pes](dog.jpg)")
        // The next letter goes through, from either side.
        #expect(Kept.typed("![Pes](dog.jpg)", name: "dog.jpg", after: "Pes v") == "![Pes v](dog.jpg)")
        #expect(Kept.heard([card], from: "![Pes v](dog.jpg)")[0].alt == "Pes v")
        #expect(Kept.typed("![Pes ](dog.jpg)", name: "dog.jpg", after: "Pes v") == "![Pes v](dog.jpg)")
    }

    // The two places as the forms wire them: a change of the text is
    // heard by the cards, a change of a card is typed into the text, each
    // until nothing moves.
    private func settle(_ text: inout String, _ cards: inout [Shot], rounds: inout Int) {
        for round in 0..<8 {
            rounds = round
            let before = cards.map(\.alt)
            cards = Kept.heard(cards, from: text)
            let next = Kept.retitled(text, shots: cards, before: before)
            if next == text && cards.map(\.alt) == before { return }
            text = next
        }
        rounds = 8
    }

    /// A square bracket in a description: the engine takes it (its own
    /// pattern for a picture reads the description up to the last "](" of
    /// the line), so the two places must stay one through it.
    @Test func aBracketInADescriptionDoesNotPartTheTwo() {
        var cards = [shot("dog.jpg", alt: "a")]
        var text = "Before.\n\n![a](dog.jpg)\n\nAfter."
        var rounds = 0
        for typed in ["a]", "a]b", "a]b [c]", "a]b [c] d"] {
            let before = cards.map(\.alt)
            cards[0].alt = typed
            text = Kept.retitled(text, shots: cards, before: before)
            settle(&text, &cards, rounds: &rounds)
            #expect(text == "Before.\n\n![\(typed)](dog.jpg)\n\nAfter.")
            #expect(cards[0].alt == typed)
        }
        // ...and from the text's side.
        text = "![x [y] z](dog.jpg)"
        settle(&text, &cards, rounds: &rounds)
        #expect(cards[0].alt == "x [y] z")
    }

    /// Typed at random into either place, a letter at a time: after each
    /// letter the two say the same, what was just typed stands as typed,
    /// and they stop moving at once.
    @Test func typedAtRandomIntoEitherPlaceTheTwoStayOne() {
        var seed: UInt64 = 20261007
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        let letters = Array("ab č,. ]")
        for _ in 0..<300 {
            var cards = [shot("dog.jpg"), shot("clip.mp4", kind: .video)]
            var text = "One.\n\n![](dog.jpg)\n\nTwo.\n\n!![](clip.mp4)\n"
            for _ in 0..<40 {
                let which = next(2), name = cards[which].name
                var rounds = 0
                if next(2) == 0 {
                    // On the card: a letter at its end, or its last letter taken off.
                    let before = cards.map(\.alt)
                    if next(5) == 0, !cards[which].alt.isEmpty { cards[which].alt.removeLast() }
                    else { cards[which].alt.append(letters[next(letters.count)]) }
                    let typed = cards[which].alt
                    text = Kept.retitled(text, shots: cards, before: before)
                    settle(&text, &cards, rounds: &rounds)
                    #expect(cards[which].alt == typed)
                } else {
                    // In the text: a letter at the end of the picture's description there.
                    guard let was = Kept.described(name, in: text) else { continue }
                    let grown = was + String(letters[next(letters.count)])
                    text = text.replacingOccurrences(of: "[\(was)](\(name))", with: "[\(grown)](\(name))")
                    let typed = text
                    settle(&text, &cards, rounds: &rounds)
                    #expect(text == typed)
                }
                #expect(rounds <= 1)
                for card in cards {
                    let said = Kept.described(card.name, in: text)
                    #expect(said != nil)
                    #expect(Kept.oneLine(said ?? "") == Kept.oneLine(card.alt))
                }
            }
        }
    }

    /// Several pictures in one text, their names alike and their marks
    /// one after another: each card is its own picture's and no other's.
    @Test func severalPicturesEachKeepToTheirOwnMark() {
        var cards = [shot("photo-1.jpg"), shot("photo-11.jpg"), shot("a-photo-1.jpg"), shot("clip.mp4", kind: .video)]
        var text = "![one](photo-1.jpg)\n\n![eleven](photo-11.jpg)\n\n![other](a-photo-1.jpg)\n\n!![film](clip.mp4)\n"
        var rounds = 0
        settle(&text, &cards, rounds: &rounds)
        #expect(cards.map(\.alt) == ["one", "eleven", "other", "film"])

        // The second card written on: only the second mark moves.
        var before = cards.map(\.alt)
        cards[1].alt = "eleven, changed"
        text = Kept.retitled(text, shots: cards, before: before)
        settle(&text, &cards, rounds: &rounds)
        #expect(text == "![one](photo-1.jpg)\n\n![eleven, changed](photo-11.jpg)\n\n![other](a-photo-1.jpg)\n\n!![film](clip.mp4)\n")
        #expect(cards.map(\.alt) == ["one", "eleven, changed", "other", "film"])

        // The third mark written in: only the third card moves.
        text = text.replacingOccurrences(of: "![other]", with: "![other one]")
        settle(&text, &cards, rounds: &rounds)
        #expect(cards.map(\.alt) == ["one", "eleven, changed", "other one", "film"])

        // Two cards given the same words stay two descriptions.
        before = cards.map(\.alt)
        cards[0].alt = "same"
        text = Kept.retitled(text, shots: cards, before: before)
        before = cards.map(\.alt)
        cards[2].alt = "same"
        text = Kept.retitled(text, shots: cards, before: before)
        before = cards.map(\.alt)
        cards[0].alt = "same, first"
        text = Kept.retitled(text, shots: cards, before: before)
        settle(&text, &cards, rounds: &rounds)
        #expect(text == "![same, first](photo-1.jpg)\n\n![eleven, changed](photo-11.jpg)\n\n![same](a-photo-1.jpg)\n\n!![film](clip.mp4)\n")
    }

    /// Two marks on one line -- which the engine refuses, but the text
    /// may hold while it is being written: each is still read as itself.
    @Test func twoMarksOnOneLineAreReadEachAsItself() {
        let text = "![x](a.jpg) ![y](b.jpg)\n\n![p](c.jpg)![q](d.jpg)"
        #expect(Kept.described("a.jpg", in: text) == "x")
        #expect(Kept.described("b.jpg", in: text) == "y")
        #expect(Kept.described("c.jpg", in: text) == "p")
        #expect(Kept.described("d.jpg", in: text) == "q")
        #expect(Kept.typed(text, name: "b.jpg", after: "why") == "![x](a.jpg) ![why](b.jpg)\n\n![p](c.jpg)![q](d.jpg)")
    }

    /// The same at random, with three pictures whose marks stand in a row.
    @Test func typedAtRandomWithSeveralPicturesEachStaysItsOwn() {
        var seed: UInt64 = 7
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        let letters = Array("ab č,.]")
        for _ in 0..<200 {
            var cards = [shot("photo-1.jpg"), shot("photo-11.jpg"), shot("photo-2.jpg")]
            var text = "![](photo-1.jpg)\n\n![](photo-11.jpg)\n\n![](photo-2.jpg)\n"
            var mine = ["", "", ""]
            for _ in 0..<45 {
                let which = next(3), name = cards[which].name
                var rounds = 0
                if next(2) == 0 {
                    let before = cards.map(\.alt)
                    cards[which].alt.append(letters[next(letters.count)])
                    mine[which] = cards[which].alt
                    text = Kept.retitled(text, shots: cards, before: before)
                } else {
                    guard let was = Kept.described(name, in: text) else { continue }
                    let grown = was + String(letters[next(letters.count)])
                    text = text.replacingOccurrences(of: "[\(was)](\(name))", with: "[\(grown)](\(name))")
                    mine[which] = grown
                }
                settle(&text, &cards, rounds: &rounds)
                #expect(rounds <= 1)
                // Every picture says what was last written of IT, in both places.
                for (index, card) in cards.enumerated() {
                    #expect(Kept.oneLine(card.alt) == Kept.oneLine(mine[index]))
                    #expect(Kept.oneLine(Kept.described(card.name, in: text) ?? "?") == Kept.oneLine(mine[index]))
                }
            }
        }
    }

    /// The mark taken out of the text: the card keeps its words, and
    /// gives them back when the picture is put in again.
    @Test func aCardKeepsItsWordsWhileItsPictureIsOutOfTheText() {
        var cards = [shot("dog.jpg", alt: "a dog")]
        var text = "![a dog](dog.jpg)\n"
        var rounds = 0
        text = "Nothing.\n"
        settle(&text, &cards, rounds: &rounds)
        #expect(cards[0].alt == "a dog")
        let before = cards.map(\.alt)
        cards[0].alt = "a dog, asleep"
        #expect(Kept.retitled(text, shots: cards, before: before) == "Nothing.\n")
        text = Kept.placed(cards[0].mark, in: text, at: nil).text
        settle(&text, &cards, rounds: &rounds)
        #expect(text == "Nothing.\n\n![a dog, asleep](dog.jpg)\n")
        #expect(cards[0].alt == "a dog, asleep")
    }

    @Test func aVideosTwoMarksFollowItsCardTheSameWay() {
        #expect(Kept.typed("!![](clip.mp4)\n", name: "clip.mp4", after: "a clip") == "!![a clip](clip.mp4)\n")
        #expect(Kept.heard([shot("clip.mp4", kind: .video)], from: "!![a clip](clip.mp4)")[0].alt == "a clip")
    }

    /// A picture standing in the text twice: the card is the first mark's;
    /// the second follows while it says the same, and keeps its own words
    /// once it has some.
    @Test func aPictureNamedTwiceFollowsWhileItSaysTheSame() {
        #expect(Kept.typed("![a](cat.jpg)\n\n![a](cat.jpg)\n\n![mine](cat.jpg)\n", name: "cat.jpg", after: "b")
                == "![b](cat.jpg)\n\n![b](cat.jpg)\n\n![mine](cat.jpg)\n")
        #expect(Kept.described("cat.jpg", in: "![first](cat.jpg)\n\n![second](cat.jpg)") == "first")
    }

    @Test func onlyTheCardsThatChangedTouchTheText() {
        var cards = [shot("one.jpg", alt: "first"), shot("two.jpg", alt: "second")]
        let text = "![first](one.jpg)\n\n![second](two.jpg)\n"
        cards[1].alt = "the second"
        #expect(Kept.retitled(text, shots: cards, before: ["first", "second"]) == "![first](one.jpg)\n\n![the second](two.jpg)\n")
        // A shot added or taken away between the two: nothing to compare.
        #expect(Kept.retitled(text, shots: cards, before: ["first"]) == text)
        // A card of a picture the text does not name changes nothing in it.
        #expect(Kept.typed(text, name: "three.jpg", after: "x") == text)
    }

    /// A line break inside a mark is a picture the engine refuses.
    @Test func aDescriptionIsOneLineWhateverItsFieldHeld() {
        #expect(Kept.oneLine("  a cat\non  a\twall \n") == "a cat on a wall")
        #expect(shot("cat.jpg", alt: "a cat\non a wall").mark == "![a cat on a wall](cat.jpg)")
        #expect(Kept.typed("![](cat.jpg)", name: "cat.jpg", after: "a cat\non a wall") == "![a cat on a wall](cat.jpg)")
    }

    @Test func whatTheTextSaysOfAPictureIsRead() {
        let text = "![a cat on a wall](cat.jpg)\n\n!![the clip](clip.mp4)\n\n![](bare.jpg)\n"
        #expect(Kept.described("cat.jpg", in: text) == "a cat on a wall")
        #expect(Kept.described("clip.mp4", in: text) == "the clip")
        #expect(Kept.described("bare.jpg", in: text) == "")
        #expect(Kept.described("absent.jpg", in: text) == nil)
    }

    // MARK: a mark put where the caret is

    private let cat = "![a cat](cat.jpg)"

    /// The text never touched: the mark goes to its end, as before.
    @Test func withNoCaretTheMarkGoesToTheEnd() {
        #expect(Kept.placed(cat, in: "", at: nil).text == "![a cat](cat.jpg)\n")
        #expect(Kept.placed(cat, in: "Words.", at: nil).text == "Words.\n\n![a cat](cat.jpg)\n")
        #expect(Kept.placed(cat, in: "Words.\n", at: nil).text == "Words.\n\n![a cat](cat.jpg)\n")
        #expect(Kept.placed(cat, in: "Words.\n\n", at: nil).text == "Words.\n\n![a cat](cat.jpg)\n")
    }

    /// Between two paragraphs, with the caret on the blank line between
    /// them: a paragraph of its own, and no blank line doubled.
    @Test func betweenTwoParagraphsItIsAParagraphOfItsOwn() {
        let text = "One.\n\nTwo."
        #expect(Kept.placed(cat, in: text, at: 6).text == "One.\n\n![a cat](cat.jpg)\n\nTwo.")
        #expect(Kept.placed(cat, in: text, at: 5).text == "One.\n\n![a cat](cat.jpg)\n\nTwo.")
        #expect(Kept.placed(cat, in: text, at: 4).text == "One.\n\n![a cat](cat.jpg)\n\nTwo.")
    }

    /// In the middle of a line the line is broken there: the blog refuses
    /// a picture that shares a line with prose.
    @Test func inTheMiddleOfALineItBreaksTheLine() {
        #expect(Kept.placed(cat, in: "One two.", at: 4).text == "One \n\n![a cat](cat.jpg)\n\ntwo.")
    }

    @Test func atTheVeryStartNothingStandsBeforeIt() {
        #expect(Kept.placed(cat, in: "One.", at: 0).text == "![a cat](cat.jpg)\n\nOne.")
    }

    /// The caret comes back after the mark and its gap: where one goes on writing.
    @Test func theCaretGoesOnAfterTheMark() {
        let put = Kept.placed(cat, in: "One.\n\nTwo.", at: 6)
        #expect((put.text as NSString).substring(from: put.caret) == "Two.")
        let end = Kept.placed(cat, in: "One.", at: nil)
        #expect(end.caret == (end.text as NSString).length)
    }

    /// Positions are counted the way the text view counts: an emoji is two.
    @Test func positionsAreCountedAsTheTextViewCountsThem() {
        let text = "Běh 🏃 hotov.\n\nDál."
        let at = ("Běh 🏃 hotov.\n\n" as NSString).length
        let put = Kept.placed(cat, in: text, at: at)
        #expect(put.text == "Běh 🏃 hotov.\n\n![a cat](cat.jpg)\n\nDál.")
        // A caret past the end, or before the start, is the end and the start.
        #expect(Kept.placed(cat, in: "One.", at: 99).text == "One.\n\n![a cat](cat.jpg)\n")
        #expect(Kept.placed(cat, in: "One.", at: -3).text == "![a cat](cat.jpg)\n\nOne.")
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

    /// A shot picked and never put into the text would arrive, stand in no
    /// post and lie in the blog's incoming/ for good: it does not go.
    @Test func onlyTheShotsTheTextNamesAreSent() {
        let a = shot("photo-1.jpg"), b = shot("photo-2.jpg"), clip = shot("video-3.mp4", kind: .video)
        #expect(Kept.sent([a, b, clip], text: "![x](photo-2.jpg)\n\n!![y](video-3.mp4)").map(\.name) == ["photo-2.jpg", "video-3.mp4"])
        #expect(Kept.sent([a, b], text: "no marks").isEmpty)
        // The name has to be the whole of what the mark names.
        #expect(Kept.sent([a], text: "![x](other-photo-1.jpg)").isEmpty)
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

    /// A shot's own mark is found whatever its description holds: with a
    /// bracket in it, "Remove" left the mark in the text and the next
    /// picture took the removed one's words.
    @Test func aShotsMarkIsFoundWithBracketsInItsDescription() throws {
        var shot = Shot(name: "photo-1.jpg", data: Data(), width: 1, height: 1)
        shot.alt = "Pes [nas] v trave"
        let pattern = try NSRegularExpression(pattern: shot.markPattern)
        let text = "Before.\n\n\(shot.mark)\n\n![other](photo-2.jpg)\n"
        let found = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        #expect(found.count == 1)
        #expect(found.first.map { (text as NSString).substring(with: $0.range) } == shot.mark)
        // Two marks on one line stay two: the first does not run into the second.
        let line = "![a](photo-2.jpg) ![b](photo-1.jpg)"
        let one = pattern.matches(in: line, range: NSRange(line.startIndex..., in: line))
        #expect(one.first.map { (line as NSString).substring(with: $0.range) } == "![b](photo-1.jpg)")
    }

    /// A title that only begins and ends with a bracket or a quote of its
    /// own goes as it was typed; one wrapped whole is unwrapped, as before.
    @Test func aTitleWithBracketsOrQuotesOfItsOwnGoesAsTyped() {
        #expect(Markdown.frontMatter(title: "[foto] Sobota [Brno]", tags: "") == "---\ntitle: [foto] Sobota [Brno]\n---\n\n")
        #expect(Markdown.frontMatter(title: #""Ano" a "ne""#, tags: "") == "---\ntitle: \"Ano\" a \"ne\"\n---\n\n")
        #expect(Markdown.frontMatter(title: "[Sobota]", tags: "") == "---\ntitle: Sobota\n---\n\n")
        #expect(Markdown.frontMatter(title: "'Sobota'", tags: "") == "---\ntitle: Sobota\n---\n\n")
    }
}
