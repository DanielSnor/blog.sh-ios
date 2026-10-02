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
        Form {
            Section {
                DatePicker("Publish when?", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
            } footer: {
                if offered != nil {
                    Text("The time offered is the next free publishing slot.")
                }
            }
            if let problem {
                Section { Text(problem).foregroundStyle(.red) }
            }
        }
        .navigationTitle(scheduled ? "Reschedule" : "Schedule")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(scheduled ? "Reschedule" : "Schedule") { Task { await schedule() } }.disabled(busy)
            }
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
            problem = error.localizedDescription
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
        Form {
            Section {
                TextField("series", text: $series)
                TextField("part of series", text: $seriesPart).keyboardType(.numberPad)
                TextField("tags", text: $tags)
                Picker("type", selection: $type) {
                    ForEach(Self.types, id: \.self) { Text($0 == "-" ? "\(props.type) (from the content)" : $0).tag($0) }
                }
            }
            Section {
                Toggle("unlisted", isOn: $unlisted)
                Picker("lead image", selection: $hero) {
                    ForEach(Self.threeStates, id: \.self) { Text($0 == "default" ? "(the site's own)" : $0).tag($0) }
                }
                Picker("chapter list", selection: $toc) {
                    ForEach(Self.threeStates, id: \.self) { Text($0 == "default" ? "(the site's own)" : $0).tag($0) }
                }
            } footer: {
                Text("Properties are what the post IS, not what it says. The flags have a third state: whatever the site does.")
            }
            if let problem {
                Section { Text(problem).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Properties")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(busy || sets.isEmpty) }
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
            problem = error.localizedDescription
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
            if let problem {
                Text(problem).foregroundStyle(.red)
            }
            ForEach(addresses, id: \.value) { address in
                VStack(alignment: .leading) {
                    Text(address.value).font(.body.monospaced())
                    Text(address.kind == "former_slugs" ? "a former slug, redirects here" : "redirects here")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Drop", role: .destructive) { dropping = address }
                }
            }
        }
        .overlay {
            if addresses.isEmpty { ContentUnavailableView("This post has no old addresses.", systemImage: "link") }
        }
        .navigationTitle("Old links")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .confirmationDialog("Drop \(dropping?.value ?? "")? It no longer redirects anywhere.",
                            isPresented: Binding(get: { dropping != nil }, set: { if !$0 { dropping = nil } }), titleVisibility: .visible) {
            if let address = dropping {
                Button("Drop", role: .destructive) { Task { await drop(address) } }
            }
        }
    }

    private func drop(_ address: PropsAnswer.OldAddress) async {
        do {
            let answer: PropsAnswer = try await Engine.shared.call(["props", props.slug, "--drop-address", address.value])
            addresses = answer.addresses
            await done()
        } catch {
            problem = error.localizedDescription
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
            if let problem {
                Text(problem).foregroundStyle(.red)
            }
            Section {
                ForEach(versions) { version in
                    Button { restoring = version } label: {
                        Text(version.label)
                    }
                }
            } footer: {
                Text("Pictures are not versioned; only the text, the title, the tags and the type come back.")
            }
        }
        .overlay {
            if loaded && versions.isEmpty { ContentUnavailableView("No earlier versions yet", systemImage: "clock.arrow.circlepath") }
        }
        .navigationTitle("Earlier versions")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await load() }
        .confirmationDialog("Restore this version? The current text is kept as a version first.",
                            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), titleVisibility: .visible) {
            if let version = restoring {
                Button("Restore") { Task { await restore(version) } }
            }
        }
    }

    private func load() async {
        do {
            let answer: VersionsAnswer = try await Engine.shared.call(["props", slug, "--versions"])
            versions = answer.versions
            loaded = true
        } catch {
            problem = error.localizedDescription
        }
    }

    private func restore(_ version: VersionsAnswer.Version) async {
        do {
            let _: PropsAnswer = try await Engine.shared.call(["props", slug, "--restore-version", version.name, "--yes"])
            await done()
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}
