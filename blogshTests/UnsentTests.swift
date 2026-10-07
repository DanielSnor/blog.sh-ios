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
}
