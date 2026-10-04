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

    private var portText: Binding<String> {
        Binding(get: { String(port) }, set: { port = Int($0.filter(\.isNumber)) ?? port })
    }

    var body: some View {
        PaperScreen {
            ScreenHeader(title: String(localized: "Settings"))

            SectionLabel("Server")
            Plate {
                FieldRow(label: "Host", text: $host, mono: true)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                FieldRow(label: "User", text: $user, mono: true)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                FieldRow(label: "Port", text: portText, mono: true)
                    .keyboardType(.numberPad)
            }

            SectionLabel("Key")
            if let publicKey {
                Plate {
                    Text(verbatim: publicKey)
                        .font(.mono(12, bold: false))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                    FieldRow(label: "path", text: $installPath, prompt: String(localized: "Path to the blog on the server"), mono: true)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text(verbatim: authorizedKeysLine(publicKey))
                        .font(.mono(12, bold: false))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                    Command("Copy the authorized_keys line", symbol: "doc.on.doc") {
                        UIPasteboard.general.string = authorizedKeysLine(publicKey)
                    }
                    Command("Make a new key", symbol: "key", danger: true) { confirmingNewKey = true }
                        .confirmationDialog("Make a new key? The server will not know it until its line is put into authorized_keys again.",
                                            isPresented: $confirmingNewKey, titleVisibility: .visible) {
                            Button("Make a new key", role: .destructive) { makeKey() }
                        }
                }
            } else {
                Plate {
                    Command("Make the app's key", symbol: "key") { makeKey() }
                }
            }
            Hint("The key is made on this device and never leaves it. Put the line above into the server's ~/.ssh/authorized_keys; the forced command in front of it is what the key may run, and nothing else.")

            SectionLabel("Connection")
            Button {
                Task { await test() }
            } label: {
                PrimaryLabel(label: "Test the connection", busy: probe == .running)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(host.isEmpty || user.isEmpty || publicKey == nil || probe == .running)
            switch probe {
            case .idle, .running:
                EmptyView()
            case .answered(let answer):
                Plate {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "./blog.sh \(answer.engine)").font(.mono(13))
                        Text(verbatim: answer.site.claim.isEmpty ? answer.site.name : "\(answer.site.name) — \(answer.site.claim)")
                            .font(.ui(15))
                        Text(verbatim: answer.site.url).font(.mono(12, bold: false)).foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.ink)
                }
                .padding(.top, 12)
            case .failed(let reason):
                ProblemLine(text: reason)
            }
            if let known = TrustOnFirstUse.known(host: host, port: port) {
                Plate {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server key").engineLabel().foregroundStyle(Theme.muted)
                        Text(verbatim: known)
                            .font(.mono(12, bold: false))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                    }
                    Command("Forget the server's key", symbol: "xmark.circle", danger: true) {
                        TrustOnFirstUse.forget(host: host, port: port)
                    }
                }
                .padding(.top, 12)
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
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
