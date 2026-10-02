import SwiftUI

/// One post's properties screen, as `props <slug> --json` hands it out:
/// the rows the terminal's frame shows, under the labels it uses, and
/// below them the keys the screen would offer this post -- named, not yet
/// wired. The actions are the next milestone; the screen is this one.
struct PropsView: View {
    let slug: String
    @State private var props: PropsAnswer?
    @State private var problem: String?

    var body: some View {
        List {
            if let problem {
                Text(problem).foregroundStyle(.secondary)
            }
            if let props {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(props.title).font(.headline)
                        Text(props.state == .draft ? "draft -- not on the site, preview only" : props.address.trimmingPrefix("/"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    if props.state == .draft {
                        PropsRow(label: "preview", value: props.url)
                        if props.scheduled, let date = props.date {
                            PropsRow(label: "scheduled", value: humanDate(date))
                        }
                    } else if let date = props.date {
                        PropsRow(label: "state", value: "published, \(humanDate(date))")
                    }
                    PropsRow(label: "type", value: props.type)
                    PropsRow(label: "tags", value: props.tags.joined(separator: ", "))
                    PropsRow(label: "series", value: seriesLabel(props))
                    PropsRow(label: "pinned", value: props.pinned ? "yes -- held at the top of the front page" : nil)
                    PropsRow(label: "unlisted", value: props.unlisted ? "yes -- reachable by its address, in no listing, feed, sitemap or search" : nil)
                    PropsRow(label: "languages", value: languagesLabel(props))
                    PropsRow(label: "announced", value: announcedLabel(props))
                    PropsRow(label: "old links", value: props.addresses.isEmpty ? nil : "\(props.addresses.count) address(es) still redirect here")
                }
                Section("Actions") {
                    ForEach(props.actions, id: \.self) { action in
                        Label(actionLabel(action), systemImage: actionSymbol(action))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if props == nil && problem == nil { ProgressView() }
        }
        .navigationTitle(slug)
        .toolbarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            props = try await Engine.shared.call(["props", slug])
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    private func humanDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.engine.date(from: iso) else { return iso }
        return date.formatted(date: .numeric, time: .shortened)
    }

    private func seriesLabel(_ props: PropsAnswer) -> String? {
        guard let series = props.series else { return nil }
        guard let part = props.seriesPart else { return series }
        return "\(series), part \(part)"
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
        case .onPublish: return "not yet -- goes out when the post publishes"
        case .nowhere: return "never -- this site announces nowhere"
        case .neverUnlisted: return "never -- an unlisted post is not announced"
        case .noSecret: return "never, as things stand -- the network's token is empty"
        case .notAnnounced: return "not announced"
        }
    }

    private func actionLabel(_ action: PostAction) -> LocalizedStringKey {
        switch action {
        case .publish: "publish"
        case .schedule: "schedule"
        case .unschedule: "cancel the schedule"
        case .unpublish: "unpublish"
        case .announce: "announce"
        case .pin: "pin/unpin"
        case .properties: "properties"
        case .rename: "rename slug"
        case .addresses: "old links"
        case .versions: "earlier versions"
        case .delete: "delete"
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

/// A row of the frame: the label in the left column, the value beside
/// it; a row with nothing to say is not drawn, as on the terminal.
struct PropsRow: View {
    let label: LocalizedStringKey
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            LabeledContent {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            } label: {
                Text(label)
            }
        }
    }
}

#Preview {
    NavigationStack { PropsView(slug: "venku") }
}
