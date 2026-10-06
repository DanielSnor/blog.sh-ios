import Testing
import Foundation
@testable import blogsh

/// The language chosen in the settings. A mistake here is an app that
/// starts in a language nobody chose, or cannot be given back to the system.
@Suite(.serialized) struct AppLanguageTests {
    @Test func nothingKeptIsTheSystems() {
        #expect(AppLanguage(kept: nil) == .system)
        #expect(AppLanguage(kept: []) == .system)
    }

    @Test func theFirstOfTheListCounts() {
        #expect(AppLanguage(kept: ["de"]) == .de)
        #expect(AppLanguage(kept: ["cs", "en"]) == .cs)
        #expect(AppLanguage(kept: ["en", "de"]) == .en)
    }

    /// The system writes a language with its region.
    @Test func aRegionDoesNotMakeItAnotherLanguage() {
        #expect(AppLanguage(kept: ["cs-CZ"]) == .cs)
        #expect(AppLanguage(kept: ["de_AT"]) == .de)
        #expect(AppLanguage(kept: ["en-GB"]) == .en)
        #expect(AppLanguage(kept: ["EN"]) == .en)
    }

    @Test func aLanguageTheAppIsNotWrittenInIsTheSystems() {
        #expect(AppLanguage(kept: ["fr"]) == .system)
        #expect(AppLanguage(kept: ["system"]) == .system)
        #expect(AppLanguage(kept: [""]) == .system)
    }

    @Test func whatIsWrittenDownReadsBackAsItself() {
        for language in AppLanguage.allCases {
            #expect(AppLanguage(kept: language.kept) == language)
        }
        #expect(AppLanguage.system.kept == nil)
    }

    @Test func onlyTheSystemsHasNoNameOfItsOwn() {
        #expect(AppLanguage.system.name == nil)
        for language in AppLanguage.allCases where language != .system {
            #expect(language.name?.isEmpty == false)
        }
    }

    /// Kept among the app's own settings, and taken out again for the system's.
    @Test func itIsKeptAndGivenBack() throws {
        let domain = "app.blogsh.ios.tests.language"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }

        #expect(AppLanguage.read(from: defaults, domain: domain) == .system)
        AppLanguage.de.write(to: defaults)
        #expect(AppLanguage.read(from: defaults, domain: domain) == .de)
        AppLanguage.cs.write(to: defaults)
        #expect(AppLanguage.read(from: defaults, domain: domain) == .cs)
        AppLanguage.system.write(to: defaults)
        #expect(AppLanguage.read(from: defaults, domain: domain) == .system)
        #expect(defaults.persistentDomain(forName: domain)?[AppLanguage.key] == nil)
    }
}
