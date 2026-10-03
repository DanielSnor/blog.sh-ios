import SwiftUI

/// One post's properties screen, as `props <slug> --json` hands it out:
/// the rows the terminal's frame shows, under the labels it uses, and
/// below them the keys the screen offers this post -- as buttons, in the
/// order of the keys row. Each asks what the screen asks, then calls the
/// command the key calls, then reads the screen again.
struct PropsView: View {
    @State var slug: String
    @Environment(\.dismiss) private var dismiss
    @State private var props: PropsAnswer?
    @State private var problem: String?
    @State private var busy = false

    // What is being asked, one at a time, the way one keypress asks.
    @State private var confirming: PostAction?
    @State private var scheduling = false
    @State private var editingProperties = false
    @State private var renaming = false
    @State private var newSlug = ""
    @State private var showingAddresses = false
    @State private var showingVersions = false
    @State private var askingRebuild = false
    @State private var notice: Notice?
    @State private var announceAnyway = false

    struct Notice: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        PaperScreen {
            if let problem {
                ProblemLine(text: problem)
            }
            if let props {
                PostHeading(title: props.title,
                            detail: props.state == .draft ? String(localized: "draft -- not on the site, preview only")
                                                          : String(props.address.trimmingPrefix("/")))
                rows(props).padding(.top, 16)
                if !props.url.isEmpty, let url = URL(string: props.url) {
                    Plate {
                        Link(destination: url) {
                            CommandRow(props.state == .draft ? "Show the preview on the web" : "Show on the web", symbol: "safari")
                        }
                        .buttonStyle(PressStyle())
                    }
                    .padding(.top, 10)
                }
                SectionLabel("Actions")
                Plate {
                    ForEach(keys(props).filter { $0 != .delete }, id: \.self) { action in
                        Command(text: Text(verbatim: actionLabel(action, props)), symbol: actionSymbol(action),
                                leads: Self.opensAScreen.contains(action)) {
                            tapped(action)
                        }
                    }
                }
                // What cannot be taken back sits apart, and last -- as [x] is the
                // last key of the row.
                if props.actions.contains(.delete) {
                    Plate {
                        Command(text: Text(verbatim: actionLabel(.delete, props)), symbol: actionSymbol(.delete), danger: true) {
                            tapped(.delete)
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .overlay {
            if props == nil && problem == nil { ProgressView() }
        }
        .disabled(busy)
        .navigationTitle(slug)
        .toolbarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            if let action = confirming {
                Button(confirmButton(action), role: action == .delete || action == .unpublish ? .destructive : nil) {
                    Task { await perform(action) }
                }
            }
        } message: {
            if let text = confirmMessage { Text(text) }
        }
        .sheet(isPresented: $scheduling) {
            NavigationStack { ScheduleSheet(slug: slug, offered: props?.slot, scheduled: props?.scheduled == true) { await load() } }
        }
        .sheet(isPresented: $editingProperties) {
            if let props {
                NavigationStack { PropertiesForm(props: props) { await afterWrite(rebuildAsk: true) } }
            }
        }
        .sheet(isPresented: $showingAddresses) {
            if let props {
                NavigationStack { AddressesSheet(props: props) { await afterWrite(rebuildAsk: true) } }
            }
        }
        .sheet(isPresented: $showingVersions) {
            NavigationStack { VersionsSheet(slug: slug) { await load() } }
        }
        .alert("Rename slug", isPresented: $renaming) {
            TextField("New slug", text: $newSlug)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Rename") { Task { await rename() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(props?.state == .draft
                 ? "A draft has no public address yet; only its preview address changes."
                 : "The old address keeps answering: it redirects to the new one.")
        }
        .alert("Rebuild and deploy the site now?", isPresented: $askingRebuild) {
            Button("Rebuild") { Task { await rebuild() } }
            Button("Not now", role: .cancel) {}
        }
        .alert(item: $notice) { notice in
            if announceAnyway {
                Alert(title: Text("Announce"), message: Text(notice.text),
                      primaryButton: .default(Text("Announce anyway")) { Task { await announce(force: true) } },
                      secondaryButton: .cancel())
            } else {
                Alert(title: Text(""), message: Text(notice.text), dismissButton: .default(Text("OK")))
            }
        }
    }

    // MARK: - The screen

    /// The keys that open a screen of their own rather than ask and act.
    private static let opensAScreen: Set<PostAction> = [.schedule, .properties, .addresses, .versions]

    /// The keys the screen offers this post, in the order the terminal's keys
    /// row has them: [p] [s] [n] [u] [t] [c] [e] [r] [a] [v] [x].
    private static let keyOrder: [PostAction] = [.publish, .schedule, .unschedule, .unpublish, .announce, .pin,
                                                  .properties, .rename, .addresses, .versions, .delete]

    private func keys(_ props: PropsAnswer) -> [PostAction] {
        Self.keyOrder.filter(props.actions.contains)
    }

    /// The rows of the terminal's frame, under the labels it uses.
    private func rows(_ props: PropsAnswer) -> some View {
        Plate {
            if props.state == .draft {
                InfoRow(label: "preview", value: props.url, mono: true)
                if props.scheduled, let date = props.date {
                    InfoRow(label: "scheduled", value: humanDate(date))
                }
            } else if let date = props.date {
                InfoRow(label: "state", value: String(localized: "published, \(humanDate(date))"))
            }
            InfoRow(label: "type", value: props.type)
            InfoRow(label: "tags", value: props.tags.joined(separator: ", "))
            InfoRow(label: "series", value: seriesLabel(props))
            InfoRow(label: "pinned", value: props.pinned ? String(localized: "yes -- held at the top of the front page") : nil)
            InfoRow(label: "unlisted", value: props.unlisted ? String(localized: "yes -- reachable by its address, in no listing, feed, sitemap or search") : nil)
            InfoRow(label: "languages", value: languagesLabel(props))
            InfoRow(label: "announced", value: announcedLabel(props))
            InfoRow(label: "old links", value: props.addresses.isEmpty ? nil : String(localized: "\(props.addresses.count) address(es) still redirect here"))
        }
    }

    // MARK: - The keys

    private func tapped(_ action: PostAction) {
        switch action {
        case .publish, .unschedule, .unpublish, .announce, .delete:
            confirming = action
        case .schedule:
            scheduling = true
        case .pin:
            Task { await pin() }
        case .properties:
            editingProperties = true
        case .rename:
            newSlug = slug
            renaming = true
        case .addresses:
            showingAddresses = true
        case .versions:
            showingVersions = true
        }
    }

    private var confirmTitle: String {
        guard let action = confirming else { return "" }
        switch action {
        case .publish: return String(localized: "Publish '\(slug)'?")
        case .unschedule: return String(localized: "Cancel the schedule of '\(slug)'?")
        case .unpublish: return String(localized: "Really move '\(slug)' back to draft?")
        case .announce: return String(localized: "Announce '\(slug)'?")
        case .delete: return String(localized: "Really delete '\(slug)'?")
        default: return ""
        }
    }

    private var confirmMessage: String? {
        guard let action = confirming, let props else { return nil }
        switch action {
        case .publish where props.network != nil && !props.unlisted:
            return String(localized: "With a network configured it announces too, which nothing takes back.")
        case .unpublish:
            return String(localized: "Its announcement is deleted too; the post keeps its text as a draft.")
        case .delete:
            return props.announced != nil
                ? String(localized: "The post goes to the trash and can be restored; its announcement goes with it and cannot.")
                : String(localized: "The post goes to the trash and can be restored.")
        case .unschedule:
            return String(localized: "The post stays a draft, with the date it had before the plan.")
        default:
            return nil
        }
    }

    private func confirmButton(_ action: PostAction) -> String {
        switch action {
        case .publish: String(localized: "Publish")
        case .unschedule: String(localized: "Cancel the schedule")
        case .unpublish: String(localized: "Unpublish")
        case .announce: String(localized: "Announce")
        case .delete: String(localized: "Delete")
        default: String(localized: "OK")
        }
    }

    private func perform(_ action: PostAction) async {
        switch action {
        case .publish:
            if await run(["publish", slug, "--yes"]) != nil { await load() }
        case .unschedule:
            if await run(["schedule", slug, "--cancel"]) != nil { await load() }
        case .unpublish:
            if await run(["unpublish", slug, "--yes"]) != nil { await load() }
        case .announce:
            await announce(force: false)
        case .delete:
            if let answer = await run(["delete", slug, "--yes"]) {
                notice = Notice(text: String(localized: "Deleted (in trash, restore from Trash): \(answer.trash ?? "")"))
                askingRebuild = true
            }
        default:
            break
        }
    }

    private func announce(force: Bool) async {
        announceAnyway = false
        var args = [props?.network == "bluesky" ? "bluesky" : "toot", slug]
        if force { args.append("--force") }
        do {
            busy = true
            defer { busy = false }
            let answer: ActionAnswer = try await Engine.shared.call(args)
            notice = Notice(text: String(localized: "Announced: \(answer.url ?? "")"))
            await load()
        } catch EngineError.refused(let refusal) where refusal.error == "outside_window" {
            announceAnyway = true
            notice = Notice(text: refusal.message)
        } catch {
            notice = Notice(text: error.localizedDescription)
        }
    }

    private func pin() async {
        guard let props else { return }
        await write(["props", slug, "--set", "pinned=\(props.pinned ? "no" : "yes")"], rebuildAsk: true)
    }

    private func rename() async {
        let wanted = newSlug.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty, wanted != slug else { return }
        if let answer = await writeProps(["props", slug, "--rename", wanted, "--yes"]) {
            let wasDraft = props?.state == .draft
            slug = answer.slug
            props = answer
            if !wasDraft { askingRebuild = true }
        }
    }

    private func rebuild() async {
        busy = true
        defer { busy = false }
        do {
            let answer: RebuildAnswer = try await Engine.shared.call(["rebuild"])
            notice = Notice(text: answer.deploy == "done" ? String(localized: "Rebuilt and deployed.") : String(localized: "Rebuilt; the deploy is owed to the next scheduled run."))
        } catch {
            notice = Notice(text: error.localizedDescription)
        }
    }

    /// Runs an action and hands back its answer, or shows why it was refused.
    private func run(_ args: [String]) async -> ActionAnswer? {
        busy = true
        defer { busy = false }
        do {
            let answer: ActionAnswer = try await Engine.shared.call(args)
            if let warnings = answer.warnings, !warnings.isEmpty {
                notice = Notice(text: warnings.joined(separator: "\n"))
            }
            return answer
        } catch {
            notice = Notice(text: error.localizedDescription)
            return nil
        }
    }

    /// A write that answers with the screen itself.
    private func writeProps(_ args: [String]) async -> PropsAnswer? {
        busy = true
        defer { busy = false }
        do {
            let answer: PropsAnswer = try await Engine.shared.call(args)
            if let warnings = answer.warnings, !warnings.isEmpty {
                notice = Notice(text: warnings.joined(separator: "\n"))
            }
            return answer
        } catch {
            notice = Notice(text: error.localizedDescription)
            return nil
        }
    }

    private func write(_ args: [String], rebuildAsk: Bool) async {
        if let answer = await writeProps(args) {
            props = answer
            if rebuildAsk { askingRebuild = true }
        }
    }

    private func afterWrite(rebuildAsk: Bool) async {
        await load()
        if rebuildAsk { askingRebuild = true }
    }

    private func load() async {
        do {
            props = try await Engine.shared.call(["props", slug])
            problem = nil
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }

    // MARK: - Words

    private func humanDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.engine.date(from: iso) else { return iso }
        return date.formatted(.dateTime.year().month().day().hour().minute().timeZone())
    }

    private func seriesLabel(_ props: PropsAnswer) -> String? {
        guard let series = props.series else { return nil }
        guard let part = props.seriesPart else { return series }
        return String(localized: "\(series), part \(part)")
    }

    private func languagesLabel(_ props: PropsAnswer) -> String? {
        guard !props.languages.others.isEmpty else { return nil }
        let marks = ["written": "✅", "started": "◐", "none": "·"]
        let others = props.languages.others.sorted { $0.key < $1.key }
            .map { "\(marks[$0.value] ?? "·") \($0.key)" }
        return (["✅ \(props.languages.own)"] + others).joined(separator: "  ")
    }

    private func announcedLabel(_ props: PropsAnswer) -> String {
        if let url = props.announced { return url }
        switch props.announces {
        case .announced: return props.announced ?? ""
        case .onPublish: return String(localized: "not yet -- goes out when the post publishes")
        case .nowhere: return String(localized: "never -- this site announces nowhere")
        case .neverUnlisted: return String(localized: "never -- an unlisted post is not announced")
        case .noSecret: return String(localized: "never, as things stand -- the network's token is empty")
        case .notAnnounced: return String(localized: "not announced")
        }
    }

    private func actionLabel(_ action: PostAction, _ props: PropsAnswer) -> String {
        switch action {
        case .publish: props.scheduled ? String(localized: "publish now") : String(localized: "publish")
        case .schedule: props.scheduled ? String(localized: "reschedule") : String(localized: "schedule")
        case .unschedule: String(localized: "cancel the schedule")
        case .unpublish: String(localized: "unpublish")
        case .announce: String(localized: "announce (\(props.network == "bluesky" ? "Bluesky" : "Mastodon"))")
        case .pin: props.pinned ? String(localized: "unpin") : String(localized: "pin")
        case .properties: String(localized: "properties")
        case .rename: String(localized: "rename slug")
        case .addresses: String(localized: "old links")
        case .versions: String(localized: "earlier versions")
        case .delete: String(localized: "delete")
        }
    }

    private func actionSymbol(_ action: PostAction) -> String {
        switch action {
        case .publish: "paperplane"
        case .schedule: "calendar.badge.clock"
        case .unschedule: "calendar.badge.minus"
        case .unpublish: "arrow.uturn.backward"
        case .announce: "megaphone"
        case .pin: "pin"
        case .properties: "slider.horizontal.3"
        case .rename: "pencil.line"
        case .addresses: "link"
        case .versions: "clock.arrow.circlepath"
        case .delete: "trash"
        }
    }
}

#Preview {
    NavigationStack { PropsView(slug: "venku") }
}
