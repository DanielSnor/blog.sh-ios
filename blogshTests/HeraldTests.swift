import Foundation
import Testing
@testable import blogsh

/// The site built by the app itself. A mistake here is a site left
/// behind what was changed, a build after every keypress, or a failure
/// nobody is told of.
@MainActor @Suite struct HeraldTests {
    /// Counts the builds, and can be told how the next one ends.
    @MainActor final class Site {
        var builds = 0
        var fails: [Error] = []
        var slow = false
        var open: UUID? = UUID()
        func build() async throws {
            builds += 1
            if slow { try? await Task.sleep(for: .milliseconds(120)) }
            if !fails.isEmpty { throw fails.removeFirst() }
        }
    }

    private func herald(_ site: Site) -> Herald {
        Herald(pause: 0.05, retry: 0.05, open: { site.open }, rebuild: { try await site.build() })
    }

    private func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    /// Waits for something to come true, however busy the tests beside
    /// this one keep the main actor; false when it never did.
    private func until(_ what: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if what() { return true }
            await wait(0.025)
        }
        return what()
    }

    @Test func aChangeIsBuiltOnceAfterAMoment() async {
        let site = Site(), herald = herald(site)
        herald.owe()
        #expect(herald.build == .owed)
        #expect(site.builds == 0)
        #expect(await until { herald.build == .none })
        #expect(site.builds == 1)
    }

    /// Several changes in a row -- a queue being put in order -- are one build.
    @Test func changesInARowAreOneBuild() async {
        let site = Site(), herald = herald(site)
        for _ in 0..<5 { herald.owe() }
        #expect(site.builds == 0)
        #expect(await until { herald.build == .none })
        await wait(0.2)
        #expect(site.builds == 1)
    }

    /// A change made while a build runs may have missed it: built once more.
    @Test func aChangeDuringABuildIsBuiltAgain() async {
        let site = Site(), herald = herald(site)
        site.slow = true
        herald.owe()
        #expect(await until { herald.isBuilding })
        herald.owe()
        #expect(herald.isBuilding)
        #expect(await until { herald.build == .none })
        #expect(site.builds == 2)
    }

    /// A publish builds the whole site: what was owed is paid without a build.
    @Test func whatSomethingElseBuiltIsNotBuiltAgain() async {
        let site = Site(), herald = herald(site)
        herald.owe()
        herald.settled()
        #expect(herald.build == .none)
        await wait(0.3)
        #expect(site.builds == 0)
    }

    /// The engine busy with something else: the same wish a little later, not a failure.
    @Test func aBusyEngineIsAskedAgain() async {
        let site = Site(), herald = herald(site)
        site.fails = [EngineError.refused(Refusal(ok: false, error: "busy", message: "busy"))]
        herald.owe()
        #expect(await until { site.builds == 2 && herald.build == .none })
        #expect(site.builds == 2)
    }

    @Test func aBuildThatFailsSaysSoAndIsPutAwayWhenRead() async {
        let site = Site(), herald = herald(site)
        site.fails = [EngineError.refused(Refusal(ok: false, error: "rebuild_failed", message: "no disk"))]
        herald.owe()
        #expect(await until { if case .failed = herald.build { true } else { false } })
        guard case .failed(let why) = herald.build else { return }
        #expect(why.contains("no disk"))
        #expect(site.builds == 1)
        herald.acknowledge()
        #expect(herald.build == .none)
    }

    /// Another blog opened before the build ran: its engine is not asked
    /// to build for a change it never had.
    @Test func anotherBlogsEngineIsNotAsked() async {
        let site = Site(), herald = herald(site)
        herald.owe()
        site.open = UUID()
        #expect(await until { herald.build == .none })
        #expect(site.builds == 0)
    }

    /// A build owed to a blog is not forgotten because another blog was
    /// opened before it ran: it waits, and runs once its blog is open again.
    @Test func aBuildOwedToABlogWaitsForItWhileAnotherIsOpen() async {
        let site = Site(), herald = herald(site)
        let a = site.open, b = UUID()
        herald.owe("a post deleted")
        // Blog B is opened before the pause is over, as the first screen says it.
        site.open = b
        herald.opened(b)
        #expect(herald.build == .none)
        await wait(0.3)
        #expect(site.builds == 0)
        // Back at A: owed again, in the words it was owed in, and built.
        site.open = a
        herald.opened(a)
        #expect(herald.build == .owed)
        #expect(herald.owedFor == "a post deleted")
        #expect(await until { site.builds == 1 && herald.build == .none })
    }

    /// The same, where nobody said the blog was changed before the pause
    /// ran out: the build that finds another blog open keeps the debt.
    @Test func aBuildThatFindsAnotherBlogOpenKeepsItsDebt() async {
        let site = Site(), herald = herald(site)
        let a = site.open
        herald.owe()
        site.open = UUID()
        #expect(await until { herald.build == .none })
        #expect(site.builds == 0)
        site.open = a
        herald.opened(a)
        #expect(await until { site.builds == 1 && herald.build == .none })
    }

    /// The other blog's own debt is its own: each is built once, for itself.
    @Test func twoBlogsDebtsAreKeptApart() async {
        let site = Site(), herald = herald(site)
        let a = site.open, b = UUID()
        herald.owe("of a")
        site.open = b
        herald.opened(b)
        herald.owe("of b")
        #expect(await until { site.builds == 1 && herald.build == .none })
        site.open = a
        herald.opened(a)
        #expect(herald.owedFor == "of a")
        #expect(await until { site.builds == 2 && herald.build == .none })
        // Nothing is left over for either.
        site.open = b
        herald.opened(b)
        #expect(herald.build == .none)
    }

    /// The herald's own build failed; then something else built the whole
    /// site. "The site could not be built" has nothing left to say.
    @Test func aFailedBuildIsPutAwayOnceSomethingElseBuiltTheSite() async {
        let site = Site(), herald = herald(site)
        site.fails = [EngineError.refused(Refusal(ok: false, error: "rebuild_failed", message: "no disk"))]
        herald.owe()
        #expect(await until { if case .failed = herald.build { true } else { false } })
        herald.settled()
        #expect(herald.build == .none)
    }

    /// The time a schedule sends is written in the year that was picked:
    /// the engine files and addresses the post by the year as written.
    @Test func aScheduledTimeIsWrittenInTheYearThatWasPicked() throws {
        let prague = try #require(TimeZone(identifier: "Europe/Prague"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = prague
        let picked = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 0, minute: 15)))
        #expect(Markdown.stamp(picked, zone: prague) == "2027-01-01T00:15:00+01:00")
        // West of Greenwich the last hours of a year are already the next in UTC.
        let lima = try #require(TimeZone(identifier: "America/Lima"))
        calendar.timeZone = lima
        let late = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23, minute: 45)))
        #expect(Markdown.stamp(late, zone: lima) == "2026-12-31T23:45:00-05:00")
    }

    /// An action's answer came after another blog was opened: the build
    /// it owes is the blog's it was made on. The open blog is not built
    /// for it, and the debt waits for its own.
    @Test func aDebtWhoseAnswerCameLateIsItsOwnBlogs() async {
        let site = Site(), herald = herald(site)
        let a = site.open, b = UUID()
        // The delete was sent on A; B was opened before it answered.
        site.open = b
        herald.opened(b)
        herald.owe("a post deleted", for: a)
        #expect(herald.build == .none)
        await wait(0.3)
        #expect(site.builds == 0)
        site.open = a
        herald.opened(a)
        #expect(herald.owedFor == "a post deleted")
        #expect(await until { site.builds == 1 && herald.build == .none })
    }

    /// A publish on another blog built that blog's site: what the open
    /// blog is owed is still owed, and what waited for the other is paid.
    @Test func anotherBlogsBuildPaysNothingOfTheOpenOnes() async {
        let site = Site(), herald = herald(site)
        let a = site.open, b = UUID()
        herald.owe("of a", for: a)
        herald.settled(for: b)
        #expect(herald.build == .owed)
        #expect(await until { site.builds == 1 && herald.build == .none })
        // A debt parked for B is paid by B's own build, said while A is open.
        herald.owe("of b", for: b)
        herald.settled(for: b)
        site.open = b
        herald.opened(b)
        #expect(herald.build == .none)
        await wait(0.2)
        #expect(site.builds == 1)
    }

    @Test func whatIsOwedIsSaidInTheWordsGiven() {
        let herald = herald(Site())
        herald.owe("the queue")
        #expect(herald.owedFor == "the queue")
        herald.owe()
        #expect(!herald.owedFor.isEmpty && herald.owedFor != "the queue")
    }

    @Test func whatWasDoneIsSaid() {
        let herald = herald(Site())
        herald.say("")
        #expect(herald.note == nil)
        herald.say("Published")
        #expect(herald.note == "Published")
    }
}
