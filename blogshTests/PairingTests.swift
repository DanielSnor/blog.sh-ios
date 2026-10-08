import Foundation
import Testing
@testable import blogsh

/// The code `./blog.sh pair` shows, read by the app. A mistake here is a
/// key handed to the wrong machine, or a good code turned away.
@Suite struct PairingTests {
    /// 32 bytes, 0…31, in the alphabet a link can carry and without padding.
    private let key = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
    private func link(_ change: (inout [String: String]) -> Void = { _ in }) -> String {
        var parts = ["v": "1", "h": "blog.example.org", "p": "2222", "u": "me", "k": key,
                     "f": "abc-DEF_123.zzz", "n": "M%C5%AFj%20blog"]
        change(&parts)
        return "blogsh://pair?" + ["v", "h", "p", "u", "k", "f", "n"].compactMap { name in parts[name].map { "\(name)=\($0)" } }.joined(separator: "&")
    }

    @Test func aCodeIsReadWhole() throws {
        let code = try PairingCode(link())
        #expect(code.host == "blog.example.org")
        #expect(code.port == 2222)
        #expect(code.user == "me")
        #expect(code.seed == Data(0..<32))
        #expect(code.fingerprints == ["abc-DEF_123", "zzz"])
        #expect(code.site == "Můj blog")
    }

    /// Pasted with a line break after it, scanned in another case of its scheme.
    @Test func whatSurroundsTheLinkDoesNotMatter() throws {
        #expect(try PairingCode("  \n" + link() + "\n").host == "blog.example.org")
        #expect(try PairingCode(link().replacingOccurrences(of: "blogsh://pair", with: "BLOGSH://PAIR")).port == 2222)
    }

    @Test func theFingerprintsAndTheNameMayBeMissing() throws {
        let code = try PairingCode(link { $0["f"] = nil; $0["n"] = nil })
        #expect(code.fingerprints.isEmpty)
        #expect(code.site == nil)
        #expect(try PairingCode(link { $0["n"] = "%20" }).site == nil)
    }

    @Test func anAddressOfAnyKindIsAnAddress() throws {
        #expect(try PairingCode(link { $0["h"] = "192.168.1.20" }).host == "192.168.1.20")
        #expect(try PairingCode(link { $0["h"] = "fe80%3A%3A1" }).host == "fe80::1")
    }

    @Test func whatIsNotACodeIsNotOne() {
        for text in ["", "ahoj", "https://example.org/pair?v=1", "blogsh://open?v=1&h=x", "blogsh:pair"] {
            #expect(throws: PairingCode.Problem.notACode) { _ = try PairingCode(text) }
        }
    }

    /// A kind of code the app has not heard of is said to be that -- not
    /// read as if it were the kind it knows.
    @Test func aCodeOfAnotherVersionIsSaidToBeOne() {
        #expect(throws: PairingCode.Problem.anotherVersion) { _ = try PairingCode(link { $0["v"] = "2" }) }
        #expect(throws: PairingCode.Problem.incomplete) { _ = try PairingCode(link { $0["v"] = nil }) }
    }

    @Test func aCodeWithAPartMissingIsIncomplete() {
        for part in ["h", "p", "u", "k"] {
            #expect(throws: PairingCode.Problem.incomplete) { _ = try PairingCode(link { $0[part] = nil }) }
        }
        #expect(throws: PairingCode.Problem.incomplete) { _ = try PairingCode(link { $0["p"] = "0" }) }
        #expect(throws: PairingCode.Problem.incomplete) { _ = try PairingCode(link { $0["p"] = "70000" }) }
        #expect(throws: PairingCode.Problem.incomplete) { _ = try PairingCode(link { $0["p"] = "ssh" }) }
        // A key of another length is no key of this kind.
        #expect(throws: PairingCode.Problem.incomplete) { _ = try PairingCode(link { $0["k"] = "AAECAwQ" }) }
        #expect(throws: PairingCode.Problem.incomplete) { _ = try PairingCode(link { $0["k"] = "!!!" }) }
    }

    /// As ssh prints a fingerprint, and as the code spells the same one.
    @Test func aFingerprintIsComparedInTheCodesSpelling() throws {
        #expect(PairingCode.urlSafe("SHA256:ab+/cd==") == "ab-_cd")
        #expect(PairingCode.urlSafe("ab-_cd") == "ab-_cd")
        let code = try PairingCode(link { $0["f"] = "ab-_cd.other" })
        #expect(code.expects("SHA256:ab+/cd"))
        #expect(code.expects("SHA256:other"))
        #expect(!code.expects("SHA256:somebody+else"))
    }

    /// A code that names no server takes the first one on trust, as a
    /// blog set up by hand does.
    @Test func aCodeWithoutFingerprintsExpectsAnyServer() throws {
        #expect(try PairingCode(link { $0["f"] = nil }).expects("SHA256:whatever"))
    }

    /// The fingerprint of a key is the one ssh-keygen prints for it.
    @Test func theFingerprintOfAKeyIsSshsOwn() {
        // ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJZ2lFQ0Nlp7tkPAqXT0k5i1a1xPB2SQXQv7fmM2U1bV
        let blob = Data(base64Encoded: "AAAAC3NzaC1lZDI1NTE5AAAAIJZ2lFQ0Nlp7tkPAqXT0k5i1a1xPB2SQXQv7fmM2U1bV")!
        let print = PairingCode.fingerprint(ofKey: blob)
        #expect(print.hasPrefix("SHA256:"))
        #expect(print.count == 7 + 43)
        #expect(!print.contains("="))
    }

    // MARK: - The engine's answer

    @Test func theEnginesYesNamesTheDevice() throws {
        #expect(try PairingError.device(from: Data(#"{"ok": true, "device": "Opravdový telefon"}"#.utf8)) == "Opravdový telefon")
    }

    /// Too old, used already, or a code the blog never heard of: all the
    /// same to somebody holding a phone -- ask for a new one.
    @Test func aSpentCodeIsSaidToBeSpent() {
        for word in ["expired", "used", "unknown_code"] {
            let answer = Data(#"{"ok": false, "error": "\#(word)", "message": "…"}"#.utf8)
            #expect(throws: PairingError.spent) { _ = try PairingError.device(from: answer) }
        }
    }

    @Test func anotherNoCarriesTheEnginesSentence() {
        let answer = Data(#"{"ok": false, "error": "bad_key", "message": "That is not one ed25519 public key."}"#.utf8)
        #expect(throws: PairingError.refused("That is not one ed25519 public key.")) { _ = try PairingError.device(from: answer) }
        #expect(throws: PairingError.refused("bash: no such file")) { _ = try PairingError.device(from: Data("bash: no such file\n".utf8)) }
    }
}
