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
                     "f": "abc-DEF_123AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.zzzZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ", "n": "M%C5%AFj%20blog"]
        change(&parts)
        return "blogsh://pair?" + ["v", "h", "p", "u", "k", "f", "n"].compactMap { name in parts[name].map { "\(name)=\($0)" } }.joined(separator: "&")
    }

    @Test func aCodeIsReadWhole() throws {
        let code = try PairingCode(link())
        #expect(code.host == "blog.example.org")
        #expect(code.port == 2222)
        #expect(code.user == "me")
        #expect(code.seed == Data(0..<32))
        #expect(code.fingerprints == ["abc-DEF_123AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "zzzZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"])
        #expect(code.site == "Můj blog")
    }

    /// Pasted with a line break after it, scanned in another case of its scheme.
    @Test func whatSurroundsTheLinkDoesNotMatter() throws {
        #expect(try PairingCode("  \n" + link() + "\n").host == "blog.example.org")
        #expect(try PairingCode(link().replacingOccurrences(of: "blogsh://pair", with: "BLOGSH://PAIR")).port == 2222)
    }

    /// As the engine writes the link: the parts are form-encoded, so a
    /// space in the blog's name arrives as a plus, and a plus as %2B.
    @Test func aPartOfTheLinkIsReadAsTheEngineWroteIt() throws {
        #expect(try PairingCode(link { $0["n"] = "M%C5%AFj+blog" }).site == "Můj blog")
        #expect(try PairingCode(link { $0["n"] = "C%2B%2B+a+j%C3%A1" }).site == "C++ a já")
        #expect(try PairingCode(link { $0["n"] = "M%C5%AFj%20blog" }).site == "Můj blog")
        // The key and the fingerprints are in an alphabet that has no plus:
        // they are read as they stand.
        #expect(try PairingCode(link { $0["n"] = "a+b" }).seed == Data(0..<32))
        #expect(try PairingCode(link { $0["n"] = "a+b" }).fingerprints == ["abc-DEF_123AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "zzzZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"])
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
        let code = try PairingCode(link { $0["f"] = "ab-_cdBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB.otherOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO" })
        #expect(code.expects("SHA256:ab+/cdBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"))
        #expect(code.expects("SHA256:otherOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO"))
        #expect(!code.expects("SHA256:somebody+else"))
    }

    /// A code cut off inside its fingerprint is not whole -- taken, it
    /// would turn its own server away as another machine.
    @Test func aCodeCutInsideItsFingerprintIsNotWhole() throws {
        let whole = link { $0["n"] = nil }
        #expect(throws: PairingCode.Problem.incomplete) { try PairingCode(String(whole.dropLast(20))) }
        #expect(throws: PairingCode.Problem.incomplete) { try PairingCode(link { $0["f"] = "short" }) }
        #expect(throws: PairingCode.Problem.incomplete) { try PairingCode(link { $0["f"] = String(repeating: "a", count: 42) + "!" }) }
        #expect(try PairingCode(whole).fingerprints.count == 2)
    }

    /// A line break or a space inside a pasted code was put there on the
    /// way, and is no part of it: the code reads as it was written.
    @Test func aLineBreakInsideAPastedCodeIsNoPartOfIt() throws {
        let good = try PairingCode(link())
        let text = link()
        for at in stride(from: 14, to: text.count, by: 9) {
            var broken = text
            broken.insert(contentsOf: "\n ", at: broken.index(broken.startIndex, offsetBy: at))
            #expect((try? PairingCode(broken)) == good, "a break at \(at)")
        }
        #expect((try? PairingCode("  \n" + text + "\n")) == good)
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

    /// A blog let in again by a new code is the same blog at the place
    /// the code names: its name on this device and its key's account --
    /// and so whatever is written and waits for it here -- stay.
    @Test func aBlogPairedAgainIsTheSameBlogElsewhere() throws {
        var blog = Blog()
        blog.host = "old.example"
        blog.port = 22
        blog.user = "dan"
        blog.name = "Sean.cz"
        blog.path = "/home/dan/blog"
        let id = blog.id, account = blog.keyAccount
        let code = try PairingCode(link { $0["h"] = "192.168.1.20"; $0["p"] = "2222"; $0["u"] = "daniel" })

        blog.moved(to: code, as: "SeanoPad")

        #expect(blog.id == id && blog.keyAccount == account)
        #expect(blog.host == "192.168.1.20" && blog.port == 2222 && blog.user == "daniel")
        #expect(blog.pairedAs == "SeanoPad")
        // What the blog called itself is kept; the code's word for it is a hint for a blog with none.
        #expect(blog.name == "Sean.cz")
        var unnamed = Blog()
        unnamed.moved(to: code, as: "")
        #expect(unnamed.name == code.site)
        #expect(unnamed.pairedAs == "")
    }

    /// The name the blog knows the device by is kept with the blog; a blog
    /// written down before the app kept it reads as one set up by hand.
    @Test func theDevicesNameIsKeptWithTheBlog() throws {
        var blog = Blog()
        blog.host = "one.example"
        blog.pairedAs = "SeanoPad"
        let read = try JSONDecoder().decode(Blog.self, from: JSONEncoder().encode(blog))
        #expect(read.pairedAs == "SeanoPad")
        let earlier = try JSONDecoder().decode(Blog.self, from: Data(#"{"host":"one.example","user":"dan","port":22}"#.utf8))
        #expect(earlier.pairedAs == nil)
    }

    /// The key is on a line of the server's that is not a device's: said
    /// as that, apart from every other no -- the code is still good, and
    /// a new key can go in with it.
    @Test func aKeyThatIsInUseIsSaidApartFromOtherRefusals() {
        let answer = Data(#"{"ok":false,"error":"key_in_use","message":"This key already stands in authorized_keys."}"#.utf8)
        #expect(throws: PairingError.keyInUse("This key already stands in authorized_keys.")) { try PairingError.device(from: answer) }
        #expect(throws: PairingError.spent) { try PairingError.device(from: Data(#"{"ok":false,"error":"used"}"#.utf8)) }
    }

    /// A key made aside takes an account's place only when it is told to:
    /// until then the account's own key is the one that was there.
    @Test func aSpareKeyTakesTheAccountsPlaceWhenMoved() throws {
        let account = "test-\(UUID().uuidString.lowercased())", spare = account + ".new"
        defer { try? KeyStore.deleteKey(account: account); try? KeyStore.deleteKey(account: spare) }
        try KeyStore.makeKey(account: account)
        let old = try KeyStore.publicKeyLine(account: account)
        try KeyStore.makeKey(account: spare)
        let new = try KeyStore.publicKeyLine(account: spare)
        #expect(old != new)
        #expect(try KeyStore.publicKeyLine(account: account) == old)

        try KeyStore.move(from: spare, to: account)

        #expect(try KeyStore.publicKeyLine(account: account) == new)
        #expect(!KeyStore.hasKey(account: spare))
        // Nothing aside to move: the account's key is left alone.
        #expect(throws: (any Error).self) { try KeyStore.move(from: spare, to: account) }
        #expect(try KeyStore.publicKeyLine(account: account) == new)
    }
}
