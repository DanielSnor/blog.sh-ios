import SwiftUI
import UIKit
import CoreText

/// How the app looks: paper and ink by day, ink and paper on black by
/// night, one accent -- the blog's own -- and three voices of type: a
/// display serif set in lower case for what a screen is, a plain sans for
/// what it holds, and a typewriter face for what the engine says (a
/// version, a count, a date, a key).
nonisolated enum Theme {
    /// The ground everything sits on.
    static let paper = dynamic(light: 0xEAE9E3, dark: 0x000000)
    /// What is written on it.
    static let ink = dynamic(light: 0x1E1D1C, dark: 0xEAE9E3)
    /// What is written beside it: tags, dates, hints.
    static let muted = dynamic(light: 0x6B6862, dark: 0x9A9993)
    /// A hairline: the edge of a card, the rule between two rows.
    static let line = dynamic(light: 0x1E1D1C, dark: 0xEAE9E3, lightAlpha: 0.18, darkAlpha: 0.16)
    /// The inside of a card, barely off the ground.
    static let card = dynamic(light: 0x1E1D1C, dark: 0xEAE9E3, lightAlpha: 0.03, darkAlpha: 0.05)
    /// Text on a pill filled with ink.
    static let onInk = dynamic(light: 0xEAE9E3, dark: 0x14110F)
    /// What cannot be taken back: a delete, a refusal. The one colour
    /// beside the accent, and never a fill.
    static let danger = dynamic(light: 0xA81800, dark: 0xFF7A5C)
    /// The accent before a blog has said its own.
    static let ember = Color(.sRGB, red: 1, green: 0x2E / 255.0, blue: 0)

    static let corner: CGFloat = 14
    static let gutter: CGFloat = 20

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            let dim = traits.userInterfaceStyle == .dark
            let value = dim ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 0xff) / 255,
                           green: CGFloat((value >> 8) & 0xff) / 255,
                           blue: CGFloat(value & 0xff) / 255,
                           alpha: dim ? darkAlpha : lightAlpha)
        })
    }
}

/// The faces the look is set in. Two of them ride in the app's bundle as
/// font files and are registered when it starts; where a file is missing
/// the system's own serif and sans stand in, so a build without them is a
/// build that still reads.
nonisolated enum Typeface {
    static func register() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// A terminal's face with a typewriter's feet, kin to the one the
    /// engine speaks in. The file names its family with its weight, so
    /// both spellings are asked.
    static let display: String? = ["IBM Plex Mono", "IBM Plex Mono Medium"]
        .flatMap { UIFont.fontNames(forFamilyName: $0) }
        .first { $0.hasPrefix("IBMPlexMono-Med") }
    private static let sans: [String] = UIFont.fontNames(forFamilyName: "Work Sans")

    static func sans(_ weight: Font.Weight) -> String? {
        let suffix: String
        switch weight {
        case .bold: suffix = "-Bold"
        case .semibold: suffix = "-SemiBold"
        case .medium: suffix = "-Medium"
        default: suffix = "-Regular"
        }
        return sans.first { $0.hasSuffix(suffix) }
    }
}

extension Font {
    /// What a screen is: its name, the blog's name.
    static func display(_ size: CGFloat) -> Font {
        if let name = Typeface.display { return .custom(name, size: size, relativeTo: .largeTitle) }
        return .system(size: size, weight: .medium, design: .monospaced)
    }

    /// What a screen holds.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let name = Typeface.sans(weight) { return .custom(name, size: size, relativeTo: .body) }
        return .system(size: size, weight: weight)
    }

    /// What the engine says.
    static func mono(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom(bold ? "CourierNewPS-BoldMT" : "CourierNewPSMT", size: size, relativeTo: .caption)
    }
}

extension Text {
    /// A line in the engine's voice: typewriter, lower case, a little air
    /// between the letters.
    func engineLabel(_ size: CGFloat = 12, bold: Bool = true) -> some View {
        font(.mono(size, bold: bold)).tracking(size * 0.06).textCase(.lowercase)
    }
}

extension EnvironmentValues {
    /// How much larger than on a phone the first screen draws itself: one,
    /// or more where it is a page of its own on a wide screen.
    @Entry var scale: CGFloat = 1
}

/// A row of its own on the ground: a hairline around, a large corner.
struct Card<Content: View>: View {
    var highlighted = false
    var capsule = false
    @ViewBuilder var content: Content
    @Environment(\.scale) private var scale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: capsule ? 999 : Theme.corner * scale, style: .continuous)
        HStack(spacing: 10 * scale) { content }
            .padding(.horizontal, 13 * scale)
            .padding(.vertical, 12 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { if highlighted { shape.fill(.tint.opacity(0.12)) } else { shape.fill(Theme.card) } }
            .overlay { if highlighted { shape.strokeBorder(.tint, lineWidth: 1) } else { shape.strokeBorder(Theme.line, lineWidth: 1) } }
            .contentShape(shape)
    }
}

/// How many: the accent, filled, with the number in the engine's voice.
struct CountBadge: View {
    let count: Int
    @Environment(\.scale) private var scale

    var body: some View {
        Text(verbatim: "\(count)")
            .font(.mono(12 * scale))
            .foregroundStyle(.white)
            .padding(.horizontal, 9 * scale)
            .padding(.vertical, 2 * scale)
            .background(.tint, in: Capsule())
    }
}

/// A key of the terminal, kept as a mark: a digit in a small square.
struct KeyChip: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.mono(13))
            .foregroundStyle(Theme.muted)
            .frame(width: 26, height: 26)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// A filter: an outline at rest, filled with ink when it is the one on.
struct FilterPill: View {
    let label: String
    var selected = false

    var body: some View {
        Text(verbatim: label)
            .font(.mono(11, bold: selected))
            .tracking(0.6)
            .textCase(.lowercase)
            .lineLimit(1)
            .foregroundStyle(selected ? Theme.onInk : Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background { if selected { Capsule().fill(Theme.ink) } }
            .overlay { Capsule().strokeBorder(selected ? Theme.ink : Theme.line, lineWidth: 1) }
            .contentShape(Capsule())
    }
}

/// The head of a screen: its name in the display face, and beside it how
/// many it holds.
struct ScreenHeader: View {
    let title: String
    var count: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: title)
                .font(.display(29))
                .textCase(.lowercase)
                .foregroundStyle(Theme.ink)
            if let count {
                Text(verbatim: count)
                    .font(.mono(12))
                    .foregroundStyle(.tint)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A press on a card or a tile: it dims, and comes back.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// A date as a row says it: this year's by day and month, an older one
/// with its year; a time soon to come by its weekday and hour.
nonisolated enum RowDate {
    static func short(_ date: Date) -> String {
        let sameYear = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: .now)
        return sameYear ? date.formatted(.dateTime.day().month(.defaultDigits))
                        : date.formatted(.dateTime.day().month(.defaultDigits).year())
    }

    static func soon(_ date: Date) -> String {
        let ahead = date.timeIntervalSinceNow
        guard ahead > -86_400, ahead < 6 * 86_400 else { return short(date) }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

extension View {
    /// The bar keeps its buttons and gives up its title: a screen says its
    /// own name, in its own face, at the head of what it holds.
    func namedByItsHeader() -> some View {
        toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
            }
    }

    /// A list on paper: no cards of the system's, no ground but ours.
    func paperList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .namedByItsHeader()
    }

    /// A row of such a list: the ground shows through, a hairline under it
    /// from one gutter to the other -- not from wherever the row's first
    /// word happens to start.
    func paperRow(rule: Bool = true) -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: Theme.gutter, bottom: 0, trailing: Theme.gutter))
            .listRowSeparator(.hidden, edges: .top)
            .listRowSeparator(rule ? .visible : .hidden, edges: .bottom)
            .listRowSeparatorTint(Theme.line)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .alignmentGuide(.listRowSeparatorTrailing) { row in row.width }
    }
}

// MARK: - A screen that is not a list

/// A screen of fields, facts and actions: everything it holds in one
/// column on paper, between the two gutters.
struct PaperScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 2)
                .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.paper.ignoresSafeArea())
        .namedByItsHeader()
    }
}

/// A post at the head of its own screen. Its title is its own words, so
/// it keeps its capitals and the plain face; under it, in the engine's
/// voice, what the engine calls it.
struct PostHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.ui(22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail, !detail.isEmpty {
                Text(verbatim: detail)
                    .font(.mono(12, bold: false))
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// What the rows under it are, in the engine's voice.
struct SectionLabel: View {
    let text: Text

    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim: String) { text = Text(verbatim: verbatim) }

    var body: some View {
        text.engineLabel()
            .foregroundStyle(Theme.muted)
            .padding(.top, 22)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A word of explanation under a plate.
struct Hint: View {
    let text: Text

    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim: String) { text = Text(verbatim: verbatim) }

    var body: some View {
        text.font(.ui(13))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }
}

/// What went wrong, where it went wrong.
struct ProblemLine: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.ui(14))
            .foregroundStyle(Theme.danger)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
            .textSelection(.enabled)
    }
}

/// Several rows that belong together, on one card: a hairline around
/// them and one between each two. A row that draws nothing takes no
/// place and leaves no rule behind.
struct Plate<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }
                    row.padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(shape.fill(Theme.card))
        .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
        .clipShape(shape)
    }
}

/// A fact: what it is in the engine's voice, what it says beside it.
/// One with nothing to say is not drawn, as on the terminal.
struct InfoRow: View {
    let label: LocalizedStringKey
    let value: String?
    var mono = false

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).engineLabel().foregroundStyle(Theme.muted).fixedSize()
                Spacer(minLength: 8)
                // The value has the row: it wraps rather than being cut, and the
                // label keeps to its own width.
                Text(verbatim: value)
                    .font(mono ? .mono(13, bold: false) : .ui(15))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .textSelection(.enabled)
            }
        }
    }
}

/// A short value to type, named in the engine's voice at its side.
struct FieldRow: View {
    let label: LocalizedStringKey
    @Binding var text: String
    var prompt: String = ""
    var mono = false
    /// The width the labels of one plate share, so their fields line up.
    var labelWidth: CGFloat = 72

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).engineLabel().foregroundStyle(Theme.muted)
                .frame(width: labelWidth, alignment: .leading)
            TextField("", text: $text, prompt: Text(verbatim: prompt).foregroundStyle(Theme.muted))
                .font(mono ? .mono(15, bold: false) : .ui(16))
                .foregroundStyle(Theme.ink)
        }
    }
}

/// Something the screen can do or lead to: its mark in the accent, its
/// name, and an arrow when it leads somewhere. What cannot be taken back
/// says so by its colour.
struct CommandRow: View {
    let symbol: String
    let label: Text
    var danger = false
    var leads = false
    var busy = false

    // Callable from a label closure that is not the main actor's -- the
    // photo picker's is one.
    nonisolated init(_ key: LocalizedStringKey, symbol: String, danger: Bool = false, leads: Bool = false, busy: Bool = false) {
        self.init(text: Text(key), symbol: symbol, danger: danger, leads: leads, busy: busy)
    }

    nonisolated init(text: Text, symbol: String, danger: Bool = false, leads: Bool = false, busy: Bool = false) {
        label = text
        self.symbol = symbol
        self.danger = danger
        self.leads = leads
        self.busy = busy
    }

    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 11) {
            Group {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 16))
                        .foregroundStyle(danger ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(.tint))
                }
            }
            .frame(width: 22)
            label.font(.ui(15, weight: .medium))
                .foregroundStyle(danger ? Theme.danger : Theme.ink)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 6)
            if leads {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .opacity(enabled ? 1 : 0.45)
        .contentShape(Rectangle())
    }
}

/// The one thing a screen is for: the accent, filled, the words in the
/// engine's voice. One of these to a screen.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration)
    }

    private struct Face: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.mono(13))
                .tracking(0.8)
                .textCase(.lowercase)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.tint, in: Capsule())
                .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
                .contentShape(Capsule())
        }
    }
}

/// A screen with nothing to show says so where the rows would be -- as
/// loudly as the room it stands in is large, and no louder. Three rooms:
/// the column beside the menu, where the note is an invitation and the
/// whole of what is there; a screen of its own -- an empty queue, an empty
/// trash -- where it fills the place without outweighing the screen's
/// name, a little larger where the screen is wide; and a part of a
/// screen -- a sheet's list, a search that found nothing with the keyboard
/// up -- where it stays the small remark it was.
struct EmptyNote: View {
    enum Room { case welcome, screen, part }

    let symbol: String
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    /// A screen of its own unless it is said otherwise.
    var room: Room = .screen
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var wide: Bool { sizeClass == .regular }

    private var mark: CGFloat {
        switch room {
        case .welcome: 104
        case .screen: wide ? 64 : 46
        case .part: 26
        }
    }

    private var words: CGFloat {
        switch room {
        case .welcome: 21
        case .screen: wide ? 19 : 17
        case .part: 16
        }
    }

    var body: some View {
        VStack(spacing: room == .welcome ? 22 : room == .screen ? 14 : 8) {
            Image(systemName: symbol)
                .font(.system(size: mark, weight: room == .part ? .light : .thin))
                .foregroundStyle(Theme.muted)
            Text(title).font(.ui(words, weight: .medium)).foregroundStyle(Theme.ink)
            if let detail {
                Text(detail).font(.ui(room == .part ? 14 : 15)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: 420)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 36)
    }
}

/// What a screen has to say after an action, and what it may ask with it:
/// one thing at a time. Two alerts raised together show one and lose the
/// other -- a post was deleted, and the screen only asked about a rebuild
/// -- so what follows an action is said as one, its question in it.
struct Said: Identifiable {
    struct Ask {
        let button: String
        var cancel: String = String(localized: "Cancel")
        let run: () async -> Void
    }

    let id = UUID()
    var title = ""
    var text = ""
    var ask: Ask?
    /// When it is put away without acting on it.
    var after: (() -> Void)?
}

extension View {
    func says(_ said: Binding<Said?>) -> some View {
        alert(said.wrappedValue?.title ?? "",
              isPresented: Binding(get: { said.wrappedValue != nil }, set: { if !$0 { said.wrappedValue = nil } }),
              presenting: said.wrappedValue) { one in
            if let ask = one.ask {
                Button(ask.button) {
                    Task {
                        // The alert this key sits in is still on its way out,
                        // and what the action says next is said through the
                        // same place: an answer that came at once -- a
                        // refusal, a quick rebuild -- was wiped by the alert
                        // closing. So the action waits until the place is free.
                        try? await Task.sleep(for: .milliseconds(450))
                        await ask.run()
                    }
                }
                Button(ask.cancel, role: .cancel) { one.after?() }
            } else {
                Button("OK") { one.after?() }
            }
        } message: { one in
            Text(verbatim: one.text)
        }
    }
}

/// A site that publishes in more than one language refuses to publish or
/// schedule a post that has no words in one of them, unless it is told to
/// (`--allow-partial`). At the desk that is a flag typed after reading the
/// refusal; here it is the question the refusal becomes.
enum Partial {
    static let code = "partial_translation"
    static var words: String {
        String(localized: "This site publishes in more than one language and this post is not written in all of them yet: it would go out in one language only.")
    }
}

/// A command row that is a button: it dims under the finger and does its one thing.
struct Command: View {
    let label: Text
    let symbol: String
    var danger = false
    var leads = false
    var busy = false
    let action: () -> Void

    init(_ key: LocalizedStringKey, symbol: String, danger: Bool = false, leads: Bool = false, busy: Bool = false,
         action: @escaping () -> Void) {
        self.init(text: Text(key), symbol: symbol, danger: danger, leads: leads, busy: busy, action: action)
    }

    init(text: Text, symbol: String, danger: Bool = false, leads: Bool = false, busy: Bool = false,
         action: @escaping () -> Void) {
        label = text
        self.symbol = symbol
        self.danger = danger
        self.leads = leads
        self.busy = busy
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            CommandRow(text: label, symbol: symbol, danger: danger, leads: leads, busy: busy)
        }
        .buttonStyle(PressStyle())
    }
}

/// One of a few: the property named in the engine's voice, and beside it
/// what is chosen now -- which opens the others.
struct ChoiceRow<Selection: Hashable, Options: View>: View {
    let label: LocalizedStringKey
    /// The choice as the row says it.
    let chosen: String
    @Binding var selection: Selection
    @ViewBuilder var options: Options

    var body: some View {
        HStack(spacing: 12) {
            Text(label).engineLabel().foregroundStyle(Theme.muted).fixedSize()
            Spacer(minLength: 8)
            Menu {
                Picker(label, selection: $selection) { options }
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: chosen)
                        .font(.ui(15))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                .contentShape(Rectangle())
            }
        }
    }
}

/// On or off: a sentence in the plain face, or a property in the engine's voice.
struct SwitchRow: View {
    let label: LocalizedStringKey
    @Binding var isOn: Bool
    var property = false

    var body: some View {
        Toggle(isOn: $isOn) {
            if property {
                Text(label).engineLabel().foregroundStyle(Theme.muted)
            } else {
                Text(label).font(.ui(15)).foregroundStyle(Theme.ink)
            }
        }
        .padding(.vertical, -3)
    }
}

/// The text of a post, wherever it is typed: markdown, the raw material
/// the engine reads, in the typewriter face -- and over it the marks the
/// /write/ page offers, as keys. The last key opens the text over the whole
/// screen, for writing with nothing else in sight; the same key there
/// closes it again. Both are the one text.
struct PaperEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 220
    @State private var whole = false

    var body: some View {
        EditorKeys(text: $text, selection: $selection, symbol: "arrow.up.left.and.arrow.down.right",
                   label: String(localized: "editor.whole", defaultValue: "Write on the whole screen")) { whole = true }
        TextEditor(text: $text, selection: $selection)
            .font(.mono(15, bold: false))
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(.horizontal, -5)
            .padding(.vertical, -4)
            .fullScreenCover(isPresented: $whole) { WritingScreen(text: $text) }
    }

    @State private var selection: TextSelection?
}

/// Nothing but the text: the marks over it, the paper under it, the
/// keyboard up. On a wide screen the lines keep a length one can read.
struct WritingScreen: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @State private var selection: TextSelection?
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            EditorKeys(text: $text, selection: $selection, symbol: "arrow.down.right.and.arrow.up.left",
                       label: String(localized: "editor.back", defaultValue: "Back to the form")) { dismiss() }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
            Rectangle().fill(Theme.line).frame(height: 1)
            TextEditor(text: $text, selection: $selection)
                .font(.mono(16, bold: false))
                .lineSpacing(4)
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .focused($typing)
                .padding(.horizontal, Theme.gutter - 5)
                .padding(.top, 8)
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(Theme.paper.ignoresSafeArea())
        .onAppear { typing = true }
    }
}

/// The marks, and at their end the key that opens or closes the whole
/// screen. The marks scroll under it; the key stays where the thumb left it.
struct EditorKeys: View {
    @Binding var text: String
    @Binding var selection: TextSelection?
    let symbol: String
    let label: String
    let turn: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            MarkBar { kind in mark(kind) }
            Button(action: turn) {
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 30)
                    .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
                    .contentShape(shape)
            }
            .buttonStyle(PressStyle())
            .padding(.vertical, -4)
            .accessibilityLabel(Text(verbatim: label))
        }
    }

    /// The mark goes where the caret or the selection is; with neither
    /// -- the text was never touched -- at its end.
    private func mark(_ kind: Marks.Kind) {
        let whole = (text as NSString).length
        var range = NSRange(location: whole, length: 0)
        if let selection {
            switch selection.indices {
            case .selection(let picked):
                if picked.lowerBound >= text.startIndex, picked.upperBound <= text.endIndex {
                    range = NSRange(picked, in: text)
                }
            case .multiSelection(let set):
                if let first = set.ranges.first, first.upperBound <= text.endIndex {
                    range = NSRange(first, in: text)
                }
            @unknown default:
                break
            }
        }
        let words = Marks.Words(text: String(localized: "mark.link.text", defaultValue: "text"), url: "https://")
        let out = Marks.apply(text, selection: range, kind: kind, words: words)
        text = out.value
        if let picked = Range(out.selection, in: out.value) {
            selection = picked.isEmpty ? TextSelection(insertionPoint: picked.lowerBound) : TextSelection(range: picked)
        }
    }
}

/// The marks as a row of keys over the text: the ones the /write/ page
/// has, in its order.
struct MarkBar: View {
    let apply: (Marks.Kind) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Marks.Kind.allCases, id: \.self) { kind in
                    Button { apply(kind) } label: { face(kind) }
                        .accessibilityLabel(Text(name(kind)))
                }
            }
            .buttonStyle(PressStyle())
        }
        .padding(.vertical, -4)
    }

    @ViewBuilder
    private func face(_ kind: Marks.Kind) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            switch kind {
            case .bold: Text(verbatim: "B").font(.ui(14, weight: .bold))
            case .italic: Text(verbatim: "I").font(.system(size: 15, design: .serif)).italic()
            case .strike: Text(verbatim: "S").font(.ui(14)).strikethrough()
            case .code: Text(verbatim: "</>").font(.mono(11))
            case .link: Image(systemName: "link").font(.system(size: 12, weight: .semibold))
            case .h2: Text(verbatim: "H").font(.ui(14, weight: .bold))
            case .quote: Text(verbatim: "❝").font(.ui(14))
            case .ul: Text(verbatim: "•").font(.ui(16, weight: .bold))
            case .ol: Text(verbatim: "1.").font(.mono(12))
            case .fence: Text(verbatim: "```").font(.mono(11))
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(width: 34, height: 30)
        .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
        .contentShape(shape)
    }

    private func name(_ kind: Marks.Kind) -> LocalizedStringKey {
        switch kind {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strike: "Strikethrough"
        case .code: "Code"
        case .link: "Link"
        case .h2: "Heading"
        case .quote: "Quote"
        case .ul: "List"
        case .ol: "Numbered list"
        case .fence: "Code block"
        }
    }
}

/// What is on the way and whether the blog will take it: the line the
/// /write/ page keeps under its pictures, in its words, and its legend.
struct DeliveryNote: View {
    let shots: [Shot]
    let textBytes: Int
    let maxMb: Int

    var body: some View {
        let over = Delivery.over(shots: shots, textBytes: textBytes, maxMb: maxMb)
        if !shots.isEmpty || textBytes > 0 {
            let line = String(localized: "On the way: \(Delivery.describe(shots: shots, textBytes: textBytes))")
            let refusal = String(localized: "\(Delivery.size(Delivery.wireBytes(shots: shots, textBytes: textBytes))) once encoded for the wire, over the server's limit of \(maxMb) MB: it will refuse this")
            Text(verbatim: over ? "\(line) — \(refusal)" : line)
                .font(.ui(13, weight: over ? .medium : .regular))
                .foregroundStyle(over ? Theme.danger : Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        Hint("A picture is shrunk to \(String(Pictures.maxEdge)) px on its long edge before it goes; a video is converted to H.264 at 720p. The whole post -- text, pictures, video -- has to stay under \(maxMb) MB, the server's limit, and the limit is measured on the encoded transfer, a third larger than the files: the files themselves get about \(Int(Double(maxMb) * 0.73)) MB.")
    }
}


/// The label of the one filled button, with a spinner while it works.
struct PrimaryLabel: View {
    let label: LocalizedStringKey
    var busy = false

    var body: some View {
        HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.small).tint(.white) }
            Text(label)
        }
    }
}
