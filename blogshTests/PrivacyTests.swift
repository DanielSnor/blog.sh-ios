import Foundation
import Testing
@testable import blogsh

/// What the app says of itself to the store: that it tracks nobody and
/// collects nothing, and why it touches the two things a reason is
/// asked for -- its own settings, and the times of its own files.
@Suite struct PrivacyTests {
    private func manifest() throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let read = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(read as? [String: Any])
    }

    @Test func theAppTracksNobodyAndCollectsNothing() throws {
        let manifest = try manifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    }

    /// The two kinds of access the code makes are both said, each with
    /// its reason: settings of the app's own, files of the app's own.
    @Test func whatIsTouchedIsSaidWithItsReason() throws {
        let said = try #require(try manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasons = Dictionary(uniqueKeysWithValues: said.compactMap { one -> (String, [String])? in
            guard let kind = one["NSPrivacyAccessedAPIType"] as? String,
                  let why = one["NSPrivacyAccessedAPITypeReasons"] as? [String] else { return nil }
            return (kind, why)
        })
        #expect(reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"])
        #expect(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"] == ["C617.1"])
        #expect(reasons.count == 2)
    }
}
