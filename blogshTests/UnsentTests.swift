import Foundation
import Testing
@testable import blogsh

/// The post being written, kept on the device until it is sent. A mistake
/// here is an evening's writing gone with a closed app -- or an old post
/// coming back into a form that was already sent.
@Suite struct UnsentTests {
    private func defaults() -> UserDefaults {
        let name = "unsent-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private let written = Unsent(title: "Pes v trávě", tags: "pes, zahrada", text: "Plazí se.\n\n![Pes](photo-1.jpg)\n",
                                 at: Date(timeIntervalSince1970: 1_791_400_000))

    @Test func whatIsWrittenIsKeptAndReadBack() {
        let defaults = defaults(), blog = UUID()
        written.keep(for: blog, in: defaults)
        #expect(Unsent.kept(for: blog, in: defaults) == written)
    }

    /// A post belongs to the blog it was written for.
    @Test func eachBlogKeepsItsOwn() {
        let defaults = defaults(), one = UUID(), other = UUID()
        written.keep(for: one, in: defaults)
        #expect(Unsent.kept(for: other, in: defaults) == nil)
        var second = written
        second.title = "Jiný blog"
        second.keep(for: other, in: defaults)
        #expect(Unsent.kept(for: one, in: defaults)?.title == "Pes v trávě")
        #expect(Unsent.kept(for: other, in: defaults)?.title == "Jiný blog")
    }

    /// Sent, or cleared by hand: nothing is left to bring back.
    @Test func anEmptiedFormKeepsNothing() {
        let defaults = defaults(), blog = UUID()
        written.keep(for: blog, in: defaults)
        Unsent().keep(for: blog, in: defaults)
        #expect(Unsent.kept(for: blog, in: defaults) == nil)
        #expect(defaults.data(forKey: Unsent.key(blog)) == nil)
        Unsent(title: "  ", tags: "", text: "\n\n").keep(for: blog, in: defaults)
        #expect(defaults.data(forKey: Unsent.key(blog)) == nil)
    }

    @Test func oneFieldIsEnoughToBeKept() {
        let defaults = defaults(), blog = UUID()
        Unsent(title: "", tags: "", text: "Jen věta.").keep(for: blog, in: defaults)
        #expect(Unsent.kept(for: blog, in: defaults)?.text == "Jen věta.")
        Unsent(title: "Jen titulek", tags: "", text: "").keep(for: blog, in: defaults)
        #expect(Unsent.kept(for: blog, in: defaults)?.title == "Jen titulek")
    }

    @Test func whatDoesNotReadIsNothing() {
        let defaults = defaults(), blog = UUID()
        defaults.set(Data("not json".utf8), forKey: Unsent.key(blog))
        #expect(Unsent.kept(for: blog, in: defaults) == nil)
        defaults.set("a string", forKey: Unsent.key(blog))
        #expect(Unsent.kept(for: blog, in: defaults) == nil)
    }

    @Test func forgottenItIsGone() {
        let defaults = defaults(), blog = UUID()
        written.keep(for: blog, in: defaults)
        Unsent.forget(for: blog, in: defaults)
        #expect(Unsent.kept(for: blog, in: defaults) == nil)
    }

    /// The pictures are not kept; the form says so where the text names one.
    @Test func itKnowsWhetherItsTextNamesPictures() {
        #expect(written.namesPictures)
        #expect(Unsent(text: "Před.\n\n!![Klip](clip-1.mp4)\n").namesPictures)
        #expect(!Unsent(text: "Jen text s [odkazem](https://example.org).").namesPictures)
        #expect(!Unsent(text: "Vykřičník! [a závorka]").namesPictures)
        #expect(!Unsent().namesPictures)
    }

    /// A form that was only opened was not written in: what is kept
    /// keeps the time it was written.
    @Test func keepingTheSameWordsAgainKeepsTheirTime() {
        let defaults = defaults(), blog = UUID()
        written.keep(for: blog, in: defaults)
        var again = written
        again.at = Date(timeIntervalSince1970: 1_791_500_000)
        again.keep(for: blog, in: defaults)
        #expect(Unsent.kept(for: blog, in: defaults)?.at == written.at)
        again.text += " A dál."
        again.keep(for: blog, in: defaults)
        #expect(Unsent.kept(for: blog, in: defaults)?.at == again.at)
    }
}

/// Changes to a post the blog has, kept until they are saved. A mistake
/// here is an edit lost with a closed app -- or one post's changes coming
/// back into another, or into another language of the same.
@Suite struct UnsavedTests {
    private func defaults() -> UserDefaults {
        let name = "unsaved-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private let changed = Unsaved(text: "---\ntitle: Venku\n---\n\nNový odstavec.\n", base: "abc123",
                                  at: Date(timeIntervalSince1970: 1_791_400_000))

    @Test func changesAreKeptForTheirPostAndReadBack() {
        let defaults = defaults(), blog = UUID()
        changed.keep(for: blog, slug: "venku", what: .text, in: defaults)
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .text, in: defaults) == changed)
    }

    /// Each to its own: another post, another language of the same post,
    /// another blog with a post of the same name.
    @Test func nothingComesBackIntoAnotherPlace() {
        let defaults = defaults(), blog = UUID()
        changed.keep(for: blog, slug: "venku", what: .text, in: defaults)
        #expect(Unsaved.kept(for: blog, slug: "doma", what: .text, in: defaults) == nil)
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .language("en"), in: defaults) == nil)
        #expect(Unsaved.kept(for: UUID(), slug: "venku", what: .text, in: defaults) == nil)
        var english = changed
        english.text = "A new paragraph."
        english.keep(for: blog, slug: "venku", what: .language("en"), in: defaults)
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .language("de"), in: defaults) == nil)
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .language("en"), in: defaults)?.text == "A new paragraph.")
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .text, in: defaults) == changed)
    }

    @Test func forgottenTheyAreGoneAndOnlyThey() {
        let defaults = defaults(), blog = UUID()
        changed.keep(for: blog, slug: "venku", what: .text, in: defaults)
        changed.keep(for: blog, slug: "venku", what: .language("en"), in: defaults)
        Unsaved.forget(for: blog, slug: "venku", what: .text, in: defaults)
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .text, in: defaults) == nil)
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .language("en"), in: defaults) != nil)
    }

    /// A blog that leaves the app takes all of its own with it, and no
    /// other blog's.
    @Test func aBlogThatLeavesTakesItsOwn() {
        let defaults = defaults(), leaving = UUID(), staying = UUID()
        changed.keep(for: leaving, slug: "venku", what: .text, in: defaults)
        changed.keep(for: leaving, slug: "doma", what: .language("en"), in: defaults)
        changed.keep(for: staying, slug: "venku", what: .text, in: defaults)
        Unsaved.forgetAll(for: leaving, in: defaults)
        #expect(Unsaved.kept(for: leaving, slug: "venku", what: .text, in: defaults) == nil)
        #expect(Unsaved.kept(for: leaving, slug: "doma", what: .language("en"), in: defaults) == nil)
        #expect(Unsaved.kept(for: staying, slug: "venku", what: .text, in: defaults) == changed)
    }

    @Test func keepingTheSameWordsAgainKeepsTheirTime() {
        let defaults = defaults(), blog = UUID()
        changed.keep(for: blog, slug: "venku", what: .text, in: defaults)
        var again = changed
        again.at = Date(timeIntervalSince1970: 1_791_500_000)
        again.base = "def456"
        again.keep(for: blog, slug: "venku", what: .text, in: defaults)
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .text, in: defaults) == changed)
        again.text += "Ještě věta.\n"
        again.keep(for: blog, slug: "venku", what: .text, in: defaults)
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .text, in: defaults) == again)
    }

    @Test func whatDoesNotReadIsNothing() {
        let defaults = defaults(), blog = UUID()
        defaults.set(Data("not json".utf8), forKey: Unsaved.key(blog, slug: "venku", what: .text))
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .text, in: defaults) == nil)
    }

    /// The pictures the post has are there to be named; one chosen on the
    /// device for these changes was not kept with them.
    @Test func itKnowsWhenItsTextNamesAPictureThePostDoesNotHave() {
        var kept = changed
        kept.text = "Text.\n\n![Les](photo-1.jpg)\n\n!![Klip](clip-1.mp4)\n"
        #expect(!kept.namesPictures(beyond: ["photo-1.jpg", "clip-1.mp4"]))
        #expect(kept.namesPictures(beyond: ["photo-1.jpg"]))
        #expect(kept.namesPictures(beyond: []))
        #expect(!changed.namesPictures(beyond: []))
    }
}

/// What the first screen lists as begun and not finished. A mistake here
/// is writing that waits in a form nobody knows to open -- or another
/// blog's writing offered under this one.
@Suite struct BegunTests {
    private func defaults() -> UserDefaults {
        let name = "begun-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_791_400_000 + seconds) }

    @Test func withNothingKeptNothingIsBegun() {
        #expect(Begun.all(for: UUID(), in: defaults()).isEmpty)
    }

    /// The new post first, however long ago it was written; then the
    /// changes to posts, the last written first.
    @Test func theNewPostComesFirstThenTheChangesTheLastWrittenFirst() {
        let defaults = defaults(), blog = UUID()
        Unsent(title: "Pes v trávě", tags: "", text: "Plazí se.", at: at(100)).keep(for: blog, in: defaults)
        Unsaved(text: "change", base: "b", at: at(200), title: "Doma").keep(for: blog, slug: "doma", what: .language("en"), in: defaults)
        Unsaved(text: "změna", base: "b", at: at(300), title: "Venku").keep(for: blog, slug: "venku", what: .text, in: defaults)
        let all = Begun.all(for: blog, in: defaults)
        #expect(all.map(\.what) == [.new, .text(slug: "venku"), .language(slug: "doma", lang: "en")])
        #expect(all.map(\.title) == ["Pes v trávě", "Venku", "Doma"])
        #expect(all.map(\.at) == [at(100), at(300), at(200)])
    }

    @Test func anotherBlogsWritingIsNotThisOnes() {
        let defaults = defaults(), mine = UUID(), other = UUID()
        Unsent(title: "Cizí", tags: "", text: "", at: at(0)).keep(for: other, in: defaults)
        Unsaved(text: "x", base: "b", at: at(0), title: "Cizí").keep(for: other, slug: "venku", what: .text, in: defaults)
        #expect(Begun.all(for: mine, in: defaults).isEmpty)
        #expect(Begun.all(for: other, in: defaults).count == 2)
    }

    /// Sent, saved or put away: gone from the list with it.
    @Test func whatIsFinishedIsNoLongerListed() {
        let defaults = defaults(), blog = UUID()
        Unsent(title: "Pes", tags: "", text: "", at: at(0)).keep(for: blog, in: defaults)
        Unsaved(text: "x", base: "b", at: at(1), title: "Venku").keep(for: blog, slug: "venku", what: .text, in: defaults)
        Unsent().keep(for: blog, in: defaults)
        #expect(Begun.all(for: blog, in: defaults).map(\.what) == [.text(slug: "venku")])
        Unsaved.forget(for: blog, slug: "venku", what: .text, in: defaults)
        #expect(Begun.all(for: blog, in: defaults).isEmpty)
    }

    /// A slug is whatever the blog made it; one with a dot in it is still one slug.
    @Test func aPostIsFoundByItsWholeSlug() {
        let defaults = defaults(), blog = UUID()
        Unsaved(text: "x", base: "b", at: at(0), title: nil).keep(for: blog, slug: "verze-1.10", what: .language("de"), in: defaults)
        let all = Begun.all(for: blog, in: defaults)
        #expect(all.map(\.what) == [.language(slug: "verze-1.10", lang: "de")])
        // Kept without a title -- by an earlier build of the app: its slug stands in.
        #expect(all.first?.title == "verze-1.10")
    }

    @Test func aPostWithoutATitleIsCalledByItsFirstWords() {
        #expect(Unsent(title: "  Pes  ", text: "Text.").headline == "Pes")
        #expect(Unsent(text: "\n\n## Nadpis uvnitř\n\nA dál.").headline == "Nadpis uvnitř")
        #expect(Unsent(text: "![Les](photo-1.jpg)\n\nPrvní věta.").headline == "První věta.")
        #expect(Unsent(text: String(repeating: "slovo ", count: 30)).headline.count == 60)
        #expect(Unsent(tags: "jen, štítky").headline == "")
    }

    /// Changes kept by a build that did not keep the title yet still read.
    @Test func changesKeptWithoutATitleStillRead() throws {
        let defaults = defaults(), blog = UUID()
        let old = Data(#"{"text":"x","base":"b","at":0}"#.utf8)
        defaults.set(old, forKey: Unsaved.key(blog, slug: "venku", what: .text))
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .text, in: defaults)?.title == nil)
        #expect(Begun.all(for: blog, in: defaults).first?.title == "venku")
    }
}

/// What an audit of the keeping found: writing that could be lost, or
/// said to be unsent when it was sent.
@MainActor @Suite struct KeepingTests {
    private func defaults() -> UserDefaults {
        let name = "keeping-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func moment(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_791_400_000 + seconds) }

    /// Changes brought back stay changes over the version they were begun
    /// over, whatever is typed after: that is what the screen compares
    /// with the blog's version to say the post has moved on.
    @Test func changesBroughtBackKeepTheBaseTheyWereBegunOver() {
        let begun = Unsaved(text: "old A", base: "K0", at: moment(0), title: "Venku")
        let typed = Unsaved.now("old AB", title: "Venku", over: "K1", begun: begun, at: moment(60))
        #expect(typed.base == "K0")
        #expect(typed.text == "old AB")
        // Nothing brought back: the changes begin over what the blog has now.
        #expect(Unsaved.now("new B", title: "Venku", over: "K1", begun: nil, at: moment(60)).base == "K1")
    }

    /// A save forgets what it saved, and nothing written after it.
    @Test func aSaveForgetsOnlyWhatItSaved() {
        let defaults = defaults(), blog = UUID()
        Unsaved(text: "saved", base: "K0", at: moment(0), title: nil).keep(for: blog, slug: "venku", what: .text, in: defaults)
        Unsaved.forget(for: blog, slug: "venku", what: .text, saved: "something else", in: defaults)
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .text, in: defaults)?.text == "saved")
        Unsaved.forget(for: blog, slug: "venku", what: .text, saved: "saved", in: defaults)
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .text, in: defaults) == nil)
    }

    /// A post that arrived is forgotten whether or not a form saw it go;
    /// what was written since is another post's, and stays.
    @Test func aSentPostIsForgottenUnlessMoreWasWritten() {
        let defaults = defaults(), blog = UUID()
        let sent = Unsent(title: "Hello", tags: "a", text: "Text", at: moment(0))
        sent.keep(for: blog, in: defaults)
        Unsent.forget(for: blog, sent: Unsent(title: "Hello", tags: "a", text: "Text"), in: defaults)
        #expect(Unsent.kept(for: blog, in: defaults) == nil)

        Unsent(title: "Hello", tags: "a", text: "Text and more", at: moment(5)).keep(for: blog, in: defaults)
        Unsent.forget(for: blog, sent: sent, in: defaults)
        #expect(Unsent.kept(for: blog, in: defaults)?.text == "Text and more")
    }

    /// A renamed post takes what was kept for it along: its text and
    /// every language, and nothing of another post or another blog.
    @Test func whatIsKeptFollowsARenamedPost() {
        let defaults = defaults(), blog = UUID(), other = UUID()
        Unsaved(text: "text", base: "K0", at: moment(0), title: "Venku").keep(for: blog, slug: "venku", what: .text, in: defaults)
        Unsaved(text: "words", base: "K0", at: moment(1), title: "Venku").keep(for: blog, slug: "venku", what: .language("en"), in: defaults)
        Unsaved(text: "beside", base: "B0", at: moment(2), title: nil).keep(for: blog, slug: "venku-2", what: .text, in: defaults)
        Unsaved(text: "elsewhere", base: "E0", at: moment(3), title: nil).keep(for: other, slug: "venku", what: .text, in: defaults)

        Unsaved.move(for: blog, from: "venku", to: "outside", in: defaults)

        #expect(Unsaved.kept(for: blog, slug: "outside", what: .text, in: defaults)?.text == "text")
        #expect(Unsaved.kept(for: blog, slug: "outside", what: .language("en"), in: defaults)?.text == "words")
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .text, in: defaults) == nil)
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .language("en"), in: defaults) == nil)
        #expect(Unsaved.kept(for: blog, slug: "venku-2", what: .text, in: defaults)?.text == "beside")
        #expect(Unsaved.kept(for: other, slug: "venku", what: .text, in: defaults)?.text == "elsewhere")
        // The first screen lists them under the name that opens.
        #expect(Set(Begun.all(for: blog, in: defaults).map(\.what)) == [.text(slug: "outside"), .language(slug: "outside", lang: "en"), .text(slug: "venku-2")])
    }

    /// Where the new name has later writing of its own, that stays.
    @Test func aRenameDoesNotPutOlderWritingOverNewer() {
        let defaults = defaults(), blog = UUID()
        Unsaved(text: "older", base: "K0", at: moment(0), title: nil).keep(for: blog, slug: "venku", what: .text, in: defaults)
        Unsaved(text: "newer", base: "K1", at: moment(60), title: nil).keep(for: blog, slug: "outside", what: .text, in: defaults)
        Unsaved.move(for: blog, from: "venku", to: "outside", in: defaults)
        #expect(Unsaved.kept(for: blog, slug: "outside", what: .text, in: defaults)?.text == "newer")
        #expect(Unsaved.kept(for: blog, slug: "venku", what: .text, in: defaults) == nil)
    }

    /// Words with no title and no body take the language off the post,
    /// whichever key sent them: the screen says so, not "Saved".
    @Test func emptiedWordsTakeTheLanguageOff() {
        #expect(TranslateView.takesOff(""))
        #expect(TranslateView.takesOff("---\ntitle:\n---\n\n"))
        #expect(TranslateView.takesOff("---\ntitle: \nslug: outside\n---\n\n  \n"))
        #expect(!TranslateView.takesOff("---\ntitle: Outside\n---\n\n"))
        #expect(!TranslateView.takesOff("---\ntitle:\n---\n\nWords.\n"))
        #expect(!TranslateView.takesOff("Words."))
    }

    /// A form is left alone while its blog's new post is on its way, and
    /// told when the post has arrived.
    @Test func theDeskKnowsWhichBlogsPostIsOnItsWay() {
        let desk = Desk(), blog = UUID(), other = UUID()
        desk.began(blog)
        #expect(desk.sending.contains(blog))
        #expect(!desk.sending.contains(other))
        desk.ended(blog, arrived: false)
        #expect(desk.sending.isEmpty)
        #expect(desk.arrived == 0)
        desk.began(blog)
        desk.ended(blog, arrived: true)
        #expect(desk.arrived == 1)
        #expect(desk.arrivedAt == blog)
    }
}
