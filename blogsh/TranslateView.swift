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
                Plate {
                    PaperEditor(text: $text, minHeight: 280)
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
                .disabled(saving || text == entry.text)
                .gap(22)
                if let problem {
                    ProblemLine(text: problem)
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
            // The blog's words, or the ones written here and never saved.
            if let blog = Blogs.shared.currentID,
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

    /// At every letter; words that are the blog's again are nothing to keep.
    private func keep() {
        guard let entry, let blog = Blogs.shared.currentID else { return }
        if text == entry.text {
            Unsaved.forget(for: blog, slug: slug, what: .language(lang))
        } else {
            Unsaved(text: text, base: entry.base, at: .now).keep(for: blog, slug: slug, what: .language(lang))
        }
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
        let file = DeliveryFile(name: "\(slug)-\(lang).md", data: Data(fileText(body).utf8))
        do {
            let answers = try await Engine.shared.deliver([file])
            let decoder = JSONDecoder()
            for answer in answers {
                if let refusal = try? decoder.decode(Refusal.self, from: answer), refusal.ok == false {
                    throw EngineError.refused(refusal)
                }
            }
            guard let last = answers.last else { throw EngineError.unreadable("") }
            saved = try decoder.decode(ActionAnswer.self, from: last)
            tookOff = takingOff
            // Saved, or taken off: nothing is left to bring back.
            if let blog = Blogs.shared.currentID { Unsaved.forget(for: blog, slug: slug, what: .language(lang)) }
            broughtBack = nil
            await load()
            answered += 1
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
            answered += 1
        }
    }
}

#Preview {
    NavigationStack { TranslateView(slug: "venku", lang: "en") }
}
