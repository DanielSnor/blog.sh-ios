import SwiftUI

/// [l]: the post's words in another language the site publishes. What
/// `translate` opens in the editor, opened here: the translation's header
/// (its title, its address) and its text, with the original beside it to
/// translate from. The save goes back as a file saying which post, which
/// version and which language; an empty title and body take the language
/// off the post, as the editor's hint says.
struct TranslateView: View {
    let slug: String
    let lang: String
    @State private var entry: TranslationEntry?
    @State private var text = ""
    @State private var showingOriginal = true
    @State private var saving = false
    @State private var problem: String?
    @State private var saved: ActionAnswer?
    @State private var confirmingRemoval = false

    private var languageName: String { Locale.current.localizedString(forLanguageCode: lang) ?? lang }

    var body: some View {
        Form {
            if let entry {
                Section {
                    DisclosureGroup("The original", isExpanded: $showingOriginal) {
                        Text(entry.original)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text("Only the words are translated. The date, the tags, the series and the state belong to the post itself and hold in every language.")
                }
                Section("In \(languageName)") {
                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        .frame(minHeight: 280)
                }
                Section {
                    Button {
                        Task { await save(text) }
                    } label: {
                        if saving {
                            HStack { ProgressView(); Text("Saving…") }
                        } else {
                            Label("Save the \(languageName) text", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(saving || text == entry.text)
                    if entry.written {
                        Button("Take this language off the post", role: .destructive) { confirmingRemoval = true }
                            .disabled(saving)
                    }
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(.red)
                    }
                }
                if let saved {
                    Section("Saved") {
                        Text("\(saved.slug): the \(languageName) text")
                        if let warnings = saved.warnings, !warnings.isEmpty {
                            ForEach(warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            } else if let problem {
                Text(problem).foregroundStyle(.secondary)
            }
        }
        .overlay { if entry == nil && problem == nil { ProgressView() } }
        .navigationTitle(entry?.title ?? slug)
        .toolbarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("Take the \(languageName) text off '\(slug)'? The post then looks exactly as it did before the translation existed.",
                            isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Take it off", role: .destructive) { Task { await save("---\ntitle:\n---\n\n") } }
        }
    }

    private func load() async {
        do {
            let answer: TranslationAnswer = try await Engine.shared.call(["translate", slug, "--lang", lang])
            entry = answer.post
            text = answer.post.text
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    /// The header gets the three lines of the delivery: which post, which
    /// version, which language.
    private func fileText(_ body: String) -> String {
        guard let entry else { return body }
        let lines = "edits: \(entry.slug)\nbase: \(entry.base)\nlang: \(lang)\n"
        if body.hasPrefix("---\n") { return "---\n" + lines + body.dropFirst(4) }
        return "---\n" + lines + "---\n\n" + body
    }

    private func save(_ body: String) async {
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
            await load()
        } catch {
            problem = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { TranslateView(slug: "venku", lang: "en") }
}
