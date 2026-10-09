import SwiftUI

/// A look at the blog that changes nothing: `./blog.sh check` goes
/// through the archive -- the posts, their pictures, links and addresses
/// -- and `./blog.sh doctor` through the installation: its configuration,
/// its announcing, its schedule, its deploy. What either finds is listed
/// here, the problems first, each with the blog's own advice under it. A
/// finding about a post is a way to that post; one about the trash, to
/// the trash. The repairs both commands have at the desk are not here:
/// the blog does not let a program with a key run them.
struct DiagnosisView: View {
    enum What {
        case archive, installation

        var args: [String] { self == .archive ? ["check"] : ["doctor"] }

        var name: String {
            self == .archive ? String(localized: "Archive check") : String(localized: "Installation check")
        }
    }

    let what: What
    @State private var answer: DiagnosisAnswer?
    @State private var problem: String?
    /// The blog's engine is older than this check's way to the app.
    @State private var notOffered = false
    @State private var running = false

    var body: some View {
        PaperScreen(name: what.name) {
            if let answer {
                Plate {
                    (answer.errors == 0 && answer.warnings == 0
                        ? Text("No problems.")
                        : Text("Problems: \(answer.errors), worth a look: \(answer.warnings)"))
                        .font(.ui(15, weight: .medium))
                        .foregroundStyle(answer.errors > 0 ? Theme.danger : Theme.ink)
                }
                .gap(14)
                Plate {
                    ForEach(Array(answer.ordered.enumerated()), id: \.offset) { _, finding in
                        row(finding)
                    }
                }
                .gap(14)
                Hint("The sentences are the blog's own -- in this app's language where the blog's engine has it, in the blog's otherwise. Nothing is repaired from here.")
                Plate {
                    Command("Check again", symbol: "arrow.clockwise") { Task { await run() } }
                }
                .gap(14)
                .disabled(running)
            } else if notOffered {
                Hint("This blog's engine does not offer this check to the app yet. It comes with a newer ./blog.sh.")
                    .gap(14)
            } else if let problem {
                ProblemLine(text: problem)
            }
        }
        .doing(running ? Doing.word(what.args) : nil)
        .navigationTitle(Text(verbatim: what.name))
        .task { if answer == nil { await run() } }
    }

    @ViewBuilder private func row(_ finding: DiagnosisAnswer.Finding) -> some View {
        if let slug = finding.slug, !slug.isEmpty {
            NavigationLink { PropsView(slug: slug) } label: { line(finding, leads: true) }
                .buttonStyle(PressStyle())
        } else if finding.kind == "trash", finding.level != .fine {
            NavigationLink { TrashView() } label: { line(finding, leads: true) }
                .buttonStyle(PressStyle())
        } else {
            line(finding, leads: false)
        }
    }

    private func line(_ finding: DiagnosisAnswer.Finding, leads: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            mark(finding.level)
                .font(.ui(14, weight: .semibold))
                .frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: finding.text)
                    .font(.ui(15))
                    .foregroundStyle(finding.level == .fine ? Theme.muted : Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let fix = finding.fix {
                    Text(verbatim: fix)
                        .font(.ui(13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            if leads {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func mark(_ level: DiagnosisAnswer.Finding.Level) -> some View {
        switch level {
        case .error: Image(systemName: "xmark.octagon").foregroundStyle(Theme.danger).accessibilityLabel(Text("Problem"))
        case .warning: Image(systemName: "exclamationmark.triangle").foregroundStyle(.tint).accessibilityLabel(Text("Worth a look"))
        case .fine: Image(systemName: "checkmark").foregroundStyle(Theme.muted).accessibilityLabel(Text("Fine"))
        }
    }

    private func run() async {
        running = true
        defer { running = false }
        do {
            answer = try await Engine.shared.call(what.args)
            problem = nil
            notOffered = false
        } catch EngineError.refused(let refusal) where refusal.error == "unknown_command" {
            notOffered = true
        } catch {
            problem = error.isCalledOff ? problem : error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { DiagnosisView(what: .archive) }
}
