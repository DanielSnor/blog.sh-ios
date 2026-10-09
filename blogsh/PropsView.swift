import SwiftUI

/// One post's properties screen, as `props <slug> --json` hands it out:
/// the rows the terminal's frame shows, under the labels it uses, and
/// below them the keys the screen offers this post -- as buttons, in the
/// order of the keys row. Each asks what the screen asks, then calls the
/// command the key calls, then reads the screen again.
struct PropsView: View {
    /// The blog this screen was opened for. An answer can come after
    /// another blog has been opened; what follows from it -- a build owed,
    /// a build paid -- is this blog's all the same.
    @State private var home = Blogs.shared.currentID
    @State var slug: String
    /// Said to the screen this one was opened from, once the post is
    /// deleted: that screen is about the same post, and leaves with it.
    var gone: (() -> Void)?
    /// Told what the post is now, when it was renamed here: the screen
    /// under this one was opened with the name it had before.
    var renamed: ((PropsAnswer) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var props: PropsAnswer?
    @State private var problem: String?
    @State private var busy = false
    /// What the screen is doing while it cannot be touched.
    @State private var doing: Text?

    // What is being asked, one at a time, the way one keypress asks.
    @State private var confirming: PostAction?
    @State private var scheduling = false
    @State private var editingProperties = false
    @State private var renaming = false
    @State private var newSlug = ""
    @State private var showingAddresses = false
    @State private var showingVersions = false
    /// What the screen says after an action -- one thing, its question in it.
    @State private var said: Said?

    var body: some View {
        PaperScreen(title: props?.title ?? slug) {
            if let problem {
                ProblemLine(text: problem)
            }
            if let props {
                // Where the post is, under its title in the bar: its address, or that it has none yet.
                PostSlug(text: props.state == .draft ? String(localized: "draft -- not on the site, preview only")
                                                    : String(props.address.trimmingPrefix("/")))
                rows(props).gap(12)
                if !props.url.isEmpty, let url = URL(string: props.url) {
                    Plate {
                        Link(destination: url) {
                            CommandRow(props.state == .draft ? "Show the preview on the web" : "Show on the web", symbol: "safari")
                        }
                        .buttonStyle(PressStyle())
                    }
                    .gap(10)
                }
                SectionLabel("Actions")
                Plate {
                    ForEach(keys(props).filter { $0 != .delete }, id: \.self) { action in
                        Command(text: Text(verbatim: actionLabel(action, props)), symbol: actionSymbol(action),
                                leads: Self.opensAScreen.contains(action)) {
                            tapped(action)
                        }
                        .modifier(asked(action))
                    }
                }
                // What cannot be taken back sits apart, and last -- as [x] is the
                // last key of the row.
                if props.actions.contains(.delete) {
                    Plate {
                        Command(text: Text(verbatim: actionLabel(.delete, props)), symbol: actionSymbol(.delete), danger: true) {
                            tapped(.delete)
                        }
                        .modifier(asked(.delete))
                    }
                    .gap(10)
                }
            }
        }
        .overlay {
            if props == nil && problem == nil { ProgressView() }
        }
        // A build holds the lock most of these keys need: while one runs, they wait.
        .disabled(busy || Herald.shared.isBuilding)
        .doing(doing)
        .navigationTitle(slug)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if let link = props.flatMap({ PostLink($0) }) {
                ToolbarItem(placement: .topBarTrailing) { ShareKey(link: link) }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $scheduling) {
            NavigationStack { ScheduleSheet(slug: slug, offered: props?.slot, current: props?.scheduled == true ? props?.date : nil,
                                            scheduled: props?.scheduled == true) { await scheduled() } }
        }
        .sheet(isPresented: $editingProperties) {
            if let props {
                NavigationStack { PropertiesForm(props: props) { await afterWrite(saying: String(localized: "Saved")) } }
            }
        }
        .sheet(isPresented: $showingAddresses) {
            if let props {
                NavigationStack { AddressesSheet(props: props) { await afterWrite() } }
            }
        }
        .sheet(isPresented: $showingVersions) {
            NavigationStack { VersionsSheet(slug: slug) { await afterWrite(saying: String(localized: "Restored: \(slug)")) } }
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
        .says($said)
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
            // The whole title: the bar has one line for it.
            InfoRow(label: "Title", value: props.title)
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

    /// What a key asks before it acts, asked over the key itself -- not at
    /// the head of the screen, a hand's width from where the finger is.
    private struct Asked: ViewModifier {
        let action: PostAction
        @Binding var confirming: PostAction?
        let title: String
        let message: String?
        let button: String
        let perform: () async -> Void

        func body(content: Content) -> some View {
            content.confirmationDialog(title, isPresented: Binding(get: { confirming == action }, set: { if !$0 { confirming = nil } }),
                                       titleVisibility: .visible) {
                Button(button, role: action == .delete || action == .unpublish ? .destructive : nil) {
                    Task { await perform() }
                }
            } message: {
                if let message { Text(verbatim: message) }
            }
        }
    }

    private func asked(_ action: PostAction) -> Asked {
        Asked(action: action, confirming: $confirming, title: confirmTitle, message: confirmMessage,
              button: confirmButton(action)) { await perform(action) }
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
            await publish(anyway: false)
        case .unschedule:
            if let answer = await run(["schedule", slug, "--cancel"]) {
                await load()
                tell(answer.warnings, or: String(localized: "The schedule is cancelled; the post is a draft again."))
            }
        case .unpublish:
            if let answer = await run(["unpublish", slug, "--yes"]) {
                // Taking a post off the site builds the site.
                Herald.shared.settled(for: home)
                await load()
                tell(answer.warnings, or: String(localized: "Unpublished; the post is a draft again."))
            }
        case .announce:
            await announce(force: false)
        case .delete:
            if await run(["delete", slug, "--yes"]) != nil {
                // The post is out of this screen's reach now. Said once, and
                // the screen is left: its keys would act on a post that is
                // not there. The site is brought up to date by itself.
                Herald.shared.owe(for: home)
                said = Said(title: String(localized: "Deleted"),
                            text: String(localized: "The post is in the trash and can be restored from there."),
                            after: { leave() })
            }
        default:
            break
        }
    }

    /// [p]. On a site of more than one language the engine refuses a post
    /// without words in one of them; the refusal is asked as a question,
    /// and the answer is the flag the terminal would have been given.
    private func publish(anyway: Bool) async {
        var args = ["publish", slug, "--yes"]
        if anyway { args.append("--allow-partial") }
        let ask = Said.Ask(button: String(localized: "Publish anyway")) { await publish(anyway: true) }
        if let answer = await run(args, anyway: anyway ? nil : ask) {
            // Publishing builds the whole site: nothing is owed after it.
            Herald.shared.settled(for: home)
            await load()
            tell(answer.warnings, or: String(localized: "Published: \(answer.url ?? slug)"))
        }
    }

    /// Away from a post that is no longer there -- this screen, and the one before it when that is the post's too.
    private func leave() {
        gone?()
        dismiss()
    }

    /// The engine's own lines about what it did, when it had any -- they
    /// are worth an answer. Otherwise the plain fact that it was done,
    /// said in passing.
    private func tell(_ lines: [String]?, or done: String? = nil) {
        if let lines = lines?.plain, !lines.isEmpty {
            said = Said(text: lines.joined(separator: "\n"))
        } else if let done {
            Herald.shared.say(done)
        }
    }

    /// The schedule dialog closed on a plan: when the post goes out now.
    private func scheduled() async {
        await load()
        guard let props, props.scheduled, let date = props.date.flatMap({ ISO8601DateFormatter.engine.date(from: $0) }) else { return }
        Herald.shared.say(String(localized: "Scheduled: goes out \(date.spoken)."))
    }

    private func announce(force: Bool) async {
        var args = [props?.network == "bluesky" ? "bluesky" : "toot", slug]
        if force { args.append("--force") }
        do {
            busy = true
            doing = Doing.word(args)
            defer { busy = false; doing = nil }
            let answer: ActionAnswer = try await Engine.shared.call(args)
            await load()
            said = Said(text: String(localized: "Announced: \(answer.url ?? "")"))
        } catch EngineError.refused(let refusal) where refusal.error == "outside_window" {
            said = Said(title: String(localized: "Announce"), text: refusal.message,
                        ask: Said.Ask(button: String(localized: "Announce anyway")) { await announce(force: true) })
        } catch {
            said = Said(text: error.localizedDescription)
        }
    }

    private func pin() async {
        guard let props else { return }
        await write(["props", slug, "--set", "pinned=\(props.pinned ? "no" : "yes")"], owed: true)
    }

    private func rename() async {
        let wanted = newSlug.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty, wanted != slug else { return }
        let blog = Blogs.shared.currentID
        let old = slug
        if let answer = await writeProps(["props", slug, "--rename", wanted, "--yes"]) {
            let wasDraft = props?.state == .draft
            // What was written for the post and not saved follows it to its new name.
            if let blog {
                Unsaved.move(for: blog, from: old, to: answer.slug)
                Desk.shared.changed()
            }
            slug = answer.slug
            props = answer
            renamed?(answer)
            // A draft's own preview follows it by itself; a published post's pages are owed a build.
            if !wasDraft { Herald.shared.owe(for: home) }
            tell(answer.warnings)
        }
    }

    /// Runs an action and hands back its answer, or says why it was
    /// refused. `anyway`: what to offer when the refusal is the one a
    /// second word overrides -- a post not written in every language.
    private func run(_ args: [String], anyway: Said.Ask? = nil) async -> ActionAnswer? {
        busy = true
        doing = Doing.word(args)
        defer { busy = false; doing = nil }
        do {
            return try await Engine.shared.call(args)
        } catch EngineError.refused(let refusal) where refusal.error == Partial.code && anyway != nil {
            said = Said(text: Partial.words, ask: anyway)
            return nil
        } catch {
            said = Said(text: error.localizedDescription)
            return nil
        }
    }

    /// A write that answers with the screen itself.
    private func writeProps(_ args: [String]) async -> PropsAnswer? {
        busy = true
        doing = Doing.word(args)
        defer { busy = false; doing = nil }
        do {
            return try await Engine.shared.call(args)
        } catch {
            said = Said(text: error.localizedDescription)
            return nil
        }
    }

    private func write(_ args: [String], owed: Bool) async {
        if let answer = await writeProps(args) {
            props = answer
            if owed { Herald.shared.owe(for: home) }
            tell(answer.warnings)
        }
    }

    /// A sheet wrote something the site does not show yet.
    private func afterWrite(saying done: String? = nil) async {
        await load()
        Herald.shared.owe(for: home)
        if let done { Herald.shared.say(done) }
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
