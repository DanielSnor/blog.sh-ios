import Testing
@testable import blogsh

/// The line for `authorized_keys`. A mistake here is a server that does
/// not let the app in -- or lets the key run more than it should.
@Suite struct KeyLineTests {
    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample blogsh-app"

    @Test func noLineUntilTheDirectoryIsKnown() {
        #expect(KeyLine.compose(publicKey: key, path: "", through: "") == nil)
        #expect(KeyLine.compose(publicKey: key, path: "   ", through: "sudo docker exec -i blog") == nil)
    }

    @Test func aPlainPathStaysPlain() {
        #expect(KeyLine.compose(publicKey: key, path: "/home/dan/blog", through: "")
                == #"restrict,command="/home/dan/blog/scripts/remote.sh" \#(key)"#)
    }

    @Test func aTrailingSlashOrTheScriptsOwnNameIsTheSameDirectory() {
        let plain = KeyLine.compose(publicKey: key, path: "/home/dan/blog", through: "")
        #expect(KeyLine.compose(publicKey: key, path: "/home/dan/blog/", through: "") == plain)
        #expect(KeyLine.compose(publicKey: key, path: "/home/dan/blog///", through: "") == plain)
        #expect(KeyLine.compose(publicKey: key, path: "/home/dan/blog/scripts/remote.sh", through: "") == plain)
        #expect(KeyLine.compose(publicKey: key, path: "  /home/dan/blog  ", through: "") == plain)
    }

    /// The forced command runs through the account's shell: a path with a
    /// space in it is one word only inside quotes.
    @Test func aPathWithASpaceIsQuoted() {
        #expect(KeyLine.compose(publicKey: key, path: "/Users/dan/My Blog", through: "")
                == #"restrict,command="'/Users/dan/My Blog/scripts/remote.sh'" \#(key)"#)
    }

    @Test func anApostropheInThePathIsClosedAndReopened() {
        #expect(KeyLine.compose(publicKey: key, path: "/Users/dan/Dan's Blog", through: "")
                == #"restrict,command="'/Users/dan/Dan'\''s Blog/scripts/remote.sh'" \#(key)"#)
    }

    /// Through the command that enters a container, the word SSH was asked
    /// for is handed to the script as its argument -- the shape the
    /// engine's docs/operations.md gives.
    @Test func throughAContainerTheWordIsHandedOver() {
        #expect(KeyLine.compose(publicKey: key, path: "/app/blog", through: "sudo docker exec -i blog")
                == #"restrict,command="sudo docker exec -i blog /app/blog/scripts/remote.sh \"$SSH_ORIGINAL_COMMAND\"" \#(key)"#)
    }

    /// What the blog is reached through may carry quotes of its own; inside
    /// the line's double quotes each has to be escaped, or sshd ends the
    /// command there.
    @Test func doubleQuotesInTheWrapperAreEscaped() {
        let line = KeyLine.compose(publicKey: key, path: "/app/blog",
                                   through: #"sudo docker exec -i $(sudo docker ps --filter "name=^blog$" -q)"#)
        #expect(line == #"restrict,command="sudo docker exec -i $(sudo docker ps --filter \"name=^blog$\" -q) /app/blog/scripts/remote.sh \"$SSH_ORIGINAL_COMMAND\"" \#(key)"#)
    }

    @Test func theLineAlwaysRestrictsTheKeyAndEndsWithIt() throws {
        let line = try #require(KeyLine.compose(publicKey: key, path: "/srv/blog", through: "env PATH=/opt/ruby/bin:/usr/bin"))
        #expect(line.hasPrefix(#"restrict,command=""#))
        #expect(line.hasSuffix(" " + key))
    }
}
