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
