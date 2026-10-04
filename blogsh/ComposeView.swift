import SwiftUI
import PhotosUI

/// "New post": what /write/ offers, as a form -- a title, the text, the
/// tags, photographs each with its description -- sent the way the page
/// sends it: the pictures first, the markdown last, one delivery. The
/// post arrives as a draft with a preview; publishing is its properties'
/// decision, the way it is at the desk.
struct ComposeView: View {
    /// The receiver's ceiling on one delivery, as the blog last said it.
    @AppStorage("site.maxMb") private var maxMb = 24
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
        PaperScreen {
            ScreenHeader(title: String(localized: "New post"))
            Plate {
                TextField("", text: $title, prompt: Text("Title").foregroundStyle(Theme.muted))
                    .font(.ui(18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                PaperEditor(text: $text, minHeight: 200)
                    .focused($bodyFocused)
                FieldRow(label: "tags", text: $tags, prompt: String(localized: "Comma separated."))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .task { await TagStore.shared.loadIfNeeded() }
                TagSuggestions(text: $tags)
            }
            .padding(.top, 14)
            // Said as it is typed: the marks in the sentence are examples, not marks.
            Hint(verbatim: String(localized: "Markdown. A picture goes in as ![description](photo.jpg), a video as !![description](clip.mp4) -- the bare name, no path."))

            SectionLabel("Pictures and video")
            Plate {
                ForEach($shots) { $shot in
                    ShotCard(shot: $shot, inText: self.text.contains("(\(shot.name))")) {
                        insert(shot)
                    } remove: {
                        remove(shot)
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
            DeliveryNote(shots: shots, textBytes: text.utf8.count, maxMb: maxMb)

            Button {
                Task { await send() }
            } label: {
                PrimaryLabel(label: sending ? "Sending…" : "Send to the blog as a draft", busy: sending)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending || importing || (title.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || overweight)
            .padding(.top, 22)
            if let problem {
                ProblemLine(text: problem)
            }

            if let made {
                SectionLabel("Done")
                Plate {
                    Text("Draft written: \(made.slug)").font(.ui(15)).foregroundStyle(Theme.ink)
                    if let warnings = made.warnings {
                        ForEach(warnings, id: \.self) { Text(verbatim: $0).font(.ui(13)).foregroundStyle(Theme.muted) }
                    }
                    if let url = made.url, !url.isEmpty, let link = URL(string: url) {
                        Link(destination: link) { CommandRow("Open the preview", symbol: "safari") }
                            .buttonStyle(PressStyle())
                    }
                    NavigationLink { PropsView(slug: made.slug) } label: {
                        CommandRow("Its properties and the actions on it", symbol: "slider.horizontal.3", leads: true)
                    }
                    .buttonStyle(PressStyle())
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
        for item in items {
            guard let shot = await Media.shot(from: item, index: shots.count + 1, taken: shots.map(\.name)) else {
                problem = String(localized: "One picture could not be read.")
                continue
            }
            shots.append(shot)
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
        text = text.replacingOccurrences(of: #"\n*"# + shot.markPattern + #"\n*"#, with: "\n\n", options: .regularExpression)
    }

    private var overweight: Bool { Delivery.over(shots: shots, textBytes: text.utf8.count, maxMb: maxMb) }

    // MARK: - Sending

    private func send() async {
        sending = true
        defer { sending = false }
        problem = nil
        // The descriptions follow the marks already in the text.
        var marked = text
        for shot in shots {
            marked = marked.replacingOccurrences(of: shot.markPattern,
                                                 with: NSRegularExpression.escapedTemplate(for: shot.mark), options: .regularExpression)
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

/// One shot's card: what it looks like, its name as the text names it
/// and what it weighs, its description, and the way into the text.
struct ShotCard: View {
    @Binding var shot: Shot
    let inText: Bool
    let insert: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = UIImage(data: shot.kind == .video ? (shot.poster ?? Data()) : shot.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
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
            } else if shot.kind == .video {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
                    .frame(width: 64, height: 64)
                    .overlay(Image(systemName: "film").foregroundStyle(Theme.muted))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: shot.name).font(.mono(12, bold: false)).foregroundStyle(Theme.muted).lineLimit(1)
                    if shot.kind == .video {
                        Text("video").engineLabel(11).foregroundStyle(.tint)
                    }
                    Spacer(minLength: 4)
                    Text(verbatim: Delivery.size(shot.data.count)).font(.mono(11, bold: false)).foregroundStyle(Theme.muted)
                }
                TextField("", text: $shot.alt, prompt: Text("No description yet").foregroundStyle(Theme.muted))
                    .font(.ui(15))
                    .foregroundStyle(Theme.ink)
                HStack {
                    Button(action: insert) {
                        Text(inText ? "Used in the text" : "Insert into text").engineLabel(11)
                    }
                    .foregroundStyle(inText ? AnyShapeStyle(Theme.muted) : AnyShapeStyle(.tint))
                    .disabled(inText)
                    Spacer()
                    Button(action: remove) { Text("Remove").engineLabel(11) }
                        .foregroundStyle(Theme.danger)
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}


#Preview {
    NavigationStack { ComposeView() }
}
