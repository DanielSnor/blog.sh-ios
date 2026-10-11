import Foundation

/// `pair --list` and `pair --revoke`, asked through the door: the devices
/// a code let in to the blog, in the order the terminal numbers them, and
/// which of them is asking. Who asks, the blog reads from the line that
/// let the connection in -- nothing the app says is listened to -- so a
/// device sees the others and takes off itself, and no other.
nonisolated struct PairedDevices: Decodable, Equatable, Sendable {
    struct Device: Decodable, Equatable, Sendable {
        let name: String
        /// As `ssh-keygen -l` writes it. Empty for a line whose key
        /// somebody damaged by hand.
        let fingerprint: String
        /// The blog says this is the device asking.
        let own: Bool

        enum CodingKeys: String, CodingKey { case name, fingerprint, own = "self" }

        init(name: String, fingerprint: String, own: Bool = false) {
            self.name = name
            self.fingerprint = fingerprint
            self.own = own
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            name = try box.decodeIfPresent(String.self, forKey: .name) ?? ""
            fingerprint = try box.decodeIfPresent(String.self, forKey: .fingerprint) ?? ""
            own = try box.decodeIfPresent(Bool.self, forKey: .own) ?? false
        }
    }

    let ok: Bool
    let devices: [Device]
    /// The key of the device asking. Nil where the blog cannot tell: the
    /// line that let it in was written by hand, or by a pairing from
    /// before a line said whose it is.
    let own: String?
    /// After `--revoke`: the device that was taken off.
    let revoked: Device?

    enum CodingKeys: String, CodingKey { case ok, devices, own = "self", revoked }

    /// The blog knows who is asking, and so can take that device off.
    var mayLeave: Bool { own != nil }

    /// The row is this device: the blog says so -- or, where it cannot
    /// tell who asks, the row carries the key the app holds.
    func isThis(_ device: Device, key: String?) -> Bool {
        device.own || (!device.fingerprint.isEmpty && device.fingerprint == key)
    }

    /// This device is among them, by either sign.
    func holdsThis(key: String?) -> Bool {
        devices.contains { isThis($0, key: key) }
    }

    /// The blog is an older one, which lets no `pair` through its door.
    static func notKnownThere(_ error: Error) -> Bool {
        if case EngineError.refused(let refusal) = error { return refusal.error == "unknown_command" }
        return false
    }

    /// What went wrong after asking to be taken off is the taking off
    /// itself: the answer was lost on its way, the app asked again, and
    /// the server no longer knew the key.
    static func isGone(after error: Error) -> Bool {
        if case EngineError.keyNotKnown = error { return true }
        return false
    }

    /// What to say of a no. The key file held by another run is said in
    /// the blog's own words: the app's sentence for a held blog speaks of
    /// a build and a save, and this is neither.
    static func words(for error: Error) -> String {
        if case EngineError.refused(let refusal) = error, refusal.error == "busy",
           let message = refusal.message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        return error.localizedDescription
    }
}
