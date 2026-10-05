import SwiftUI
import PhotosUI

/// "the text": what `./blog.sh edit` opens in the editor, opened here.
/// `edit <slug> --json` hands the text out with the post's pictures by
/// bare name and a digest; the save goes back the way a post from the
/// phone goes -- new pictures first, then the text as a file whose header
/// says which post it edits and which version it started from. A draft
/// gets its preview rebuilt; a published post is rebuilt and deployed.
struct TextEditView: View {
    let slug: String
    /// The text already handed out to the screen before this one, so the
    /// first look need not ask the engine again.
    var loaded: EditEntry?
    @State private var tookLoaded = false
    /// The receiver's ceiling on one delivery, as the blog last said it.
    private var maxMb: Int { Blogs.shared.current?.maxMb ?? 24 }
    @Environment(\.dismiss) private var dismiss
    @State private var entry: EditEntry?
    @State private var text = ""
    @State private var shots: [Shot] = []
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var saving = false
    @State private var problem: String?
    @State private var saved: ActionAnswer?
    @State private var confirmingLoss = false
    @State private var previewing = false
    @State private var looking: Looked?

    var body: some View {
        PaperScreen {
            if let entry {
                PostHeading(title: entry.title, detail: entry.slug)
                if !entry.editable {
                    Hint(verbatim: entry.problem.map { String(localized: "This post cannot be edited here: \($0). At the desk, edit asks before losing it; here nobody could answer.") }
                         ?? String(localized: "This post cannot be edited here."))
                }
                Plate {
                    PaperEditor(text: $text, minHeight: 320)
                        .disabled(!entry.editable)
                }
                .padding(.top, 14)
                Hint("The header and the text, as the editor opens them. A picture is named by its file name.")
                Plate {
                    Command("Preview", symbol: "eye") { previewing = true }
                }
                .padding(.top, 10)

                if !entry.media.isEmpty {
                    SectionLabel("Pictures on the blog")
                    Plate {
                        ForEach(entry.media, id: \.self) { name in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(verbatim: name).font(.mono(13, bold: false)).foregroundStyle(Theme.ink)
                                Spacer(minLength: 8)
                                if Kept.named(name, in: text) {
                                    Text("in the text").font(.ui(13)).foregroundStyle(Theme.muted)
                                } else if fewer {
                                    // Not a promise the blog would not keep: see the hint under the list.
                                    Text("not in the text").font(.ui(13)).foregroundStyle(Theme.danger)
                                } else {
                                    Text("not named — deleted on save").font(.ui(13)).foregroundStyle(Theme.danger)
                                }
                            }
                        }
                    }
                    // Said before the save, not after it: what the blog will answer.
                    if fewer {
                        Hint(verbatim: String(localized: "The text names fewer pictures than the post has. From the app a picture can be swapped for another, not taken out: the blog refuses a save that would leave the post with fewer. Taking pictures out is done at the desk, with ./blog.sh edit."))
                    }
                }

                SectionLabel("Pictures and video")
                Plate {
                    ForEach($shots) { $shot in
                        ShotCard(shot: $shot, inText: self.text.contains("(\(shot.name))")) {
                            insert(shot)
                        } remove: {
                            shots.removeAll { $0.id == shot.id }
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
                    .disabled(importing || !entry.editable)
                }
                DeliveryNote(shots: Kept.sent(shots, text: text), textBytes: text.utf8.count, maxMb: maxMb)

                Button {
                    // The question is asked where the answer counts: a swap deletes
                    // the picture it replaces. Fewer than before is the blog's to
                    // refuse, and the hint above has said so.
                    if dropped.isEmpty || fewer { Task { await save() } } else { confirmingLoss = true }
                } label: {
                    PrimaryLabel(label: saving ? "Saving…" : (entry.scheduled || isDraft ? "Save the draft" : "Save and publish the change"),
                                 busy: saving)
                }
                .buttonStyle(PrimaryButtonStyle())
                .confirmationDialog("Pictures the text no longer names are deleted from the blog: \(dropped.joined(separator: ", ")). Save anyway?",
                                    isPresented: $confirmingLoss, titleVisibility: .visible) {
                    Button("Save and delete them", role: .destructive) { Task { await save() } }
                }
                .disabled(saving || importing || !entry.editable || text == entry.text
                          || Delivery.over(shots: Kept.sent(shots, text: text), textBytes: text.utf8.count, maxMb: maxMb))
                .padding(.top, 22)
                if let problem {
                    ProblemLine(text: problem)
                } else if !isDraft {
                    Hint("The post is live: saving rebuilds and deploys the site.")
                }

                if let saved {
                    SectionLabel("Saved")
                    Plate {
                        Text(verbatim: "\(saved.slug): " + (saved.state == .published
                            ? String(localized: "saved.published", defaultValue: "published")
                            : String(localized: "saved.draft", defaultValue: "draft")))
                            .font(.ui(15)).foregroundStyle(Theme.ink)
                        if let warnings = saved.warnings?.plain {
                            ForEach(warnings, id: \.self) { Text(verbatim: $0).font(.ui(13)).foregroundStyle(Theme.muted) }
                        }
                        // The editor closes on a save; here the way back is a key.
                        Command("Back to the post", symbol: "arrow.left") { dismiss() }
                    }
                }
            } else if let problem {
                ProblemLine(text: problem)
            }
        }
        .overlay { if entry == nil && problem == nil { ProgressView() } }
        .navigationTitle(entry?.title ?? slug)
        .task { await load() }
        .onChange(of: picked) { _, items in Task { await loadPictures(items) } }
        .sheet(isPresented: $previewing) {
            // The post's own media from beside its page on the blog; what
            // was picked here from the device.
            let parts = Preview.parts(of: described(text))
            let own = Preview.shown(media: entry?.media ?? [], beside: entry?.preview ?? "/")
            PreviewSheet(title: parts.title, markdown: parts.body,
                         shown: own.merging(Preview.shown(for: shots)) { _, new in new })
        }
        .fullScreenCover(item: $looking) { one in
            ShotsViewer(shots: $shots, current: one.id)
        }
    }

    private var isDraft: Bool {
        guard let entry else { return true }
        return entry.preview.hasPrefix("/draft/")
    }

    /// Pictures the post has that the text stops naming.
    private var dropped: [String] {
        Kept.dropped(media: entry?.media ?? [], text: text)
    }

    /// The save would leave the post with fewer pictures than it had.
    private var fewer: Bool {
        Kept.fewer(media: entry?.media ?? [], shots: shots, text: text)
    }

    private func load() async {
        // Once: after a save the text is asked for afresh, with its new version.
        if let loaded, !tookLoaded, let handed = loaded.text {
            tookLoaded = true
            entry = loaded
            text = handed
            return
        }
        tookLoaded = true
        do {
            let answer: EditAnswer = try await Engine.shared.call(["edit", slug])
            entry = answer.post
            text = answer.post.text ?? ""
            problem = answer.post.text == nil ? String(localized: "The text did not come with the answer.") : nil
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }

    private func loadPictures(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        importing = true
        defer { importing = false; picked = [] }
        for item in items {
            let taken = (entry?.media ?? []) + shots.map(\.name)
            guard let shot = await Media.shot(from: item, index: taken.count + 1, taken: taken) else {
                problem = String(localized: "One picture could not be read.")
                continue
            }
            shots.append(shot)
        }
    }

    private func insert(_ shot: Shot) {
        var kept = text
        while kept.hasSuffix("\n") { kept.removeLast() }
        text = kept + "\n\n" + shot.mark + "\n"
    }

    /// The text with every new shot's mark carrying its description as it stands now.
    private func described(_ text: String) -> String {
        var marked = text
        for shot in shots {
            marked = marked.replacingOccurrences(of: shot.markPattern,
                                                 with: NSRegularExpression.escapedTemplate(for: shot.mark), options: .regularExpression)
        }
        return marked
    }

    /// The header gets the two lines of the delivery: which post, which version.
    private func fileText() -> String {
        guard let entry else { return text }
        let marked = described(text)
        let lines = "edits: \(entry.slug)\nbase: \(entry.base)\n"
        if marked.hasPrefix("---\n") {
            return "---\n" + lines + marked.dropFirst(4)
        }
        return "---\n" + lines + "---\n\n" + marked
    }

    private func save() async {
        saving = true
        defer { saving = false }
        problem = nil
        var files = Kept.sent(shots, text: text).map { DeliveryFile(name: $0.name, data: $0.data) }
        files.append(DeliveryFile(name: "\(slug).md", data: Data(fileText().utf8)))
        do {
            let answers = try await Engine.shared.deliver(files)
            let decoder = JSONDecoder()
            for answer in answers {
                if let refusal = try? decoder.decode(Refusal.self, from: answer), refusal.ok == false {
                    throw EngineError.refused(refusal)
                }
            }
            guard let last = answers.last else { throw EngineError.unreadable("") }
            saved = try decoder.decode(ActionAnswer.self, from: last)
            shots = []
            await load()
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { TextEditView(slug: "venku") }
}
