import SwiftUI

/// [l]: the post's words in another language the site publishes. What
/// `translate` opens in the editor, opened here: the translation's header
/// (its title, its address) and its text, with the original beside it to
/// translate from. The save goes back as a file saying which post, which
/// version and which language; an empty title and body take the language
/// off the post, as the editor's hint says.
///
/// What is written and not saved is kept on the device (`Unsaved`), for
/// this post and this language, and is back the next time it is opened.
struct TranslateView: View {
    let slug: String
    let lang: String
    @Environment(\.dismiss) private var dismiss
    @State private var entry: TranslationEntry?
    @State private var text = ""
    @State private var showingOriginal = true
    @State private var saving = false
    @State private var problem: String?
    /// The save was turned away because the post has changed on the blog
    /// since its text was opened here.
    @State private var changedOnBlog = false
    @State private var saved: ActionAnswer?
    /// The last save took the language off rather than wrote it.
    @State private var tookOff = false
    /// Counted when a save has answered: the page goes to the answer.
    @State private var answered = 0
    @State private var confirmingRemoval = false
    @State private var previewing = false
    /// The words brought back when the screen opened, for the line that says so.
    @State private var broughtBack: Unsaved?

    private var languageName: String { Locale.current.localizedString(forLanguageCode: lang) ?? lang }

    var body: some View {
        PaperScreen(title: entry?.title, answered: answered) {
            if let entry {
                if let broughtBack {
                    BroughtBack(words: Unsaved.words(broughtBack, over: entry.base, media: nil),
                                key: "Take the text as the blog has it") { takeTheBlogs() }
                        .gap(14)
                }
                SectionLabel("The original")
                Plate {
                    Button {
                        showingOriginal.toggle()
                    } label: {
                        CommandRow(showingOriginal ? "Hide the original" : "Show the original",
                                   symbol: showingOriginal ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(PressStyle())
                    if showingOriginal {
                        Text(verbatim: entry.original)
                            .font(.mono(14, bold: false))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                    }
                }
                Hint("Only the words are translated. The date, the tags, the series and the state belong to the post itself and hold in every language.")

                SectionLabel("In \(languageName)")
                // Said before anything is written, not at the save that
                // would turn it away -- with what was written in it.
                if !entry.editable {
                    Hint(verbatim: entry.problem.map { String(localized: "This post cannot be edited here: \($0). At the desk, edit asks before losing it; here nobody could answer.") }
                         ?? String(localized: "This post cannot be edited here."))
                }
                Plate {
                    // Left alone while a save is on its way.
                    PaperEditor(text: $text, minHeight: 280, original: entry.text)
                        .disabled(saving || !entry.editable)
                }
                Plate {
                    Command("Preview", symbol: "eye") { previewing = true }
                }
                .gap(10)

                Button {
                    Task { await save(text) }
                } label: {
                    PrimaryLabel(label: saving ? "Saving…" : "Save the \(languageName) text", busy: saving)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(saving || !entry.editable || text == entry.text)
                .gap(22)
                if let problem {
                    ProblemLine(text: problem)
                    if changedOnBlog {
                        Plate {
                            Command("Load the post as the blog has it now", symbol: "arrow.clockwise", danger: true) {
                                Task { await takeAfresh() }
                            }
                            .disabled(saving)
                        }
                        .gap(10)
                        Hint("What is written here is replaced by the blog's text.")
                    }
                }
                if entry.written {
                    Plate {
                        Command("Take this language off the post", symbol: "minus.circle", danger: true) { confirmingRemoval = true }
                            .confirmationDialog("Take the \(languageName) text off '\(slug)'? The post then looks exactly as it did before the translation existed.",
                                                isPresented: $confirmingRemoval, titleVisibility: .visible) {
                                Button("Take it off", role: .destructive) { Task { await save("---\ntitle:\n---\n\n", takingOff: true) } }
                            }
                            .disabled(saving)
                    }
                    .gap(14)
                }

                if let saved {
                    SectionLabel(tookOff ? "Taken off" : "Saved")
                    Plate {
                        // What was done, not only to what: written, or taken off.
                        (tookOff ? Text("\(saved.slug): the \(languageName) text is taken off")
                                 : Text("\(saved.slug): the \(languageName) text"))
                            .font(.ui(15)).foregroundStyle(Theme.ink)
                        if let warnings = saved.warnings?.plain {
                            ForEach(warnings, id: \.self) { Text(verbatim: $0).font(.ui(13)).foregroundStyle(Theme.muted) }
                        }
                        Command("Back to the post", symbol: "arrow.left") { dismiss() }
                    }
                }
            } else if let problem {
                ProblemLine(text: problem)
                if let stranded {
                    Stranded(kept: stranded) {
                        if let blog = Blogs.shared.currentID { Unsaved.forget(for: blog, slug: slug, what: .language(lang)) }
                        Desk.shared.changed()
                    }
                }
            }
        }
        .overlay { if entry == nil && problem == nil { ProgressView() } }
        .navigationTitle(entry?.title ?? slug)
        .task { await load() }
        .onChange(of: text) { _, _ in keep() }
        .sheet(isPresented: $previewing) {
            // The translation's own title, or the post's while it has none;
            // the pictures are the post's, from beside its page on the blog.
            let parts = Preview.parts(of: text)
            PreviewSheet(title: parts.title.isEmpty ? (entry?.title ?? "") : parts.title, markdown: parts.body,
                         shown: Preview.shown(media: entry?.media ?? [], beside: entry?.preview ?? "/"), lang: lang)
        }
    }

    private func load() async {
        do {
            let answer: TranslationAnswer = try await Engine.shared.call(["translate", slug, "--lang", lang])
            entry = answer.post
            // The blog's words, or the ones written here and never saved --
            // over a language that can be written here at all.
            if answer.post.editable, let blog = Blogs.shared.currentID,
               let kept = Unsaved.kept(for: blog, slug: slug, what: .language(lang)), kept.text != answer.post.text {
                broughtBack = kept
                text = kept.text
            } else {
                broughtBack = nil
                text = answer.post.text
            }
            problem = nil
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }

    /// What is kept for this language while the post itself did not open.
    private var stranded: Unsaved? {
        _ = Desk.shared.changes
        return Blogs.shared.currentID.flatMap { Unsaved.kept(for: $0, slug: slug, what: .language(lang)) }
    }

    /// A text with no title and no words: saved, it takes the language
    /// off the post -- the engine's own rule, and the editor's hint.
    static func takesOff(_ text: String) -> Bool {
        let parts = Preview.parts(of: text)
        return parts.title.isEmpty && parts.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// At every letter; words that are the blog's again are nothing to keep.
    private func keep() {
        guard let entry, let blog = Blogs.shared.currentID else { return }
        if text == entry.text {
            Unsaved.forget(for: blog, slug: slug, what: .language(lang))
            broughtBack = nil
        } else {
            Unsaved.now(text, title: entry.title, over: entry.base, begun: broughtBack).keep(for: blog, slug: slug, what: .language(lang))
        }
        Desk.shared.changed()
    }

    private func takeTheBlogs() {
        broughtBack = nil
        text = entry?.text ?? ""
        if let blog = Blogs.shared.currentID { Unsaved.forget(for: blog, slug: slug, what: .language(lang)) }
    }

    /// The header gets the three lines of the delivery: which post, which
    /// version, which language.
    private func fileText(_ body: String) -> String {
        guard let entry else { return body }
        let lines = "edits: \(entry.slug)\nbase: \(entry.base)\nlang: \(lang)\n"
        if body.hasPrefix("---\n") { return "---\n" + lines + body.dropFirst(4) }
        return "---\n" + lines + "---\n\n" + body
    }

    private func save(_ body: String, takingOff: Bool = false) async {
        saving = true
        defer { saving = false }
        problem = nil
        changedOnBlog = false
        // What goes has code's quotes in its code.
        let file = DeliveryFile(name: "\(slug)-\(lang).md", data: Data(fileText(CodeQuotes.settled(body, over: entry?.text)).utf8))
        // Whose post it is and what the editor held, said before anything is waited for.
        let blog = Blogs.shared.currentID
        let going = text
        do {
            saved = try await Engine.shared.delivered([file], to: blog)
            // What was done, by what was sent: emptied words take the
            // language off whichever key sent them.
            tookOff = takingOff || Self.takesOff(body)
            // Saved, or taken off: what the editor held is not left to bring back.
            if let blog { Unsaved.forget(for: blog, slug: slug, what: .language(lang), saved: going) }
            broughtBack = nil
            Desk.shared.changed()
            await load()
            answered += 1
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
            if case EngineError.refused(let refusal) = error { changedOnBlog = refusal.error == "changed" }
            answered += 1
        }
    }

    /// The text as the blog has it now, in place of what is written here.
    private func takeAfresh() async {
        if let blog = Blogs.shared.currentID { Unsaved.forget(for: blog, slug: slug, what: .language(lang)) }
        Desk.shared.changed()
        changedOnBlog = false
        await load()
    }
}

#Preview {
    NavigationStack { TranslateView(slug: "venku", lang: "en") }
}
