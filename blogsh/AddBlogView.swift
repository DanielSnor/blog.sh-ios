import SwiftUI

/// "Add a blog": two ways in. With a code -- `./blog.sh pair` on the
/// server shows one, the app reads it with the camera (or is given its
/// line of text) and is connected, and nobody types an address, a user
/// name or a key -- or by hand, as before: the blog's
/// settings, a key made here and its line written into the server's
/// authorized_keys by whoever keeps that file.
struct AddBlogView: View {
    /// A code that came with the way in: a link opened from elsewhere.
    var initialCode = ""
    /// The blog the code is for, where it is one the app already has:
    /// paired again -- its server moved, or its line there is gone -- it
    /// stays the same blog, at the place the new code names.
    var renewing: Blog?
    /// Closes the sheet this screen stands in.
    let close: () -> Void
    private var blogs = Blogs.shared
    @State private var text = ""
    @State private var connecting = false
    @State private var problem: String?
    @State private var byHand = false
    @State private var scanning = false
    /// The camera was asked for and the answer was no.
    @State private var cameraRefused = false

    init(initialCode: String = "", renewing: Blog? = nil, close: @escaping () -> Void) {
        self.initialCode = initialCode
        self.renewing = renewing
        self.close = close
    }

    private var name: String { renewing == nil ? String(localized: "Add a blog") : String(localized: "Pair again") }

    /// What was pasted, read: a code, or why it is not one. Nothing while
    /// nothing is there.
    private var read: Result<PairingCode, PairingCode.Problem>? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do { return .success(try PairingCode(text)) } catch { return .failure(error) }
    }

    var body: some View {
        PaperScreen(name: name) {
            // Which blog's, and what a new code does to it.
            if let renewing {
                if !renewing.label.isEmpty {
                    Text(verbatim: renewing.label)
                        .font(.mono(12))
                        .foregroundStyle(.tint)
                        .padding(.top, 2)
                }
                Hint("A new code moves this blog to where the code points: another address or another computer. What is written for it on the device stays.")
                    .gap(10)
            }
            SectionLabel("With a code")
            Plate {
                // Where there is a camera that reads codes, that is the
                // first way; the line of text is for where there is none.
                if CodeScanner.isOffered {
                    Command("Scan the code", symbol: "qrcode.viewfinder") {
                        Task {
                            if await CodeScanner.allowed() {
                                cameraRefused = false
                                scanning = true
                            } else {
                                cameraRefused = true
                            }
                        }
                    }
                    .disabled(connecting)
                }
                HStack(alignment: .top, spacing: 6) {
                    TextField("", text: $text, prompt: Text(verbatim: "blogsh://pair?…").foregroundStyle(Theme.muted), axis: .vertical)
                        .font(.mono(13, bold: false))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2...6)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(connecting)
                    // What was pasted and is not a code -- a clipboard holds
                    // anything -- goes with one tap, and what was said of it too.
                    if !text.isEmpty {
                        Button {
                            text = ""
                            problem = nil
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.muted)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .disabled(connecting)
                        .accessibilityLabel(Text("Clear"))
                    }
                }
                PasteButton(payloadType: String.self) { pasted in
                    if let first = pasted.first { text = first }
                }
                .labelStyle(.titleAndIcon)
                .tint(Theme.accent)
                .disabled(connecting)
            }
            if cameraRefused {
                ProblemLine(text: String(localized: "The app is not allowed to use the camera. Allow it in the system's settings, or paste the code as text."))
            }
            if CodeScanner.isOffered {
                Hint("On the server, run ./blog.sh pair. It shows a code: scan it, or paste the line of text under it here.")
            } else {
                Hint("On the server, run ./blog.sh pair. It shows a code and under it the same thing as a line of text: paste that line here.")
            }

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

            // By hand is a way in for a blog the app does not have yet.
            if renewing == nil {
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
        }
        .navigationTitle(Text(verbatim: name))
        .navigationDestination(isPresented: $byHand) {
            BlogSettingsView(close: close)
        }
        .fullScreenCover(isPresented: $scanning) {
            // Whatever the camera read goes into the field: a code is then
            // asked about, and anything else is said not to be one.
            CodeScannerScreen { text = $0 }
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
        if let renewing {
            await renew(renewing, with: code)
            return
        }
        var blog = Blog()
        blog.host = code.host
        blog.port = code.port
        blog.user = code.user
        blog.name = code.site ?? ""
        do {
            try KeyStore.makeKey(account: blog.keyAccount)
            // The key and its kind, without the comment ssh-keygen would add.
            let line = try KeyStore.publicKeyLine(account: blog.keyAccount).split(separator: " ").prefix(2).joined(separator: " ")
            let device = UIDevice.current.name
            let handed = try await Pairing.handIn(line, named: device, with: code)
            // The server that answered is the one this blog's connections expect from now on.
            UserDefaults.standard.set(handed.server, forKey: TrustOnFirstUse.defaultsKey(host: code.host, port: code.port))
            blog.pairedAs = Pairing.known(as: handed.device, here: device)
            blogs.adopt(blog)
            Herald.shared.say(String(localized: "Connected: \(handed.device.isEmpty ? blog.label : handed.device)"))
            close()
        } catch let error as PairingError {
            try? KeyStore.deleteKey(account: blog.keyAccount)
            problem = Self.words(error, at: code)
        } catch {
            try? KeyStore.deleteKey(account: blog.keyAccount)
            problem = Self.words(PairingError.noKey, at: code)
        }
    }

    /// The key and its kind, without the comment ssh-keygen would add.
    private static func keyLine(_ account: String) throws -> String {
        try KeyStore.publicKeyLine(account: account).split(separator: " ").prefix(2).joined(separator: " ")
    }

    /// The same blog, let in again. The key it already has is handed in:
    /// the blog knows a device by its key, and writes the new line in
    /// the old one's place instead of beside it. Where that key stands on
    /// a line that is not a device's -- one written by hand -- the blog
    /// says so without spending the code, and a new key goes in with the
    /// same code; it becomes the blog's own only once it was taken, so a
    /// pairing that fails leaves the blog able to connect as it could.
    private func renew(_ blog: Blog, with code: PairingCode) async {
        let spare = blog.keyAccount + ".new"
        do {
            if !KeyStore.hasKey(account: blog.keyAccount) { try KeyStore.makeKey(account: blog.keyAccount) }
            let device = UIDevice.current.name
            var handed: (device: String, server: String)
            do {
                handed = try await Pairing.handIn(try Self.keyLine(blog.keyAccount), named: device, with: code)
            } catch PairingError.keyInUse {
                try KeyStore.makeKey(account: spare)
                handed = try await Pairing.handIn(try Self.keyLine(spare), named: device, with: code)
                try KeyStore.move(from: spare, to: blog.keyAccount)
            }
            UserDefaults.standard.set(handed.server, forKey: TrustOnFirstUse.defaultsKey(host: code.host, port: code.port))
            blogs.move(blog.id, to: code, as: Pairing.known(as: handed.device, here: device))
            // The kept connection is to where the blog was.
            Engine.hangUp()
            Herald.shared.say(String(localized: "Connected: \(handed.device.isEmpty ? blog.label : handed.device)"))
            close()
        } catch let error as PairingError {
            try? KeyStore.deleteKey(account: spare)
            problem = Self.words(error, at: code)
        } catch {
            try? KeyStore.deleteKey(account: spare)
            problem = Self.words(PairingError.noKey, at: code)
        }
    }

    private static func words(_ why: PairingCode.Problem) -> String {
        switch why {
        case .notACode: String(localized: "This is not a code from ./blog.sh pair.")
        case .anotherVersion: String(localized: "This code is of a newer kind than the app knows. Update the app.")
        case .incomplete: String(localized: "The code is not whole. Copy the whole line under the picture.")
        }
    }

    private static func words(_ why: PairingError, at code: PairingCode) -> String {
        switch why {
        case .spent: String(localized: "The code is no longer good: it lasts ten minutes and works once. Ask for a new one: ./blog.sh pair")
        case .wrongServer: String(localized: "Another machine answered than the one the code describes. Nothing was sent to it.")
        // Said as what to check, not as what the network library reported.
        case .unreachable: String(localized: "The server \(code.host) did not answer. Is this device on a network the server can be reached from?")
        case .refused(let words): String(localized: "The blog said no: \(words)")
        case .noKey: String(localized: "The app could not make its key.")
        case .keyInUse(let words): String(localized: "The blog said no: \(words)")
        }
    }
}

#Preview {
    NavigationStack { AddBlogView(close: {}) }
}
