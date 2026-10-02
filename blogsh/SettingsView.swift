import SwiftUI

/// The one thing the terminal never asks for: where the blog is, and the
/// key the app holds. Three fields, a key made on this device, and the
/// line for the server's authorized_keys -- with the forced command in
/// front of it, which is what keeps this key from ever getting a shell.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ServerSettings.hostKey) private var host = ""
    @AppStorage(ServerSettings.portKey) private var port = 22
    @AppStorage(ServerSettings.userKey) private var user = ""
    @State private var publicKey: String? = try? KeyStore.publicKeyLine()
    @State private var installPath = "/path/to/blog"
    @State private var probe: Probe = .idle
    @State private var confirmingNewKey = false

    enum Probe: Equatable {
        case idle, running
        case answered(VersionAnswer)
        case failed(String)
    }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Host", text: $host)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("User", text: $user)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Port", value: $port, format: .number)
                    .keyboardType(.numberPad)
            }

            Section {
                if let publicKey {
                    Text(publicKey)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    TextField("Path to the blog on the server", text: $installPath)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.body.monospaced())
                    Text(authorizedKeysLine(publicKey))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button("Copy the authorized_keys line") {
                        UIPasteboard.general.string = authorizedKeysLine(publicKey)
                    }
                    Button("Make a new key", role: .destructive) { confirmingNewKey = true }
                } else {
                    Button("Make the app's key") { makeKey() }
                }
            } header: {
                Text("Key")
            } footer: {
                Text("The key is made on this device and never leaves it. Put the line above into the server's ~/.ssh/authorized_keys; the forced command in front of it is what the key may run, and nothing else.")
            }

            Section("Connection") {
                Button("Test the connection") { Task { await test() } }
                    .disabled(host.isEmpty || user.isEmpty || publicKey == nil || probe == .running)
                switch probe {
                case .idle:
                    EmptyView()
                case .running:
                    ProgressView()
                case .answered(let answer):
                    VStack(alignment: .leading, spacing: 2) {
                        Text("./blog.sh \(answer.engine)")
                        Text("\(answer.site.name) — \(answer.site.claim)")
                        Text(answer.site.url).foregroundStyle(.secondary)
                    }
                    .font(.callout.monospaced())
                case .failed(let reason):
                    Text(reason).foregroundStyle(.red)
                }
                if let known = TrustOnFirstUse.known(host: host, port: port) {
                    LabeledContent("Server key", value: known)
                        .font(.caption.monospaced())
                    Button("Forget the server's key", role: .destructive) {
                        TrustOnFirstUse.forget(host: host, port: port)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog("Make a new key? The server will not know it until its line is put into authorized_keys again.",
                            isPresented: $confirmingNewKey, titleVisibility: .visible) {
            Button("Make a new key", role: .destructive) { makeKey() }
        }
    }

    /// The forced command runs through the account's shell, so a path with
    /// a space in it (an iCloud folder on a Mac) is single-quoted inside the
    /// double quotes sshd takes; a plain path stays plain.
    private func authorizedKeysLine(_ publicKey: String) -> String {
        let path = "\(installPath)/scripts/remote.sh"
        let safe = path.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "/._-+@:".unicodeScalars.contains($0) }
        let quoted = safe ? path : "'" + path.replacingOccurrences(of: "'", with: "'\''") + "'"
        return "restrict,command=\"\(quoted)\" \(publicKey)"
    }

    private func makeKey() {
        do {
            try KeyStore.makeKey()
            publicKey = try KeyStore.publicKeyLine()
            probe = .idle
        } catch {
            probe = .failed(error.localizedDescription)
        }
    }

    private func test() async {
        probe = .running
        do {
            let answer: VersionAnswer = try await Engine.shared.call(["version"])
            probe = .answered(answer)
        } catch {
            probe = .failed(error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
