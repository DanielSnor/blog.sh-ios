import SwiftUI

/// What the app says without being asked and without asking back: that
/// something was done, and that the site is being brought up to date. One
/// place for both, shown under whatever screen is open, so the same thing
/// is said the same way wherever it happens -- and nothing of it is a key.
///
/// The site is built by the app itself. A change the site does not show
/// yet -- a pin, a rename, a post deleted or restored, the queue put in
/// another order -- is owed a build; the build waits a moment for the
/// next such change, as the terminal's queue waits for the way out, and
/// then runs. Nobody is asked whether it should.
@Observable final class Herald {
    static let shared = Herald()

    enum Build: Equatable {
        case none
        /// A change waits for its build; another may follow.
        case owed
        case building
        case failed(String)
    }

    private(set) var build: Build = .none
    /// What the site does not show yet, in the words of the screen that changed it.
    private(set) var owedFor = ""
    /// What was just done, said for a few seconds.
    private(set) var note: String?

    /// How long a build waits for the next change, and for whatever else
    /// holds the engine when it finds it busy.
    private let pause: Double
    private let retry: Double
    /// Which blog is open, and the build itself: the engine's `rebuild`.
    private let open: () -> UUID?
    private let rebuild: () async throws -> Void

    private var waiting: Task<Void, Never>?
    private var fading: Task<Void, Never>?
    /// The blog the build is owed to: a build is that blog's and no other's.
    private var blog: UUID?
    private var again = false
    private var tries = 0

    init(pause: Double = 6, retry: Double = 10,
         open: @escaping () -> UUID? = { Blogs.shared.currentID },
         rebuild: @escaping () async throws -> Void = { let _: RebuildAnswer = try await Engine.shared.call(["rebuild"]) }) {
        self.pause = pause
        self.retry = retry
        self.open = open
        self.rebuild = rebuild
    }

    /// A build holds the lock a change of the queue or another build needs.
    var isBuilding: Bool { build == .building }

    /// Something was done: said, and gone again by itself.
    func say(_ words: String) {
        guard !words.isEmpty else { return }
        note = words
        fading?.cancel()
        fading = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { note = nil }
        }
    }

    /// A change the site does not show yet. `why`: what a reader of the
    /// site would notice, where the screen has more to say than that.
    func owe(_ why: String? = nil) {
        owedFor = why ?? String(localized: "The site does not show this change yet.")
        blog = open()
        tries = 0
        if build == .building {
            // Changed while a build runs: that build may have missed it.
            again = true
        } else {
            build = .owed
            arm()
        }
    }

    /// The site was just built by something else -- a publish builds it
    /// whole -- so what was owed is paid.
    func settled() {
        guard build == .owed else { return }
        waiting?.cancel()
        build = .none
    }

    /// A failure was read; the line goes.
    func acknowledge() {
        if case .failed = build { build = .none }
    }

    private func arm(after seconds: Double? = nil) {
        waiting?.cancel()
        waiting = Task {
            try? await Task.sleep(for: .seconds(seconds ?? pause))
            guard !Task.isCancelled else { return }
            await run()
        }
    }

    private func run() async {
        guard build == .owed else { return }
        // Another blog is open by now: its engine is not the one to ask.
        guard blog == open() else {
            build = .none
            return
        }
        build = .building
        again = false
        do {
            try await rebuild()
            if again {
                build = .owed
                arm()
            } else {
                build = .none
            }
        } catch EngineError.refused(let refusal) where refusal.error == "busy" && tries < 6 {
            // Something else is building or publishing: the same wish, a little later.
            tries += 1
            build = .owed
            arm(after: retry)
        } catch {
            build = error.isCalledOff ? .none : .failed(error.localizedDescription)
        }
    }
}

/// The herald's place on the screen: a line or two over the lower edge,
/// there only while there is something to say.
struct HeraldStrip: View {
    private var herald = Herald.shared

    var body: some View {
        if herald.build != .none || herald.note != nil {
            VStack(alignment: .leading, spacing: 5) {
                if let note = herald.note {
                    Text(verbatim: note)
                        .font(.ui(13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                }
                switch herald.build {
                case .none:
                    EmptyView()
                case .owed:
                    Text(verbatim: herald.owedFor)
                        .font(.ui(13))
                        .foregroundStyle(Theme.muted)
                case .building:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        ProgressView().controlSize(.mini)
                        (Text(verbatim: herald.owedFor + " — ") + Text("Building the site now."))
                            .font(.ui(13))
                            .foregroundStyle(Theme.muted)
                    }
                case .failed(let why):
                    // The one thing here that wants something: it failed, and
                    // where to try again. A tap puts it away.
                    Text("The site could not be built: \(why) It can be tried again under The site.")
                        .font(.ui(13))
                        .foregroundStyle(Theme.danger)
                        .onTapGesture { herald.acknowledge() }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 10)
            .background(Theme.paper)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            .accessibilityElement(children: .combine)
        }
    }
}

/// What a screen is doing while it cannot be touched: a wheel and a word
/// over it. An action that is over in a blink says nothing -- the note
/// only comes up once the wait is long enough to be wondered about.
struct BusyNote: View {
    let words: Text
    @State private var shown = false

    var body: some View {
        Group {
            if shown {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    words.font(.ui(14, weight: .medium)).foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Theme.paper, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            shown = true
        }
    }
}

extension View {
    /// Says what the screen is doing, while it is doing something.
    func doing(_ words: Text?) -> some View {
        overlay { if let words { BusyNote(words: words) } }
    }
}

/// The word for what an engine command is doing, by the command.
enum Doing {
    static func word(_ args: [String]) -> Text {
        switch args.first {
        case "publish": Text("Publishing…")
        case "unpublish": Text("Unpublishing…")
        case "delete": Text("Deleting…")
        case "restore": Text("Restoring…")
        case "toot", "bluesky": Text("Announcing…")
        case "empty": Text("Clearing out…")
        case "rebuild": Text("Rebuilding…")
        default: Text("Saving…")
        }
    }
}

extension Date {
    /// A time a post goes out, as a sentence says it: the day, the date, the hour.
    var spoken: String {
        formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute())
    }
}
