import Foundation
import Testing
@testable import blogsh

/// What the engine answers, read: the shapes are its contract
/// (`--json`), and the app must take them as they come.
@Suite struct AnswersTests {
    private func version(claim: String, accent: Bool = true) -> Data {
        // Two pounds: a colour's own "#" would end a string fenced with one.
        let colours = accent ? ##","accent":{"light":"#1da1f2","dark":"#4ab3f4"}"## : ""
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
