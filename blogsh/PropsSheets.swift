import SwiftUI

/// The schedule dialog: "publish when?", with the slot the engine would
/// offer already in the picker. `schedule <slug> --at <time> --json`.
struct ScheduleSheet: View {
    let slug: String
    let offered: String?
    let scheduled: Bool
    let done: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date = Date().addingTimeInterval(3600)
    @State private var problem: String?
    @State private var busy = false

    var body: some View {
        PaperScreen {
            ScreenHeader(title: scheduled ? String(localized: "Reschedule") : String(localized: "Schedule"))
            Plate {
                DatePicker(selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute]) {
                    Text("Publish when?").engineLabel().foregroundStyle(Theme.muted)
                }
                .padding(.vertical, -4)
            }
            .padding(.top, 14)
            if offered != nil {
                Hint("The time offered is the next free publishing slot.")
            }
            Button {
                Task { await schedule() }
            } label: {
                PrimaryLabel(label: scheduled ? "Reschedule" : "Schedule", busy: busy)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy)
            .padding(.top, 22)
            if let problem {
                ProblemLine(text: problem)
            }
        }
        .navigationTitle(scheduled ? "Reschedule" : "Schedule")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .onAppear {
            if let offered, let slot = ISO8601DateFormatter.engine.date(from: offered), slot > Date() {
                date = slot
            }
        }
    }

    private func schedule() async {
        busy = true
        defer { busy = false }
        do {
            let _: ActionAnswer = try await Engine.shared.call(["schedule", slug, "--at", ISO8601DateFormatter.engine.string(from: date)])
            await done()
            dismiss()
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}

/// The [e] screen: what the post IS. Each row is written only when it
/// changed, as one `--set key=value`; the words are the screen's own.
struct PropertiesForm: View {
    let props: PropsAnswer
    let done: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var series: String
    @State private var seriesPart: String
    @State private var tags: String
    @State private var type: String
    @State private var unlisted: Bool
    @State private var hero: String
    @State private var toc: String
    @State private var problem: String?
    @State private var busy = false

    static let types = ["-", "document", "video", "audio", "image", "chat", "quote", "link", "text"]
    static let threeStates = ["default", "yes", "no"]

    init(props: PropsAnswer, done: @escaping () async -> Void) {
        self.props = props
        self.done = done
        _series = State(initialValue: props.series ?? "")
        _seriesPart = State(initialValue: props.seriesPart ?? "")
        _tags = State(initialValue: props.tags.joined(separator: ", "))
        _type = State(initialValue: props.typeSet ?? "-")
        _unlisted = State(initialValue: props.unlisted)
        _hero = State(initialValue: props.hero)
        _toc = State(initialValue: props.toc)
    }

    var body: some View {
        PaperScreen {
            ScreenHeader(title: String(localized: "Properties"))
            Plate {
                FieldRow(label: "series", text: $series, labelWidth: 84)
                FieldRow(label: "part of series", text: $seriesPart, labelWidth: 84).keyboardType(.numberPad)
                FieldRow(label: "tags", text: $tags, labelWidth: 84)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .task { await TagStore.shared.loadIfNeeded() }
                TagSuggestions(text: $tags)
                ChoiceRow(label: "type", chosen: typeWord(type), selection: $type) {
                    ForEach(Self.types, id: \.self) { Text(verbatim: typeWord($0)).tag($0) }
                }
            }
            .padding(.top, 14)
            Plate {
                SwitchRow(label: "unlisted", isOn: $unlisted, property: true)
                ChoiceRow(label: "lead image", chosen: flagWord(hero), selection: $hero) {
                    ForEach(Self.threeStates, id: \.self) { Text(verbatim: flagWord($0)).tag($0) }
                }
                ChoiceRow(label: "chapter list", chosen: flagWord(toc), selection: $toc) {
                    ForEach(Self.threeStates, id: \.self) { Text(verbatim: flagWord($0)).tag($0) }
                }
            }
            .padding(.top, 10)
            Hint("Properties are what the post IS, not what it says. The flags have a third state: whatever the site does.")
            Button {
                Task { await save() }
            } label: {
                PrimaryLabel(label: "Save", busy: busy)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || sets.isEmpty)
            .padding(.top, 22)
            if let problem {
                ProblemLine(text: problem)
            }
        }
        .navigationTitle("Properties")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    /// A type as the menu says it: `-` is "let the content decide".
    private func typeWord(_ value: String) -> String {
        value == "-" ? String(localized: "\(props.type) (from the content)") : value
    }

    /// A flag as the menu says it: yes, no, or whatever the site does.
    private func flagWord(_ value: String) -> String {
        switch value {
        case "yes": String(localized: "flag.yes", defaultValue: "yes")
        case "no": String(localized: "flag.no", defaultValue: "no")
        default: String(localized: "(the site's own)")
        }
    }

    /// Only what changed, in the words `--set` takes.
    private var sets: [String] {
        var out: [String] = []
        let series = series.trimmingCharacters(in: .whitespaces)
        if series != (props.series ?? "") { out.append("series=\(series.isEmpty ? "-" : series)") }
        let part = seriesPart.trimmingCharacters(in: .whitespaces)
        if part != (props.seriesPart ?? "") { out.append("series_part=\(part.isEmpty ? "-" : part)") }
        let tags = tags.trimmingCharacters(in: .whitespaces)
        if tags != props.tags.joined(separator: ", ") { out.append("tags=\(tags.isEmpty ? "-" : tags)") }
        if type != (props.typeSet ?? "-") { out.append("type=\(type)") }
        if unlisted != props.unlisted { out.append("unlisted=\(unlisted ? "yes" : "no")") }
        if hero != (props.hero) { out.append("hero=\(hero)") }
        if toc != (props.toc) { out.append("toc=\(toc)") }
        return out
    }

    private func save() async {
        busy = true
        defer { busy = false }
        var args = ["props", props.slug]
        for set in sets { args += ["--set", set] }
        do {
            let _: PropsAnswer = try await Engine.shared.call(args)
            await done()
            dismiss()
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}

/// The [a] screen: the addresses the post used to answer at, and the one
/// way to drop one. `props <slug> --drop-address <address> --json`.
struct AddressesSheet: View {
    let props: PropsAnswer
    let done: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var addresses: [PropsAnswer.OldAddress]
    @State private var dropping: PropsAnswer.OldAddress?
    @State private var problem: String?

    init(props: PropsAnswer, done: @escaping () async -> Void) {
        self.props = props
        self.done = done
        _addresses = State(initialValue: props.addresses)
    }

    var body: some View {
        List {
            ScreenHeader(title: String(localized: "Old links"), count: addresses.isEmpty ? nil : addresses.count.formatted())
                .padding(.top, 2)
                .padding(.bottom, 6)
                .paperRow()
            if let problem {
                ProblemLine(text: problem).padding(.bottom, 10).paperRow()
            }
            ForEach(addresses, id: \.value) { address in
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: address.value).font(.mono(14, bold: false)).foregroundStyle(Theme.ink)
                    Text(address.kind == "former_slugs" ? "a former slug, redirects here" : "redirects here")
                        .font(.ui(13)).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 11)
                .confirmationDialog("Drop \(address.value)? It no longer redirects anywhere.",
                                    isPresented: Binding(get: { dropping?.value == address.value }, set: { if !$0 { dropping = nil } }),
                                    titleVisibility: .visible) {
                    Button("Drop", role: .destructive) { Task { await drop(address) } }
                }
                .paperRow()
                .swipeActions {
                    Button("Drop", role: .destructive) { dropping = address }
                }
            }
        }
        .paperList()
        .overlay {
            if addresses.isEmpty { EmptyNote(symbol: "link", title: "This post has no old addresses.", room: .part) }
        }
        .navigationTitle("Old links")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func drop(_ address: PropsAnswer.OldAddress) async {
        do {
            let answer: PropsAnswer = try await Engine.shared.call(["props", props.slug, "--drop-address", address.value])
            addresses = answer.addresses
            await done()
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}

/// The [v] screen: what the post said before one of its recent saves.
/// `--versions` lists them, `--restore-version <name> --yes` restores one;
/// the text it replaces is kept as a version first.
struct VersionsSheet: View {
    let slug: String
    let done: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [VersionsAnswer.Version] = []
    @State private var restoring: VersionsAnswer.Version?
    @State private var problem: String?
    @State private var loaded = false

    var body: some View {
        List {
            ScreenHeader(title: String(localized: "Earlier versions"), count: versions.isEmpty ? nil : versions.count.formatted())
                .padding(.top, 2)
                .padding(.bottom, 6)
                .paperRow()
            if let problem {
                ProblemLine(text: problem).padding(.bottom, 10).paperRow()
            }
            ForEach(versions) { version in
                Button { restoring = version } label: {
                    HStack(spacing: 10) {
                        Text(verbatim: version.label).font(.ui(15)).foregroundStyle(Theme.ink)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13))
                            .foregroundStyle(.tint)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .confirmationDialog("Restore this version? The current text is kept as a version first.",
                                    isPresented: Binding(get: { restoring?.id == version.id }, set: { if !$0 { restoring = nil } }),
                                    titleVisibility: .visible) {
                    Button("Restore") { Task { await restore(version) } }
                }
                .paperRow()
            }
            if !versions.isEmpty {
                Hint("Pictures are not versioned; only the text, the title, the tags and the type come back.")
                    .padding(.bottom, 10)
                    .paperRow(rule: false)
            }
        }
        .paperList()
        .overlay {
            if loaded && versions.isEmpty { EmptyNote(symbol: "clock.arrow.circlepath", title: "No earlier versions yet", room: .part) }
        }
        .navigationTitle("Earlier versions")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await load() }
    }

    private func load() async {
        do {
            let answer: VersionsAnswer = try await Engine.shared.call(["props", slug, "--versions"])
            versions = answer.versions
            loaded = true
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }

    private func restore(_ version: VersionsAnswer.Version) async {
        do {
            let _: PropsAnswer = try await Engine.shared.call(["props", slug, "--restore-version", version.name, "--yes"])
            await done()
            dismiss()
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}
