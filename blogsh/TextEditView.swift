import SwiftUI
import PhotosUI

/// "the text": what `./blog.sh edit` opens in the editor, opened here.
/// `edit <slug> --json` hands the text out with the post's pictures by
/// bare name and a digest; the save goes back the way a post from the
/// phone goes -- new pictures first, then the text as a file whose header
/// says which post it edits and which version it started from. A draft
/// gets its preview rebuilt; a published post is rebuilt and deployed.
///
/// Changes written and not saved are kept on the device (`Unsaved`) and
/// are back in the editor the next time the post is opened.
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
    /// Where the caret is in the text: where a picture's mark goes.
    @State private var caret: TextSelection?
    @State private var shots: [Shot] = []
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false
    /// Why the last picture chosen is not among the shots.
    @State private var unread: String?
    @State private var saving = false
    @State private var problem: String?
    @State private var saved: ActionAnswer?
    /// Counted when a save has answered: the page goes to the answer.
    @State private var answered = 0
    @State private var confirmingLoss = false
    @State private var previewing = false
    @State private var looking: Looked?
    /// The changes brought back when the text was opened, for the line that says so.
    @State private var broughtBack: Unsaved?

    var body: some View {
        PaperScreen(title: entry?.title, answered: answered) {
            if let entry {
                if let broughtBack {
                    BroughtBack(words: Unsaved.words(broughtBack, over: entry.base, media: entry.media),
                                key: "Take the text as the blog has it") { takeTheBlogs() }
                        .gap(14)
                        .gap(14, .bottom)
                }
                if !entry.editable {
                    Hint(verbatim: entry.problem.map { String(localized: "This post cannot be edited here: \($0). At the desk, edit asks before losing it; here nobody could answer.") }
                         ?? String(localized: "This post cannot be edited here."))
                }
                Plate {
                    // Left alone while a save is on its way: what is typed
                    // then would be neither in what was saved nor kept.
                    PaperEditor(text: $text, selection: $caret, minHeight: 320)
                        .disabled(!entry.editable || saving)
                }
                .padding(.top, entry.editable ? 0 : 14)
                Hint("The header and the text, as the editor opens them. A picture is named by its file name.")
                Plate {
                    Command("Preview", symbol: "eye") { previewing = true }
                }
                .gap(10)

                if !entry.media.isEmpty {
                    SectionLabel("Pictures on the blog")
                    Plate {
                        ForEach(entry.media, id: \.self) { name in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(verbatim: name).font(.mono(13, bold: false)).foregroundStyle(Theme.ink)
                                Spacer(minLength: 8)
                                if Kept.named(name, in: text) {
                                    Text("in the text").font(.ui(13)).foregroundStyle(Theme.muted)
                                } else {
                                    // Whether or not another takes its place: the
                                    // blog deletes a picture its text stopped naming.
                                    Text("not named — deleted on save").font(.ui(13)).foregroundStyle(Theme.danger)
                                }
                            }
                        }
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
                if let unread { ProblemLine(text: unread) }
                DeliveryNote(shots: Kept.sent(shots, text: text), textBytes: text.utf8.count, maxMb: maxMb)

                Button {
                    // Asked whenever the save would delete a picture -- one
                    // swapped for another, or one simply taken out. The blog
                    // used to refuse a save that left the post with fewer, and
                    // the app left that case to it; it takes such a save now,
                    // and deletes the picture for good.
                    if Kept.asksBeforeSaving(media: entry.media, text: text) { confirmingLoss = true } else { Task { await save() } }
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
                .gap(22)
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
                if let stranded {
                    Stranded(kept: stranded) {
                        if let blog = Blogs.shared.currentID { Unsaved.forget(for: blog, slug: slug, what: .text) }
                        Desk.shared.changed()
                    }
                }
            }
        }
        .overlay { if entry == nil && problem == nil { ProgressView() } }
        .navigationTitle(entry?.title ?? slug)
        .task { await load() }
        // A description typed on a card goes into the mark the text has for it.
        // ...and one typed into the text goes onto the card: the two are one.
        .onChange(of: text) { _, now in
            shots = Kept.heard(shots, from: now)
            keep()
        }
        .onChange(of: shots.map(\.alt)) { before, _ in
            text = Kept.retitled(text, shots: shots, before: before)
        }
        // A picture just chosen, whose mark the text already has, takes its words too.
        .onChange(of: shots.count) { _, _ in
            shots = Kept.heard(shots, from: text)
        }
        .onChange(of: picked) { _, items in Task { await loadPictures(items) } }
        .sheet(isPresented: $previewing) {
            // The post's own media from beside its page on the blog; what
            // was picked here from the device.
            let parts = Preview.parts(of: text)
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

    // MARK: - Kept until saved

    /// The text the editor opens with: the blog's, or -- where changes to
    /// it were written here and never saved -- those.
    private func opened(_ entry: EditEntry, with fresh: String) -> String {
        guard entry.editable, let blog = Blogs.shared.currentID,
              let kept = Unsaved.kept(for: blog, slug: slug, what: .text), kept.text != fresh else {
            broughtBack = nil
            return fresh
        }
        broughtBack = kept
        return kept.text
    }

    /// What is kept for this post while the post itself did not open.
    private var stranded: Unsaved? {
        _ = Desk.shared.changes
        return Blogs.shared.currentID.flatMap { Unsaved.kept(for: $0, slug: slug, what: .text) }
    }

    /// At every letter; a text that is the blog's again is nothing to keep.
    private func keep() {
        guard let entry, entry.editable, let fresh = entry.text, let blog = Blogs.shared.currentID else { return }
        if text == fresh {
            Unsaved.forget(for: blog, slug: slug, what: .text)
            broughtBack = nil
        } else {
            Unsaved.now(text, title: entry.title, over: entry.base, begun: broughtBack).keep(for: blog, slug: slug, what: .text)
        }
        Desk.shared.changed()
    }

    private func takeTheBlogs() {
        broughtBack = nil
        shots = []
        text = entry?.text ?? ""
        if let blog = Blogs.shared.currentID { Unsaved.forget(for: blog, slug: slug, what: .text) }
    }

    private func load() async {
        // Once: after a save the text is asked for afresh, with its new version.
        if let loaded, !tookLoaded, let handed = loaded.text {
            tookLoaded = true
            entry = loaded
            text = opened(loaded, with: handed)
            return
        }
        tookLoaded = true
        do {
            let answer: EditAnswer = try await Engine.shared.call(["edit", slug])
            entry = answer.post
            text = opened(answer.post, with: answer.post.text ?? "")
            problem = answer.post.text == nil ? String(localized: "The text did not come with the answer.") : nil
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }

    private func loadPictures(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        importing = true
        unread = nil
        defer { importing = false; picked = [] }
        for item in items {
            let taken = (entry?.media ?? []) + shots.map(\.name)
            do {
                shots.append(try await Media.shot(from: item, index: taken.count + 1, taken: taken))
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

    /// The header gets the two lines of the delivery: which post, which version.
    private func fileText() -> String {
        guard let entry else { return text }
        // The text is what goes: a description typed on a card is in it
        // already, one typed into the text itself was never the card's.
        let marked = text
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
        // Whose post it is and what goes, said before anything is waited for.
        let blog = Blogs.shared.currentID
        let going = text
        do {
            saved = try Engine.made(from: await Engine.shared.deliver(files, to: blog))
            shots = []
            // Saved: what went is not left to bring back.
            if let blog { Unsaved.forget(for: blog, slug: slug, what: .text, saved: going) }
            broughtBack = nil
            Desk.shared.changed()
            // Saving a published post builds the site: nothing is owed after it.
            if saved?.state == .published { Herald.shared.settled() }
            await load()
            answered += 1
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
            answered += 1
        }
    }
}

#Preview {
    NavigationStack { TextEditView(slug: "venku") }
}
