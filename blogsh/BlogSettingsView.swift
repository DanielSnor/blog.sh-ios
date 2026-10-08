import SwiftUI

/// The one thing the terminal never asks for: where the blog is, and the
/// key the app holds. Three fields, a key made on this device, and the
/// line for the server's authorized_keys -- with the forced command in
/// front of it, which is what keeps this key from ever getting a shell.
/// It is the open blog's, and it is reached from that blog's row in the
/// list of blogs; what is the app's own is under the gear.
struct BlogSettingsView: View {
    /// Closes the list this was opened from, and so the way back to the app.
    let close: () -> Void
    @Environment(\.dismiss) private var dismiss
    private var blogs = Blogs.shared
    @State private var publicKey: String?
    @State private var confirmingRemoval = false
    @State private var probe: Probe = .idle
    @State private var confirmingNewKey = false
    @State private var copied = false

    enum Probe: Equatable {
        case idle, running
        case answered(VersionAnswer)
        case failed(String)
    }

    // The fields are the open blog's own, written down as they are typed.
    private func field(_ key: WritableKeyPath<Blog, String>) -> Binding<String> {
        Binding(get: { blogs.current?[keyPath: key] ?? "" }, set: { value in blogs.update { $0[keyPath: key] = value } })
    }

    private var portText: Binding<String> {
        Binding(get: { String(blogs.current?.port ?? 22) },
                set: { value in blogs.update { $0.port = Int(value.filter(\.isNumber)) ?? $0.port } })
    }

    private var host: String { blogs.current?.host ?? "" }
    private var user: String { blogs.current?.user ?? "" }
    private var port: Int { blogs.current?.port ?? 22 }

    var body: some View {
        PaperScreen(name: String(localized: "The blog's settings")) {
            // Which blog's: the one the row was.
            if let label = blogs.current?.label, !label.isEmpty {
                Text(verbatim: label)
                    .font(.mono(12))
                    .foregroundStyle(.tint)
                    .padding(.top, 2)
            }

            SectionLabel("Server")
            Plate {
                FieldRow(label: "Host", text: field(\.host), mono: true)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                FieldRow(label: "User", text: field(\.user), mono: true)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                FieldRow(label: "Port", text: portText, mono: true)
                    .keyboardType(.numberPad)
                // Where on it the blog is, and what it is entered through.
                FieldRow(label: "path", text: field(\.path), prompt: "/home/you/blog", mono: true)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                FieldRow(label: "through", text: field(\.through), prompt: "sudo docker exec -i blog", mono: true)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
            }
            Hint("The line for the server's ~/.ssh/authorized_keys is made from where the blog is. A blog inside a container is reached through the command that enters it, for example sudo docker exec -i blog; one that is not in a container leaves that field empty.")

            SectionLabel("Key")
            if let publicKey {
                Plate {
                    Text(verbatim: publicKey)
                        .font(.mono(12, bold: false))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                    // No line until it can be a true one: a made-up path in it is a
                    // line somebody copies.
                    if let line = authorizedKeysLine(publicKey) {
                        Text(verbatim: line)
                            .font(.mono(12, bold: false))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                        // The key says that it took: the row is the only place to see it.
                        if copied {
                            DoneRow(label: "Copied")
                        } else {
                            Command("Copy the authorized_keys line", symbol: "doc.on.doc") {
                                UIPasteboard.general.string = line
                                copied = true
                                Task {
                                    try? await Task.sleep(for: .seconds(2))
                                    copied = false
                                }
                            }
                        }
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
                        Text(verbatim: answer.site.claim.isEmpty ? answer.site.name : "\(answer.site.name) — \(answer.site.claim.replacingOccurrences(of: "\n", with: " "))")
                            .font(.ui(15))
                        Text(verbatim: answer.site.url).font(.mono(12, bold: false)).foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.ink)
                }
                .gap(12)
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
                        // The kept connection was opened to the key just forgotten.
                        Engine.hangUp()
                    }
                }
                .gap(12)
            }

            // The blog leaves the app; nothing on the server is touched.
            if let blog = blogs.current {
                Plate {
                    Command("Remove this blog", symbol: "minus.circle", danger: true) { confirmingRemoval = true }
                        .confirmationDialog("Remove '\(blog.label)' from the app? Its key is deleted with it; the blog itself is not touched.",
                                            isPresented: $confirmingRemoval, titleVisibility: .visible) {
                            Button("Remove", role: .destructive) {
                                blogs.remove(blog.id)
                                dismiss()
                            }
                        }
                }
                .gap(28)
            }
        }
        .navigationTitle("The blog's settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { close() }
            }
        }
        .task(id: blogs.currentID) {
            publicKey = blogs.current.flatMap { try? KeyStore.publicKeyLine(account: $0.keyAccount) }
            probe = .idle
        }
    }

    /// The line, or nothing while the blog's place is not known. The forced
    /// command runs through the account's shell, so a path with a space in
    /// it (an iCloud folder on a Mac) is single-quoted inside the double
    /// quotes sshd takes; a plain path stays plain. Through a wrapper -- the
    /// command that enters a container, an `env PATH=…` for a Ruby the
    /// server's own PATH does not have -- the word SSH hands over does not
    /// reach the script by itself, so it is passed as its argument, which
    /// `scripts/remote.sh` takes the same way.
    private func authorizedKeysLine(_ publicKey: String) -> String? {
        KeyLine.compose(publicKey: publicKey, path: blogs.current?.path ?? "", through: blogs.current?.through ?? "")
    }

    private func makeKey() {
        do {
            guard let account = blogs.current?.keyAccount else { return }
            try KeyStore.makeKey(account: account)
            Engine.hangUp()
            publicKey = try KeyStore.publicKeyLine(account: account)
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
    NavigationStack { BlogSettingsView(close: {}) }
}
