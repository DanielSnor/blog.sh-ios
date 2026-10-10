import Foundation
import Testing
@testable import blogsh

/// What the engine answers, read: the shapes are its contract
/// (`--json`), and the app must take them as they come.
@Suite struct AnswersTests {
    private func version(claim: String, accent: Bool = true, palette: Bool = false) -> Data {
        // Two pounds: a colour's own "#" would end a string fenced with one.
        var colours = accent ? ##","accent":{"light":"#1da1f2","dark":"#4ab3f4"}"## : ""
        if palette {
            colours += ##","palette":{"light":{"bg":"#fff7eb","text":"#1e1d1c","meta_text":"#6b6862","border":"#d7d0c6"},"dark":{"bg":"#000000","text":"#e6dccb","meta_text":"#a1988a","border":"#3c3935"}}"##
        }
        return Data(#"{"ok":true,"engine":"1.10.pre","max_mb":24,"site":{"name":"./blog.sh","claim":"\#(claim)","url":"https://blogsh.app","lang":"en","locales":["en","cs"]\#(colours)}}"#.utf8)
    }

    @Test func theIdentityIsRead() throws {
        let answer: VersionAnswer = try Engine.decode(version(claim: "just a blog"))
        #expect(answer.engine == "1.10.pre")
        #expect(answer.maxMb == 24)
        #expect(answer.site.name == "./blog.sh")
        #expect(answer.site.claim == "just a blog")
        #expect(answer.site.locales == ["en", "cs"])
        #expect(answer.site.accent?.light == "#1da1f2")
        #expect(answer.site.accent?.dark == "#4ab3f4")
    }

    /// A claim is markdown in the site's configuration; broken the markdown
    /// way, with a backslash at the end of a line, it is its two lines here.
    @Test func aClaimBrokenWithABackslashIsItsLines() throws {
        let answer: VersionAnswer = try Engine.decode(version(claim: #"just ./blog.sh\\\nno database"#))
        #expect(answer.site.claim == "just ./blog.sh\nno database")
    }

    @Test func aClaimBrokenWithTwoSpacesIsItsLines() throws {
        let answer: VersionAnswer = try Engine.decode(version(claim: #"one  \ntwo"#))
        #expect(answer.site.claim == "one\ntwo")
    }

    @Test func emptyLinesOfAClaimAreDropped() throws {
        let answer: VersionAnswer = try Engine.decode(version(claim: #"one\n\n  \ntwo\n"#))
        #expect(answer.site.claim == "one\ntwo")
    }

    /// An engine from before it said its accent: the app falls back to its own.
    @Test func anEngineWithoutAnAccentIsStillRead() throws {
        let answer: VersionAnswer = try Engine.decode(version(claim: "x", accent: false))
        #expect(answer.site.accent == nil)
    }

    /// The rest of the palette, as the engine names its colours.
    @Test func thePaletteIsRead() throws {
        let answer: VersionAnswer = try Engine.decode(version(claim: "x", palette: true))
        #expect(answer.site.palette?.light == Tones(bg: "#fff7eb", text: "#1e1d1c", metaText: "#6b6862", border: "#d7d0c6"))
        #expect(answer.site.palette?.dark == Tones(bg: "#000000", text: "#e6dccb", metaText: "#a1988a", border: "#3c3935"))
    }

    /// An engine from before it said its palette: the accent is still its own.
    @Test func anEngineWithoutAPaletteIsStillRead() throws {
        let answer: VersionAnswer = try Engine.decode(version(claim: "x"))
        #expect(answer.site.palette == nil)
        #expect(answer.site.accent?.light == "#1da1f2")
    }

    /// A post renamed in its properties, as the engine answers the rename:
    /// the screen it was opened from takes its new name from this, and
    /// asks for the text and the properties under it.
    @Test func aPostsRowIsReadFromItsProperties() throws {
        let props: PropsAnswer = try Engine.decode(Fixture.data("props-renamed"))
        let row = PostRow(props)
        #expect(row.slug == "novy-nazev")
        #expect(row.year == "2026")
        #expect(row.id == "2026/novy-nazev")
        #expect(row.title == "K přejmenování")
        #expect(row.state == .published)
        #expect(row.scheduled == false)
        #expect(row.date == "2026-05-01T10:00:00+02:00")
        #expect(row.day != nil)
        #expect(row.type == "text")
        #expect(row.tags == [])
        #expect(row.pinned == false)
        #expect(row.match == nil)
    }

    /// A post without a title is called by its slug in a list and by its
    /// opening words in its properties: the row keeps none, so the screen
    /// opened from the list does not rename the post a moment later.
    @Test func aRowWithoutATitleKeepsNone() throws {
        let props: PropsAnswer = try Engine.decode(Fixture.data("props-renamed"))
        let untitled = PostRow(slug: "stary", year: "2026", date: nil, title: nil, type: "text", tags: [],
                               state: .draft, scheduled: false, series: nil, pinned: false)
        let now = untitled.seen(as: props)
        #expect(now.title == nil)
        #expect(now.slug == "novy-nazev")
        #expect(now.state == .published)
        let titled = PostRow(slug: "stary", year: "2026", date: nil, title: "Starý", type: "text", tags: [],
                             state: .draft, scheduled: false, series: nil, pinned: false)
        #expect(titled.seen(as: props).title == "K přejmenování")
    }

    /// What is handed to somebody: the address the engine says, and the
    /// post's title to go with it.
    @Test func aPostsLinkIsItsAddressAndItsTitle() throws {
        let props: PropsAnswer = try Engine.decode(Fixture.data("props-renamed"))
        let link = try #require(PostLink(props))
        #expect(link.url.absoluteString == "https://example.com/posts/2026/novy-nazev/")
        #expect(link.title == "K přejmenování")
    }

    /// A site with no address set, or one that is not a web address: no link to give.
    @Test func withoutAWebAddressThereIsNoLink() {
        #expect(PostLink(address: "", title: "x") == nil)
        #expect(PostLink(address: "/posts/2026/x/", title: "x") == nil)
        #expect(PostLink(address: "file:///etc/passwd", title: "x") == nil)
        #expect(PostLink(address: "javascript:alert(1)", title: "x") == nil)
        #expect(PostLink(address: "http://localhost:8000/draft/abc/x/", title: "x")?.url.host() == "localhost")
        #expect(PostLink(address: "https://sean.cz/posts/2026/x/", title: "X")?.title == "X")
        // A blog at home, on a port of its own: the address goes on whole.
        let home = "http://10.0.0.5:8080/posts/2026/zkouska-portu/"
        #expect(PostLink(address: home, title: "x")?.url.absoluteString == home)
        #expect(PostLink(address: home, title: "x")?.url.port == 8080)
    }

    /// A row of the queue opens its post: the row it hands over is a
    /// draft with a plan, under the same slug and year.
    @Test func aQueuedPostIsARowOfItsOwn() throws {
        let json = #"{"position":2,"date":"2026-10-10T09:00:00+02:00","slug":"plan-d","year":"2026","title":"Plan D","overdue":false}"#
        let queued = try JSONDecoder().decode(QueueRow.self, from: Data(json.utf8))
        let row = PostRow(queued)
        #expect(row.id == queued.id)
        #expect(row.slug == "plan-d")
        #expect(row.title == "Plan D")
        #expect(row.state == .draft)
        #expect(row.scheduled)
        #expect(row.day != nil)
        // A post without a title is called by its slug, as everywhere.
        let bare = try JSONDecoder().decode(QueueRow.self, from: Data(json.replacingOccurrences(of: "Plan D", with: "").utf8))
        #expect(PostRow(bare).title == nil)
    }

    /// `stats --json` has no `ok` of its own and far more than the first
    /// screen says; what it says is read, the rest let be.
    @Test func theArchiveCountedIsRead() throws {
        let json = #"""
        {"posts":{"total":6653,"published":6649,"drafts":2,"scheduled":2,"pages":0},
         "span":{"first":"2003-10-31","last":"2026-10-08","days":8378,"busiest_year":{"year":"2024","posts":642}},
         "years":{"2003":23},"types":{"text":4815},
         "words":{"total":415207,"mean":62.4,"median":22,"longest":{"slug":"x","words":1925},"reading_hours":34.6},
         "tags":{"unique":864,"per_post":2.6,"top":[["twitter",2160]]},
         "media":{"files":5545,"bytes":2045037447,"referenced":5546,"posts_with_media":2562},
         "sources":{"twitter":2133}}
        """#
        let stats: StatsAnswer = try Engine.decode(Data(json.utf8))
        #expect(stats.posts.total == 6653)
        #expect(stats.span.first == "2003-10-31")
        #expect(stats.words.total == 415207)
        #expect(stats.words.readingHours == 34.6)
        #expect(stats.tags.unique == 864)
        #expect(stats.media.files == 5545)
        #expect(stats.media.bytes == 2_045_037_447)
    }

    @Test func anEmptyArchiveHasNoFirstDay() throws {
        let json = #"{"posts":{"total":0},"span":{"first":null},"words":{"total":0,"reading_hours":0.0},"tags":{"unique":0},"media":{"files":0,"bytes":0}}"#
        let stats: StatsAnswer = try Engine.decode(Data(json.utf8))
        #expect(stats.span.first == nil)
        #expect(stats.posts.total == 0)
    }

    /// `empty trash --json` without `--yes`: how much there is.
    @Test func whatTheTrashHoldsIsRead() throws {
        let json = #"{"ok":true,"what":"trash","count":10,"bytes":1231404,"size":"1.2MB","emptied":false}"#
        let held: HeldAnswer = try Engine.decode(Data(json.utf8))
        #expect(held.count == 10)
        #expect(held.bytes == 1_231_404)
    }

    /// A refusal is an answer too: it is thrown as what the engine said,
    /// not as an answer that failed to parse.
    @Test func aRefusalIsThrownAsTheEnginesOwnWords() {
        let json = #"{"ok":false,"error":"unknown_command","message":"Only run, receive and deliver are allowed on this key."}"#
        do {
            let _: VersionAnswer = try Engine.decode(Data(json.utf8))
            Issue.record("a refusal was read as an answer")
        } catch EngineError.refused(let refusal) {
            #expect(refusal.error == "unknown_command")
            #expect(refusal.message.hasPrefix("Only run"))
        } catch {
            Issue.record("thrown as \(error)")
        }
    }

    // MARK: the server's paths

    /// What the engine says after a restore names a file on the server;
    /// the name is what a phone can use.
    @Test func aFileOnTheServerIsCalledByItsName() {
        #expect(ServerPaths.plain("Obnoveno: /app/data/sean.cz/content.nosync/posts/2026/venku.json") == "Obnoveno: venku")
        #expect(ServerPaths.plain("Smazáno (v koši): /srv/blog/trash/2026/smazat") == "Smazáno (v koši): smazat")
        #expect(ServerPaths.plain("Kept /srv/blog/media.nosync/2026/venku/01.jpg, dropped the rest.") == "Kept 01.jpg, dropped the rest.")
        #expect(ServerPaths.plain("Moved to /srv/blog/trash/2026/smazat.") == "Moved to smazat.")
    }

    /// An address, a preview path, a command: none of them is a file of the engine's.
    @Test func whatIsNotTheEnginesFileIsLeftAsItIs() {
        for line in ["Publikováno: https://sean.cz/posts/2026/venku/",
                     "Náhled: /draft/9d7e7bbcce6f229e/venku/",
                     "obnovíš přes ./blog.sh restore venku",
                     "Fronta posunuta: každý následující příspěvek převzal dřívější slot.",
                     "see https://example.com/trash/2026/x for more", ""] {
            #expect(ServerPaths.plain(line) == line)
        }
        #expect(["a /srv/b/trash/x", "plain"].plain == ["a x", "plain"])
    }

    /// `empty trash --yes --json`: how much went.
    @Test func whatWasClearedOutIsRead() throws {
        let json = #"{"ok":true,"what":"trash","count":2,"bytes":536,"size":"536 B","emptied":true}"#
        let held: HeldAnswer = try Engine.decode(Data(json.utf8))
        #expect(held.count == 2 && held.bytes == 536 && held.emptied == true)
    }

    /// The engine's sentence about a slug two posts share speaks of --yes
    /// and of a screen the terminal has; the app says what a phone can do.
    @Test func aSlugTwoPostsShareIsSaidInTheAppsWords() throws {
        let refusal = Refusal(ok: false, error: "ambiguous_slug", message: "Slug x je ve víc než jednom roce a --yes se nemá koho zeptat.")
        let said = try #require(EngineError.refused(refusal).errorDescription)
        #expect(!said.contains("--yes"))
        #expect(said.contains("./blog.sh props"))
        let other = Refusal(ok: false, error: "not_found", message: "Příspěvek nenalezen.")
        #expect(EngineError.refused(other).errorDescription == "Příspěvek nenalezen.")
    }

    @Test func noAnswerAtAllIsSaidSo() {
        do {
            let _: VersionAnswer = try Engine.decode(Data())
            Issue.record("nothing was read as an answer")
        } catch EngineError.unreadable {
            // as it should be
        } catch {
            Issue.record("thrown as \(error)")
        }
    }

    @Test func whatIsNotJsonIsShownNotSwallowed() {
        do {
            let _: VersionAnswer = try Engine.decode(Data("ruby: command not found".utf8))
            Issue.record("a shell's complaint was read as an answer")
        } catch EngineError.unreadable(let text) {
            #expect(text.contains("command not found"))
        } catch {
            Issue.record("thrown as \(error)")
        }
    }

    /// The server turning the key away is said in words a person can act
    /// on, not in the SSH library's own.
    @Test func aKeyTheServerDoesNotKnowIsSaidInWords() throws {
        let said = try #require(EngineError.keyNotKnown.errorDescription)
        #expect(!said.isEmpty)
        #expect(!said.contains("allAuthenticationOptionsFailed"))
        #expect(said.contains("authorized_keys"))
    }
}

/// What `check` and `doctor` answer, read as they are sent. A mistake
/// here is a problem the blog reported and the app passed over.
@Suite struct DiagnosisTests {
    private func read(_ name: String) throws -> DiagnosisAnswer {
        try Engine.decode(try Fixture.data(name))
    }

    /// As blogsh.app answered `check` on 8. 10. 2026.
    @Test func aFindingAboutAPostNamesThePost() throws {
        let answer = try read("check-warning")
        #expect(answer.errors == 0)
        #expect(answer.warnings == 1)
        let finding = try #require(answer.findings.first)
        #expect(finding.level == .warning)
        #expect(finding.kind == "post_entities")
        #expect(finding.slug == "everything-else-in-1-6")
        #expect(finding.text.hasPrefix("everything-else-in-1-6:"))
        #expect(finding.fix?.isEmpty == false)
    }

    /// As sean.cz answered: one finding, and it is the all-clear.
    @Test func anArchiveInOrderSaysSoInOneFinding() throws {
        let answer = try read("check-clear")
        #expect(answer.errors == 0 && answer.warnings == 0)
        #expect(answer.findings.map(\.level) == [.fine])
        #expect(answer.findings.first?.kind == "all_clear")
        #expect(answer.findings.first?.slug == nil)
        #expect(answer.findings.first?.fix == nil)
    }

    /// As the engine's `doctor --json` answers: a kind on every finding,
    /// a fix that is null where there is no advice, nothing about a post.
    @Test func theInstallationsFindingsAreReadWithTheirKinds() throws {
        let answer = try read("doctor")
        #expect(answer.errors == 0)
        #expect(answer.warnings == answer.findings.filter { $0.level == .warning }.count)
        #expect(answer.findings.allSatisfy { !$0.kind.isEmpty })
        #expect(answer.findings.allSatisfy { $0.slug == nil })
        #expect(answer.findings.contains { $0.level == .fine && $0.fix == nil })
        #expect(answer.findings.contains { $0.kind == "scheduler" })
    }

    @Test func theProblemsComeFirstThenWhatWantsALookThenWhatIsFine() throws {
        let mixed = Data(#"""
        {"errors": 1, "warnings": 2, "findings": [
          {"level": "ok", "kind": "a", "text": "fine one", "fix": null},
          {"level": "warn", "kind": "b", "text": "first warning"},
          {"level": "error", "kind": "c", "text": "the error", "fix": "do this"},
          {"level": "warn", "kind": "d", "text": "second warning", "data": {"slugs": ["x", "y"]}},
          {"level": "notice", "text": "a level nobody knows"}
        ]}
        """#.utf8)
        let answer: DiagnosisAnswer = try Engine.decode(mixed)
        #expect(answer.ordered.map(\.text) == ["the error", "first warning", "second warning", "a level nobody knows", "fine one"])
        // A level the app has not heard of is not passed over as fine.
        #expect(answer.findings.last?.level == .warning)
        #expect(answer.findings.last?.kind == "")
        // What a finding is about differs with its kind: no post, no failure.
        #expect(answer.findings[3].slug == nil)
    }

    /// The blog said no -- an engine without the check: that is a
    /// refusal, not a diagnosis with nothing in it.
    @Test func aRefusalIsNotADiagnosis() {
        let refusal = Data(#"{"ok":false,"error":"unknown_command","message":"\"doctor\" is not a command a program may run."}"#.utf8)
        #expect(throws: EngineError.self) { let _: DiagnosisAnswer = try Engine.decode(refusal) }
    }

    /// The queue says whether anything sends it out by itself; an older
    /// engine does not say, and nothing is concluded from its silence.
    @Test func theQueueSaysWhetherAnythingSendsItOut() throws {
        func queue(_ scheduler: String) throws -> QueueAnswer {
            try JSONDecoder().decode(QueueAnswer.self, from: Data(#"{"ok":true,"queue":[]\#(scheduler)}"#.utf8))
        }
        #expect(try queue(#","scheduler":{"last_run":null}"#).unattended)
        #expect(try !queue(#","scheduler":{"last_run":"2026-10-09T12:40:00+02:00"}"#).unattended)
        #expect(try queue(#","scheduler":{"last_run":"2026-10-09T12:40:00+02:00"}"#).scheduler?.lastRun == "2026-10-09T12:40:00+02:00")
        // Before the engine said either way.
        #expect(try !queue("").unattended)
        #expect(try queue("").scheduler == nil)
        // The answer to a move carries it too, beside what it always had.
        let moved = try JSONDecoder().decode(QueueAnswer.self, from: Data(#"{"ok":true,"queue":[],"scheduler":{"last_run":null},"warnings":[]}"#.utf8))
        #expect(moved.unattended)
    }

    /// check and doctor are asked in the app's language; nothing else is,
    /// and what is not a language's code is not sent as one.
    @Test func theTwoThatAnswerInSentencesAreAskedInTheAppsLanguage() {
        #expect(Engine.request(["check"], lang: "cs")["lang"] as? String == "cs")
        #expect(Engine.request(["doctor", "--json"], lang: "de")["lang"] as? String == "de")
        #expect(Engine.request(["check"], lang: "cs")["args"] as? [String] == ["check"])
        #expect(Engine.request(["queue"], lang: "cs")["lang"] == nil)
        #expect(Engine.request(["publish", "venku", "--yes"], lang: "cs")["lang"] == nil)
        #expect(Engine.request(["check"], lang: nil)["lang"] == nil)
        #expect(Engine.request(["check"], lang: "cs-CZ")["lang"] == nil)
        #expect(Engine.request(["check"], lang: "Base")["lang"] == nil)
        #expect(Engine.request([], lang: "cs")["lang"] == nil)
    }

    /// The commands after which the first screen reads its cards again:
    /// the ones that change the drafts, the queue, the trash or the versions.
    @Test func theCommandsThatChangeWhatTheFirstScreenSays() {
        for args in [["publish", "venku", "--yes"], ["unpublish", "venku", "--yes"], ["delete", "venku", "--yes"],
                     ["restore", "venku"], ["schedule", "venku", "--at", "2026-10-10T08:00:00+02:00"], ["schedule", "venku", "--cancel"],
                     ["queue", "--up", "2026/venku"], ["queue", "--move", "2026/venku", "--to", "1"],
                     ["props", "venku", "--set", "pinned=yes"], ["props", "venku", "--rename", "outside", "--yes"],
                     ["props", "venku", "--restore-version", "v1", "--yes"], ["empty", "trash", "--yes"]] {
            #expect(Engine.changesTheBlog(args), "\(args)")
        }
        for args in [["queue"], ["list", "--drafts"], ["version"], ["stats"], ["props", "venku"], ["props", "venku", "--versions"],
                     ["empty", "trash"], ["empty", "versions"], ["edit", "venku"], ["check"], ["doctor"], ["rebuild"], []] {
            #expect(!Engine.changesTheBlog(args), "\(args)")
        }
    }

    /// The findings about former addresses, as the engine builds them
    /// since e8b3225 (lib/checker.rb): lists in `data`, and two kinds
    /// this app has no word of its own for. Each is a row with its
    /// sentence, its repair and the way to its post -- nothing in `data`
    /// that the app does not ask for stands in the way.
    @Test func findingsAboutFormerAddressesAreRowsLikeAnyOther() throws {
        let json = #"""
        {"errors": 0, "warnings": 3, "findings": [
          {"level": "warn", "kind": "former_slug_taken",
           "data": {"slug": "venku", "entry": "outside", "holder": "obsazeno", "taken_in": ["/"], "served_in": ["/en/"], "lang": "en"},
           "text": "venku: the former address is taken in one tree.", "fix": "Give it up there."},
          {"level": "warn", "kind": "former_slug_two_languages",
           "data": {"slug": "venku", "entry": "outside", "langs": ["en", "de"], "year": "2026"},
           "text": "venku: the same former address in two languages.", "fix": "Keep it in one."},
          {"level": "warn", "kind": "former_slug_unpublished",
           "data": {"slug": "doma", "entry": "at-home", "lang": "de", "year": "2025"},
           "text": "doma: a former address in a language the site does not publish.", "fix": "Drop it."}
        ]}
        """#
        let answer = try JSONDecoder().decode(DiagnosisAnswer.self, from: Data(json.utf8))
        #expect(answer.findings.count == 3)
        #expect(answer.findings.map(\.kind) == ["former_slug_taken", "former_slug_two_languages", "former_slug_unpublished"])
        #expect(answer.findings.map(\.slug) == ["venku", "venku", "doma"])
        #expect(answer.findings.allSatisfy { $0.level == .warning && !$0.text.isEmpty && $0.fix != nil })
    }
}
