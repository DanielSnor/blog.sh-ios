import Foundation
import Testing
@testable import blogsh

/// The connection kept to the server. A mistake here is a server that
/// stops answering because it was asked through too many connections --
/// or a connection left open to a blog nobody is looking at.
@Suite struct LineTests {
    /// A server that counts: what was opened, what is open now.
    actor Server {
        var opened = 0
        var closed: [Int] = []
        var slow = false
        var refuses = false
        struct Refused: Error {}

        func open() async throws -> Int {
            if slow { try? await Task.sleep(for: .milliseconds(80)) }
            if refuses { throw Refused() }
            opened += 1
            return opened
        }
        func close(_ wire: Int) { closed.append(wire) }
        func be(slow: Bool = false, refusing: Bool = false) { self.slow = slow; refuses = refusing }
    }

    private let home = Door(host: "example.org", port: 22, user: "me", keyAccount: "a")
    private let other = Door(host: "example.org", port: 22, user: "me", keyAccount: "b")

    private func line(_ server: Server, keep: Double = 30, rest: Double = 20) -> Line<Int> {
        Line(keep: keep, rest: rest, open: { _ in try await server.open() }, close: { await server.close($0) })
    }

    private func until(_ what: () async -> Bool) async -> Bool {
        for _ in 0..<400 {
            if await what() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return await what()
    }

    @Test func oneConnectionServesTheCallsThatFollow() async throws {
        let server = Server(), line = line(server)
        for _ in 0..<12 {
            let hold = try await line.take(home)
            #expect(hold.wire == 1)
            await line.give(hold)
        }
        #expect(await server.opened == 1)
        #expect(await line.opened == 1)
        #expect(await server.closed.isEmpty)
    }

    /// A screen that asks three things at once, before anything is open:
    /// one connection, not three.
    @Test func callsThatComeTogetherShareTheOneBeingOpened() async throws {
        let server = Server(), line = line(server)
        await server.be(slow: true)
        async let a = line.take(home), b = line.take(home), c = line.take(home)
        let holds = try await [a, b, c]
        #expect(holds.map(\.wire) == [1, 1, 1])
        #expect(await server.opened == 1)
        for hold in holds { await line.give(hold) }
        #expect(await server.closed.isEmpty)
    }

    @Test func itIsClosedOnceNobodyHasUsedItForAWhile() async throws {
        let server = Server(), line = line(server, keep: 0.1)
        let hold = try await line.take(home)
        await line.give(hold)
        #expect(await until { await server.closed == [1] })
        // And the next call opens another.
        let next = try await line.take(home)
        #expect(next.wire == 2)
        await line.give(next)
    }

    /// The while is counted from the last call's end, and not at all
    /// under a call that is still running -- a build takes a minute.
    @Test func aCallInFlightKeepsItOpen() async throws {
        let server = Server(), line = line(server, keep: 0.1)
        let long = try await line.take(home)
        let short = try await line.take(home)
        await line.give(short)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(await server.closed.isEmpty)
        await line.give(long)
        #expect(await until { await server.closed == [1] })
    }

    @Test func anotherBlogIsAnotherConnectionAndTheFirstIsLetGo() async throws {
        let server = Server(), line = line(server)
        let first = try await line.take(home)
        await line.give(first)
        let second = try await line.take(other)
        #expect(second.wire == 2)
        #expect(await server.closed == [1])
        await line.give(second)
    }

    /// Let go of under a call: that call finishes on it, and only then
    /// is it closed.
    @Test func aConnectionLetGoOfUnderACallIsClosedWhenTheCallEnds() async throws {
        let server = Server(), line = line(server)
        let running = try await line.take(home)
        let second = try await line.take(other)
        #expect(await server.closed.isEmpty)
        await line.give(running)
        #expect(await server.closed == [1])
        await line.give(second)
        await line.drop()
        #expect(await server.closed == [1, 2])
    }

    @Test func droppedItIsClosedAndTheNextCallOpensAnother() async throws {
        let server = Server(), line = line(server)
        let hold = try await line.take(home)
        await line.give(hold)
        await line.drop()
        #expect(await server.closed == [1])
        await line.drop()
        #expect(await server.closed == [1])
        let next = try await line.take(home)
        #expect(next.wire == 2)
        await line.give(next)
    }

    /// One that failed under a call is not handed to the next.
    @Test func aBrokenOneIsNotKept() async throws {
        let server = Server(), line = line(server)
        let hold = try await line.take(home)
        await line.give(hold, broken: true)
        #expect(await server.closed == [1])
        let next = try await line.take(home)
        #expect(next.wire == 2)
        await line.give(next)
        #expect(await server.opened == 2)
    }

    @Test func aServerThatTurnsTheConnectionAwayIsAskedAgainNextTime() async throws {
        let server = Server(), line = line(server)
        await server.be(refusing: true)
        await #expect(throws: Server.Refused.self) { _ = try await line.take(home) }
        await server.be()
        let hold = try await line.take(home)
        #expect(hold.wire == 1)
        await line.give(hold)
    }

    /// Fresh from a call it is taken on trust; after lying unused, and
    /// with nobody else on it, it is one to be wary of.
    @Test func aConnectionThatHasRestedSaysSo() async throws {
        let server = Server(), line = line(server, rest: 0.1)
        let first = try await line.take(home)
        #expect(!first.rested)
        await line.give(first)
        let soon = try await line.take(home)
        #expect(!soon.rested)
        await line.give(soon)
        try? await Task.sleep(for: .milliseconds(250))
        let late = try await line.take(home)
        #expect(late.rested)
        // Somebody else is on it by now: not one to close under them.
        let beside = try await line.take(home)
        #expect(!beside.rested)
        await line.give(late)
        await line.give(beside)
    }
}
