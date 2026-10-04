import Foundation
import CryptoKit
import Security

/// Where the open blog is: the machine, the account, the port, and which
/// key reaches it. The path to the engine is not what the app connects
/// by, on purpose -- the key's forced command on the server fixes it
/// (scripts/remote.sh), so the app cannot be pointed anywhere else.
nonisolated struct ServerSettings: Equatable, Sendable {
    var host: String
    var port: Int
    var user: String
    var keyAccount: String

    static func load(from defaults: UserDefaults = .standard) -> ServerSettings? {
        guard let blog = BlogShelf.current(from: defaults) else { return nil }
        let host = blog.host.trimmingCharacters(in: .whitespaces)
        let user = blog.user.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !user.isEmpty else { return nil }
        return ServerSettings(host: host, port: blog.port == 0 ? 22 : blog.port, user: user, keyAccount: blog.keyAccount)
    }
}

/// A blog's SSH key: made on this device, kept in the keychain, never
/// leaving it. The public half is what goes into the server's
/// authorized_keys, in front of the forced command. One to a blog, each
/// under its own account.
nonisolated enum KeyStore {
    static let service = "app.blogsh.ios"
    /// The account of the one key the app had before it had blogs.
    static let firstAccount = "ssh-ed25519"

    enum Failure: Error {
        case noKey
        case keychain(OSStatus)
    }

    static func privateKey(account: String) throws -> Curve25519.Signing.PrivateKey {
        guard let data = try read(account) else { throw Failure.noKey }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    static func hasKey(account: String) -> Bool {
        (try? read(account)) != nil
    }

    /// A new key, replacing the old one: the server has to be told again.
    @discardableResult
    static func makeKey(account: String) throws -> Curve25519.Signing.PrivateKey {
        let key = Curve25519.Signing.PrivateKey()
        try write(key.rawRepresentation, account)
        return key
    }

    static func deleteKey(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }

    /// The line for authorized_keys, as ssh-keygen would print it.
    static func publicKeyLine(account: String, comment: String = "blogsh-app") throws -> String {
        let key = try privateKey(account: account).publicKey
        var wire = Data()
        func sshString(_ bytes: Data) {
            var length = UInt32(bytes.count).bigEndian
            wire.append(Data(bytes: &length, count: 4))
            wire.append(bytes)
        }
        sshString(Data("ssh-ed25519".utf8))
        sshString(key.rawRepresentation)
        return "ssh-ed25519 \(wire.base64EncodedString()) \(comment)"
    }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read(_ account: String) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        return item as? Data
    }

    private static func write(_ data: Data, _ account: String) throws {
        try deleteKey(account: account)
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }
}
