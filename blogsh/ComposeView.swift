import SwiftUI
import PhotosUI

/// "New post": what /write/ offers, as a form -- a title, the text, the
/// tags, photographs each with its description -- sent the way the page
/// sends it: the pictures first, the markdown last, one delivery. The
/// post arrives as a draft with a preview; publishing is its properties'
/// decision, the way it is at the desk.
struct ComposeView: View {
    let maxMb: Int
    @State private var title = ""
    @State private var tags = ""
    @State private var text = ""
    @State private var shots: [Shot] = []
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var sending = false
    @State private var problem: String?
    @State private var made: ActionAnswer?
    @FocusState private var bodyFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                TextEditor(text: $text)
                    .frame(minHeight: 180)
                    .focused($bodyFocused)
                TextField("Tags, separated by commas", text: $tags)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .task { await TagStore.shared.loadIfNeeded() }
                TagSuggestions(text: $tags)
            } footer: {
                Text("Markdown. A picture goes in as a paragraph of its own: insert it from its card below.")
            }

            Section {
                ForEach($shots) { $shot in
                    ShotCard(shot: $shot, inText: self.text.contains("(\(shot.name))")) {
                        insert(shot)
                    } remove: {
                        remove(shot)
                    }
                }
                PhotosPicker(selection: $picked, matching: .images) {
                    Label(importing ? "Reading…" : "Add pictures", systemImage: "photo.on.rectangle")
                }
                .disabled(importing)
            } header: {
                Text("Pictures")
            } footer: {
                Text(weight)
            }

            Section {
                Button {
                    Task { await send() }
                } label: {
                    if sending {
                        HStack { ProgressView(); Text("Sending…") }
                    } else {
                        Label("Send to the blog as a draft", systemImage: "paperplane")
                    }
                }
                .disabled(sending || importing || (title.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || overweight)
            } footer: {
                if let problem {
                    Text(problem).foregroundStyle(.red)
                }
            }

            if let made {
                Section("Done") {
                    Text("Draft written: \(made.slug)")
                    if let url = made.url, !url.isEmpty, let link = URL(string: url) {
                        Link("Open the preview", destination: link)
                    }
                    if let warnings = made.warnings, !warnings.isEmpty {
                        ForEach(warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                    NavigationLink("Its properties and the actions on it") { PropsView(slug: made.slug) }
                }
            }
        }
        .navigationTitle("New post")
        .onChange(of: picked) { _, items in
            Task { await load(items) }
        }
    }

    // MARK: - Pictures

    private func load(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        importing = true
        defer { importing = false; picked = [] }
        var taken = shots.map(\.name)
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            guard let shrunk = Pictures.shrink(data) else {
                problem = String(localized: "One picture could not be read.")
                continue
            }
            let wanted = Pictures.safeName(item.itemIdentifier, index: shots.count + index + 1)
            let name = Pictures.freeName(wanted, taken: taken)
            taken.append(name)
            shots.append(Shot(name: name, data: shrunk.data, width: shrunk.width, height: shrunk.height))
        }
    }

    /// A blank line on each side: the blog renders a picture only as a
    /// paragraph of its own.
    private func insert(_ shot: Shot) {
        var kept = text
        while kept.hasSuffix("\n") { kept.removeLast() }
        text = kept.isEmpty ? shot.mark + "\n" : kept + "\n\n" + shot.mark + "\n"
    }

    private func remove(_ shot: Shot) {
        shots.removeAll { $0.id == shot.id }
        text = text.replacingOccurrences(of: #"\n*!\[[^\]]*\]\(\#(NSRegularExpression.escapedPattern(for: shot.name))\)\n*"#,
                                         with: "\n\n", options: .regularExpression)
    }

    private var encodedBytes: Int {
        shots.reduce(0) { $0 + encodedSize($1.data.count) } + encodedSize(text.utf8.count + 200)
    }

    private var overweight: Bool { encodedBytes > maxMb * 1_048_576 }

    private var weight: String {
        let mb = Double(encodedBytes) / 1_048_576
        return overweight
            ? String(localized: "\(mb, specifier: "%.1f") MB on the wire — over the blog's \(maxMb) MB limit; take a picture out.")
            : String(localized: "\(mb, specifier: "%.1f") MB of \(maxMb) MB the blog takes in one delivery.")
    }

    // MARK: - Sending

    private func send() async {
        sending = true
        defer { sending = false }
        problem = nil
        // The descriptions follow the marks already in the text.
        var marked = text
        for shot in shots {
            marked = marked.replacingOccurrences(of: #"!\[[^\]]*\]\(\#(NSRegularExpression.escapedPattern(for: shot.name))\)"#,
                                             with: shot.mark, options: .regularExpression)
        }
        let markdown = Markdown.file(title: title, tags: tags, body: marked)
        var files = shots.map { DeliveryFile(name: $0.name, data: $0.data) }
        files.append(DeliveryFile(name: Markdown.fileName(title: title, body: text), data: Data(markdown.utf8)))
        do {
            let answers = try await Engine.shared.deliver(files)
            let decoder = JSONDecoder()
            for answer in answers {
                if let refusal = try? decoder.decode(Refusal.self, from: answer), refusal.ok == false {
                    throw EngineError.refused(refusal)
                }
            }
            guard let last = answers.last else { throw EngineError.unreadable("") }
            made = try decoder.decode(ActionAnswer.self, from: last)
            // The form is the next post's now.
            title = ""; tags = ""; text = ""; shots = []
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}

/// One picture's card: a thumbnail, its description, and the way into the text.
struct ShotCard: View {
    @Binding var shot: Shot
    let inText: Bool
    let insert: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = UIImage(data: shot.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(shot.name).font(.caption.monospaced()).foregroundStyle(.secondary)
                TextField("Description", text: $shot.alt)
                HStack {
                    Button(inText ? "In the text" : "Insert into the text", action: insert)
                        .disabled(inText)
                    Spacer()
                    Button("Remove", role: .destructive, action: remove)
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { ComposeView(maxMb: 24) }
}
