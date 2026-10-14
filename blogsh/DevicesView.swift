import SwiftUI

/// The devices a code let in to the open blog, as `./blog.sh pair --list`
/// shows them at the terminal -- and the one thing a device may do about
/// them from here: take itself off. Another device is taken off on the
/// server, by whoever sits at it.
struct DevicesView: View {
    private var blogs = Blogs.shared
    @State private var answer: PairedDevices?
    @State private var problem: String?
    /// The blog is an older one, which does not show its devices to an app.
    @State private var notYet = false
    @State private var loading = false
    @State private var leaving = false
    /// This device was just taken off: said here, over who is left, for
    /// as long as the screen stands.
    @State private var gone = false
    @State private var confirming = false

    /// The key the app holds for this blog, as the list writes keys.
    private var key: String? {
        blogs.current.flatMap { try? KeyStore.fingerprint(account: $0.keyAccount) }
    }

    var body: some View {
        PaperScreen(name: String(localized: "Paired devices"), count: answer.flatMap { $0.devices.isEmpty ? nil : $0.devices.count.formatted() }) {
            // Which blog's: the one whose settings led here.
            if let label = blogs.current?.label, !label.isEmpty {
                Text(verbatim: label)
                    .font(.mono(12))
                    .foregroundStyle(.tint)
                    .padding(.top, 2)
            }
            if loading && answer == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .gap(40)
            }
            if notYet {
                Hint("This blog does not show its devices to the app yet; a newer ./blog.sh will. On the server, ./blog.sh pair --list shows them.")
                    .gap(10)
            }
            if let problem {
                ProblemLine(text: problem)
            }
            if gone {
                Plate {
                    Text("This device was taken off the blog. A new code lets it in again: Pair again, in the blog's settings.")
                        .font(.ui(15))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .gap(14)
            }
            if let answer {
                if answer.devices.isEmpty {
                    Hint("No device was let in to this blog by a code.")
                        .gap(10)
                } else {
                    // Each row says what is done about it: this device can take
                    // itself off, here, in its own row; another is taken off at
                    // the server, and its row says by what. A key for it set
                    // apart under the list left it to be guessed which row it was.
                    Plate {
                        ForEach(Array(answer.devices.enumerated()), id: \.offset) { index, device in
                            let this = answer.isThis(device, key: key)
                            row(index + 1, device, this: this, mayLeave: this && answer.mayLeave)
                        }
                    }
                    .gap(14)
                    Hint("The devices a code let in to this blog, as ./blog.sh pair --list shows them on the server. Another device is taken off there: ./blog.sh pair --revoke.")
                }
                if !answer.mayLeave && answer.holdsThis(key: key) {
                    Hint("The blog cannot tell yet which of these devices is asking, so this one cannot be taken off from here. On the server, ./blog.sh pair --list brings an older pairing up to date.")
                }
            }
        }
        .disabled(leaving)
        .navigationTitle("Paired devices")
        .task(id: blogs.currentID) {
            gone = false
            await load()
        }
    }

    /// One device: its number as `./blog.sh pair --list` counts it, its
    /// name, the mark on this one, the key the server knows it by -- and
    /// what is done about it: this one is taken off by the key under it,
    /// another on the server, by the command under it.
    private func row(_ number: Int, _ device: PairedDevices.Device, this: Bool, mayLeave: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: number.formatted())
                        .font(.mono(13))
                        .foregroundStyle(Theme.muted)
                    Text(verbatim: device.name.isEmpty ? "—" : device.name)
                        .font(.ui(15, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if this {
                        Text("this device").engineLabel().foregroundStyle(.tint)
                    }
                }
                if !device.fingerprint.isEmpty {
                    Text(verbatim: device.fingerprint)
                        .font(.mono(12, bold: false))
                        .foregroundStyle(Theme.muted)
                        .textSelection(.enabled)
                }
            }
            .accessibilityElement(children: .combine)
            if mayLeave {
                Command("Take this device off the blog", symbol: "minus.circle", danger: true, busy: leaving) { confirming = true }
                    .padding(.top, 6)
                    .confirmationDialog("Take this device off the blog '\(blogs.current?.label ?? "")'? The server will not let it in any more; to connect again, it needs a new code from ./blog.sh pair. The blog stays in the app, with what is written for it on this device.",
                                        isPresented: $confirming, titleVisibility: .visible) {
                        Button("Remove", role: .destructive) { Task { await leave() } }
                    }
            } else if !this && !device.fingerprint.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Taken off on the server with:")
                        .font(.ui(12))
                        .foregroundStyle(Theme.muted)
                    Text(verbatim: "./blog.sh pair --revoke \(device.fingerprint)")
                        .font(.mono(12, bold: false))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        problem = nil
        notYet = false
        do {
            answer = try await Engine.shared.call(["pair", "--list"])
        } catch where PairedDevices.notKnownThere(error) {
            answer = nil
            notYet = true
        } catch {
            answer = nil
            problem = PairedDevices.words(for: error)
        }
    }

    /// `pair --revoke`: the blog takes off whoever asks, and nobody else.
    /// The answer still comes over the connection that asked; the next
    /// one the server turns away, so the kept one is hung up with it.
    private func leave() async {
        leaving = true
        defer { leaving = false }
        problem = nil
        do {
            // Who is left comes with the answer.
            answer = try await Engine.shared.call(["pair", "--revoke"])
        } catch where PairedDevices.isGone(after: error) {
            // Taken off, and the answer lost on its way.
            answer = nil
        } catch {
            problem = PairedDevices.words(for: error)
            return
        }
        Engine.hangUp()
        gone = true
        Herald.shared.say(String(localized: "This device was taken off the blog."))
    }
}

#Preview {
    NavigationStack { DevicesView() }
}
