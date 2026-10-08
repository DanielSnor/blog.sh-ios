import SwiftUI

/// "Add a blog": two ways in. With a code -- `./blog.sh pair` on the
/// server shows one, the app reads it and is connected, and nobody types
/// an address, a user name or a key -- or by hand, as before: the blog's
/// settings, a key made here and its line written into the server's
/// authorized_keys by whoever keeps that file.
struct AddBlogView: View {
    /// A code that came with the way in: a link opened from elsewhere.
    var initialCode = ""
    /// Closes the sheet this screen stands in.
    let close: () -> Void
    private var blogs = Blogs.shared
    @State private var text = ""
    @State private var connecting = false
    @State private var problem: String?
    @State private var byHand = false

    init(initialCode: String = "", close: @escaping () -> Void) {
        self.initialCode = initialCode
        self.close = close
    }

    /// What was pasted, read: a code, or why it is not one. Nothing while
    /// nothing is there.
    private var read: Result<PairingCode, PairingCode.Problem>? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do { return .success(try PairingCode(text)) } catch { return .failure(error) }
    }

    var body: some View {
        PaperScreen(name: String(localized: "Add a blog")) {
            SectionLabel("With a code")
            Plate {
                TextField("", text: $text, prompt: Text(verbatim: "blogsh://pair?…").foregroundStyle(Theme.muted), axis: .vertical)
                    .font(.mono(13, bold: false))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2...6)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .disabled(connecting)
                PasteButton(payloadType: String.self) { pasted in
                    if let first = pasted.first { text = first }
                }
                .labelStyle(.titleAndIcon)
                .tint(Theme.accent)
                .disabled(connecting)
            }
            Hint("On the server, run ./blog.sh pair. It shows a code and under it the same thing as a line of text: paste that line here.")

            switch read {
            case .success(let code):
                Plate {
                    Text("Connect to \(code.site ?? code.host)?")
                        .font(.ui(15, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    InfoRow(label: "Host", value: "\(code.host):\(String(code.port))", mono: true)
                    InfoRow(label: "User", value: code.user, mono: true)
                }
                .gap(14)
                Button {
                    Task { await connect(code) }
                } label: {
                    PrimaryLabel(label: connecting ? "Connecting…" : "Connect", busy: connecting)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(connecting)
                .gap(22)
            case .failure(let why):
                ProblemLine(text: Self.words(why))
            case nil:
                EmptyView()
            }
            if let problem {
                ProblemLine(text: problem)
            }

            SectionLabel("By hand")
            Plate {
                Command("Set up by hand", symbol: "wrench.and.screwdriver", leads: true) {
                    blogs.add()
                    byHand = true
                }
                .disabled(connecting)
            }
            Hint("For a blog that lives in a container, or to write the line into authorized_keys yourself.")
        }
        .navigationTitle("Add a blog")
        .navigationDestination(isPresented: $byHand) {
            BlogSettingsView(close: close)
        }
        .onAppear { if text.isEmpty { text = initialCode } }
        .onChange(of: text) { problem = nil }
    }

    /// The exchange: a key of the app's own is made, handed in with the
    /// code's, and the blog is the app's from then on. A code that did
    /// not take leaves nothing behind -- no blog, no key.
    private func connect(_ code: PairingCode) async {
        connecting = true
        defer { connecting = false }
        problem = nil
        var blog = Blog()
        blog.host = code.host
        blog.port = code.port
        blog.user = code.user
        blog.name = code.site ?? ""
        do {
            try KeyStore.makeKey(account: blog.keyAccount)
            // The key and its kind, without the comment ssh-keygen would add.
            let line = try KeyStore.publicKeyLine(account: blog.keyAccount).split(separator: " ").prefix(2).joined(separator: " ")
            let handed = try await Pairing.handIn(line, named: UIDevice.current.name, with: code)
            // The server that answered is the one this blog's connections expect from now on.
            UserDefaults.standard.set(handed.server, forKey: TrustOnFirstUse.defaultsKey(host: code.host, port: code.port))
            blogs.adopt(blog)
            Herald.shared.say(String(localized: "Connected: \(handed.device.isEmpty ? blog.label : handed.device)"))
            close()
        } catch let error as PairingError {
            try? KeyStore.deleteKey(account: blog.keyAccount)
            problem = Self.words(error)
        } catch {
            try? KeyStore.deleteKey(account: blog.keyAccount)
            problem = Self.words(PairingError.noKey)
        }
    }

    private static func words(_ why: PairingCode.Problem) -> String {
        switch why {
        case .notACode: String(localized: "This is not a code from ./blog.sh pair.")
        case .anotherVersion: String(localized: "This code is of a newer kind than the app knows. Update the app.")
        case .incomplete: String(localized: "The code is not whole. Copy the whole line under the picture.")
        }
    }

    private static func words(_ why: PairingError) -> String {
        switch why {
        case .spent: String(localized: "The code is no longer good: it lasts ten minutes and works once. Ask for a new one: ./blog.sh pair")
        case .wrongServer: String(localized: "Another machine answered than the one the code describes. Nothing was sent to it.")
        case .unreachable(let how): String(localized: "The server did not answer: \(how)")
        case .refused(let words): String(localized: "The blog said no: \(words)")
        case .noKey: String(localized: "The app could not make its key.")
        }
    }
}

#Preview {
    NavigationStack { AddBlogView(close: {}) }
}
