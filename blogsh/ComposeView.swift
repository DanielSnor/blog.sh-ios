import SwiftUI
import PhotosUI

/// "New post": what /write/ offers, as a form -- a title, the text, the
/// tags, photographs each with its description -- sent the way the page
/// sends it: the pictures first, the markdown last, one delivery. The
/// post arrives as a draft with a preview; publishing is its properties'
/// decision, the way it is at the desk.
///
/// What is written is kept on the device at every letter (`Unsent`) and
/// is back in the form the next time it opens, until it is sent.
struct ComposeView: View {
    /// The receiver's ceiling on one delivery, as the blog last said it.
    private var maxMb: Int { Blogs.shared.current?.maxMb ?? 24 }
    @State private var title = ""
    @State private var tags = ""
    @State private var text = ""
    /// Where the caret is in the text: where a picture's mark goes.
    @State private var caret: TextSelection?
    @State private var shots: [Shot] = []
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false
    /// Why the last picture chosen is not among the shots.
    @State private var unread: String?
    @State private var sending = false
    @State private var problem: String?
    @State private var made: ActionAnswer?
    /// The post was put by on the device: said where an answer would be.
    @State private var putBy = false
    /// Counted when a sending has answered: the page goes to the answer.
    @State private var answered = 0
    @State private var previewing = false
    @State private var looking: Looked?
    /// What was brought back when the form opened, for the line that says so.
    @State private var broughtBack: Unsent?
    /// The blog the form writes for, once it has looked what is kept for it.
    @State private var keeping: UUID?
    @FocusState private var bodyFocused: Bool

    var body: some View {
        PaperScreen(name: String(localized: "New post"), symbol: MenuEntry.add.symbol, answered: answered) {
            if let broughtBack {
                // Said, because it was not asked for: the form opens with
                // something in it that was not typed just now.
                BroughtBack(words: broughtBack.namesPictures
                                ? Text("Back in the form: what was written here \(broughtBack.at.spoken) and not sent.") + Text(verbatim: " ") + Text("Its pictures were not kept; add them again.")
                                : Text("Back in the form: what was written here \(broughtBack.at.spoken) and not sent."),
                            key: "Start with an empty form") { startEmpty() }
                    .gap(14)
            }
            Plate {
                TextField("", text: $title, prompt: Text("Title").foregroundStyle(Theme.muted))
                    .font(.ui(18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                PaperEditor(text: $text, selection: $caret, minHeight: 200)
                    .focused($bodyFocused)
                FieldRow(label: "tags", text: $tags, prompt: String(localized: "Comma separated."))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .task { await TagStore.shared.loadIfNeeded() }
                TagSuggestions(text: $tags)
            }
            .gap(14)
            // Said as it is typed: the marks in the sentence are examples, not marks.
            Hint(verbatim: String(localized: "Markdown. A picture goes in as ![description](photo.jpg), a video as !![description](clip.mp4) -- the bare name, no path."))
            Plate {
                Command("Preview", symbol: "eye") { previewing = true }
            }
            .gap(10)

            SectionLabel("Pictures and video")
            Plate {
                ForEach($shots) { $shot in
                    ShotCard(shot: $shot, inText: self.text.contains("(\(shot.name))")) {
                        insert(shot)
                    } remove: {
                        remove(shot)
                    } look: {
                        looking = Looked(id: shot.id)
                    }
                }
                // Read here, on the main actor: the picker's label is built off it.
                let reading = importing
                PhotosPicker(selection: $picked, matching: .any(of: [.images, .videos])) {
                    CommandRow(reading ? "Reading…" : "Add a picture or video", symbol: "photo.on.rectangle", busy: reading)
                }
                .buttonStyle(PressStyle())
                .disabled(importing)
            }
            if let unread { ProblemLine(text: unread) }
            DeliveryNote(shots: sent, textBytes: text.utf8.count, maxMb: maxMb)

            // With the server silent the same key keeps the post on the
            // device instead, whole, to go when the server answers.
            Button {
                if offline { keepOnDevice() } else { Task { await send() } }
            } label: {
                PrimaryLabel(label: sending ? "Sending…" : (offline ? "Keep on the device" : "Send to the blog as a draft"), busy: sending)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending || importing || (title.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || overweight)
            .gap(22)
            if offline {
                Hint("The blog's server cannot be reached. Kept on the device, the post goes to the blog as a draft, with its pictures, once the server answers.")
            }
            if let problem {
                ProblemLine(text: problem)
            }

            if putBy {
                SectionLabel("Done")
                Plate {
                    Text("Kept on the device. It goes to the blog as a draft once the server answers.")
                        .font(.ui(15)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let made {
                SectionLabel("Done")
                Plate {
                    Text("Draft written: \(made.slug)").font(.ui(15)).foregroundStyle(Theme.ink)
                    if let warnings = made.warnings?.plain {
                        ForEach(warnings, id: \.self) { Text(verbatim: $0).font(.ui(13)).foregroundStyle(Theme.muted) }
                    }
                    if let url = made.url, !url.isEmpty, let link = URL(string: url) {
                        Link(destination: link) { CommandRow("Open the preview", symbol: "safari") }
                            .buttonStyle(PressStyle())
                    }
                    // Deleted from there, the post is not this form's to point at any more.
                    NavigationLink { PropsView(slug: made.slug, gone: { self.made = nil }) } label: {
                        CommandRow("Its properties and the actions on it", symbol: "slider.horizontal.3", leads: true)
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .navigationTitle("New post")
        .task { bringBack() }
        // Kept at every letter: there is no moment at which an app is told
        // it is about to be closed.
        .onChange(of: [title, tags, text]) { _, _ in keep() }
        // A description typed on a card goes into the mark the text has for it.
        // ...and one typed into the text goes onto the card: the two are one.
        .onChange(of: text) { _, now in
            shots = Kept.heard(shots, from: now)
        }
        .onChange(of: shots.map(\.alt)) { before, _ in
            text = Kept.retitled(text, shots: shots, before: before)
        }
        // A picture just chosen, whose mark the text already has, takes its words too.
        .onChange(of: shots.count) { _, _ in
            shots = Kept.heard(shots, from: text)
        }
        .onChange(of: picked) { _, items in
            Task { await load(items) }
        }
        .sheet(isPresented: $previewing) {
            PreviewSheet(title: title, markdown: text, shown: Preview.shown(for: shots))
        }
        .fullScreenCover(item: $looking) { one in
            ShotsViewer(shots: $shots, current: one.id)
        }
    }

    // MARK: - Kept until sent

    /// Once, when the form opens: what was written for this blog and not
    /// sent is put back -- unless something is in the form already.
    private func bringBack() {
        guard keeping == nil, let blog = Blogs.shared.currentID else { return }
        keeping = blog
        // A post that waited to be sent and was taken back to be written
        // on: it is the form's now, pictures and all, and waits no longer.
        if let handed = Desk.shared.takeHanded() {
            shots = WaitingRoom.shots(of: handed, for: blog)
            title = handed.title
            tags = handed.tags
            text = handed.text
            WaitingRoom.remove(handed.id, for: blog)
            Desk.shared.changed()
            return
        }
        guard title.isEmpty, tags.isEmpty, text.isEmpty, let kept = Unsent.kept(for: blog) else { return }
        title = kept.title
        tags = kept.tags
        text = kept.text
        broughtBack = kept
    }

    private func keep() {
        guard let keeping else { return }
        Unsent(title: title, tags: tags, text: text, at: .now).keep(for: keeping)
        Desk.shared.changed()
    }

    private func startEmpty() {
        title = ""; tags = ""; text = ""; shots = []
        broughtBack = nil
    }

    // MARK: - Pictures

    private func load(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        importing = true
        unread = nil
        defer { importing = false; picked = [] }
        for item in items {
            do {
                shots.append(try await Media.shot(from: item, index: shots.count + 1, taken: shots.map(\.name)))
            } catch {
                // Said at the key that was pressed, not at the form's end.
                unread = error.words
            }
        }
    }

    /// Where the caret is, a paragraph of its own; the caret goes on after it.
    private func insert(_ shot: Shot) {
        let put = Kept.placed(shot.mark, in: text, at: caret?.range(in: text)?.location)
        text = put.text
        caret = TextSelection(caret: put.caret, in: put.text)
    }

    private func remove(_ shot: Shot) {
        shots.removeAll { $0.id == shot.id }
        text = text.replacingOccurrences(of: #"\n*"# + shot.markPattern + #"\n*"#, with: "\n\n", options: .regularExpression)
    }

    private var overweight: Bool { Delivery.over(shots: sent, textBytes: text.utf8.count, maxMb: maxMb) }

    /// The shots the text names: only those go.
    private var sent: [Shot] { Kept.sent(shots, text: text) }

    // MARK: - Sending

    /// The open blog's server did not answer the last time it was asked.
    private var offline: Bool { Reach.shared.isOffline(Blogs.shared.current) }

    /// Put by on the device, whole: the text and the shots it names. The
    /// form is the next post's, as after a sending.
    private func keepOnDevice() {
        guard let blog = Blogs.shared.currentID else { return }
        problem = nil
        made = nil
        do {
            try WaitingRoom.put(Waiting(title: title, tags: tags, text: text, at: .now), shots: sent, for: blog)
            title = ""; tags = ""; text = ""; shots = []
            broughtBack = nil
            putBy = true
            Desk.shared.changed()
        } catch {
            problem = String(localized: "The post could not be kept on the device: \(error.localizedDescription)")
        }
        answered += 1
    }

    private func send() async {
        sending = true
        defer { sending = false }
        problem = nil
        putBy = false
        // The text is what goes: a description typed on a card is in it
        // already, one typed into the text itself was never the card's.
        let markdown = Markdown.file(title: title, tags: tags, body: text)
        var files = sent.map { DeliveryFile(name: $0.name, data: $0.data) }
        files.append(DeliveryFile(name: Markdown.fileName(title: title, body: text), data: Data(markdown.utf8)))
        do {
            made = try Engine.made(from: await Engine.shared.deliver(files))
            // The form is the next post's now, and nothing is left to bring back.
            title = ""; tags = ""; text = ""; shots = []
            broughtBack = nil
            answered += 1
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
            answered += 1
        }
    }
}

/// Which shot the viewer opens on.
struct Looked: Identifiable {
    let id: UUID
}

/// One shot's card: what it looks like, its name as the text names it
/// and what it weighs, its description, and the way into the text.
struct ShotCard: View {
    @Binding var shot: Shot
    let inText: Bool
    let insert: () -> Void
    let remove: () -> Void
    /// The shot large, with its description under it.
    var look: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The small picture is a key: behind it the shot is large enough
            // to tell from the next one, and to describe.
            Button(action: look) {
                if let image = UIImage(data: shot.thumb ?? (shot.kind == .video ? (shot.poster ?? Data()) : shot.data)) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            if shot.kind == .video {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white)
                                    .padding(5)
                                    .background(.black.opacity(0.55), in: Circle())
                                    .padding(4)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.black.opacity(0.55), in: Circle())
                                .padding(4)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                        .frame(width: 84, height: 84)
                        .overlay(Image(systemName: shot.kind == .video ? "film" : "photo").foregroundStyle(Theme.muted))
                }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(Text("Look at the picture"))
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: shot.name).font(.mono(12, bold: false)).foregroundStyle(Theme.muted).lineLimit(1)
                    if shot.kind == .video {
                        Text("video").engineLabel(11).foregroundStyle(.tint)
                    }
                    Spacer(minLength: 4)
                    Text(verbatim: Delivery.size(shot.data.count)).font(.mono(11, bold: false)).foregroundStyle(Theme.muted)
                }
                // The same words as in the picture's mark in the text: written
                // here or there, they are one description.
                TextField("", text: $shot.alt, prompt: Text("No description yet").foregroundStyle(Theme.muted))
                    .font(.ui(15))
                    .foregroundStyle(Theme.ink)
                // Two keys for a finger, not two words: each is as tall as a
                // finger needs and takes its half of the row.
                HStack(spacing: 0) {
                    Button(action: insert) {
                        Text(inText ? "Used in the text" : "Insert into text").engineLabel(12)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(inText ? AnyShapeStyle(Theme.muted) : AnyShapeStyle(.tint))
                    .disabled(inText)
                    Button(action: remove) {
                        Text("Remove").engineLabel(12)
                            .frame(minWidth: 88, minHeight: 40, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(Theme.danger)
                }
                .buttonStyle(PressStyle())
                .padding(.vertical, -6)
                // Said on the card, before the post goes: what the text
                // does not name stays behind.
                if !inText {
                    Text("Not in the text — it will not be sent with the post.")
                        .font(.ui(12))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}


#Preview {
    NavigationStack { ComposeView() }
}
