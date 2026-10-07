import Foundation
import Testing
@testable import blogsh

/// The line in Settings that says which build this is. A mistake here is
/// a version nobody can name.
@Suite struct BuildStampTests {
    @Test func theTwoLinesAreTheCommitAndTheTime() {
        let stamp = BuildStamp(text: "e838f47\n2026-10-07T15:10:00Z\n")
        #expect(stamp.commit == "e838f47")
        #expect(stamp.built == Date(timeIntervalSince1970: 1_791_385_800))
    }

    /// Built from a tree with changes not committed: the commit says so.
    @Test func aTreeWithChangesIsMarked() {
        #expect(BuildStamp(text: "e838f47+\n2026-10-07T15:10:00Z").commit == "e838f47+")
    }

    @Test func whatIsNotAStampIsNone() {
        #expect(BuildStamp(text: "") == BuildStamp(commit: nil, built: nil))
        #expect(BuildStamp(text: "fatal: not a git repository\nyesterday").commit == nil)
        #expect(BuildStamp(text: "fatal: not a git repository\nyesterday").built == nil)
        // A build outside a repository: no commit, the time all the same.
        let bare = BuildStamp(text: "\n2026-10-07T15:10:00Z\n")
        #expect(bare.commit == nil)
        #expect(bare.built != nil)
    }
}
