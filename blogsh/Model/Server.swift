import Foundation
import CryptoKit
import Security

/// Where the blog is: the machine, the account, the port. The path to the
/// engine is not here, on purpose -- the key's forced command on the
/// server fixes it (scripts/remote.sh), so the app cannot be pointed
/// anywhere else. Nothing secret lives in these three fields.
nonisolated struct ServerSettings: Equatable, Sendable {
    var host: String
    var port: Int
    var user: String

    static let hostKey = "server.host"
    static let portKey = "server.port"
    static let userKey = "server.user"

    static func load(from defaults: UserDefaults = .standard) -> ServerSettings? {
        let host = defaults.string(forKey: hostKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        let user = defaults.string(forKey: userKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !host.isEmpty, !user.isEmpty else { return nil }
        let port = defaults.integer(forKey: portKey)
        return ServerSettings(host: host, port: port == 0 ? 22 : port, user: user)
    }
}

/// The app's own SSH key: made on this device, kept in the keychain,
/// never leaving it. The public half is what goes into the server's
/// authorized_keys, in front of the forced command.
nonisolated enum KeyStore {
    static let service = "app.blogsh.ios"
    static let account = "ssh-ed25519"

    enum Failure: Error {
        case noKey
        case keychain(OSStatus)
    }

    static func privateKey() throws -> Curve25519.Signing.PrivateKey {
        guard let data = try read() else { throw Failure.noKey }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    static func hasKey() -> Bool {
        (try? read()) != nil
    }

    /// A new key, replacing the old one: the server has to be told again.
    @discardableResult
    static func makeKey() throws -> Curve25519.Signing.PrivateKey {
        let key = Curve25519.Signing.PrivateKey()
        try write(key.rawRepresentation)
        return key
    }

    static func deleteKey() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }

    /// The line for authorized_keys, as ssh-keygen would print it.
    static func publicKeyLine(comment: String = "blogsh-app") throws -> String {
        let key = try privateKey().publicKey
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

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read() throws -> Data? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        return item as? Data
    }

    private static func write(_ data: Data) throws {
        try deleteKey()
        var q = query()
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }
}
