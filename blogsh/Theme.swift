import SwiftUI
import UIKit
import CoreText

/// How the app looks: a ground and the ink on it, by day and by night,
/// and one accent -- all of them the open blog's own, as its pages have
/// them, or the app's own -- and three voices of type: a terminal's face
/// set in lower case for what a screen is, a plain sans for what it
/// holds, and a typewriter face for what the engine says (a version, a
/// count, a date, a key).
nonisolated enum Theme {
    /// The ground everything sits on.
    @MainActor static var paper: Color {
        let worn = Look.shared.worn
        return dynamic(light: worn.light.bg, dark: worn.dark.bg)
    }
    /// What is written on it.
    @MainActor static var ink: Color {
        let worn = Look.shared.worn
        return dynamic(light: worn.light.text, dark: worn.dark.text)
    }
    /// What is written beside it: tags, dates, hints.
    @MainActor static var muted: Color {
        let worn = Look.shared.worn
        return dynamic(light: worn.light.metaText, dark: worn.dark.metaText)
    }
    /// A hairline: the edge of a card, the rule between two rows.
    @MainActor static var line: Color {
        let worn = Look.shared.worn
        return dynamic(light: worn.light.border, dark: worn.dark.border)
    }
    /// The inside of a card, barely off the ground.
    @MainActor static var card: Color {
        let worn = Look.shared.worn
        return dynamic(light: worn.light.text, dark: worn.dark.text, lightAlpha: 0.03, darkAlpha: 0.05)
    }
    /// Text on a pill filled with ink: the ground's own colour.
    @MainActor static var onInk: Color {
        let worn = Look.shared.worn
        return dynamic(light: worn.light.bg, dark: worn.dark.bg)
    }
    /// What cannot be taken back: a delete, a refusal. The one colour
    /// beside the accent, and never a fill.
    static let danger = dynamic(light: 0xA81800, dark: 0xFF7A5C)
    /// The accent before a blog has said its own, and the app's own when
    /// it keeps to its own colours.
    static let accent = dynamic(light: Tones.ownAccent.light, dark: Tones.ownAccent.dark)

    /// The engine's voice and the names of screens are set in lower case
    /// -- except in German, which reads its nouns by their capitals: there
    /// the words stand as they are written.
    static let voiceCase: Text.Case? = Bundle.main.preferredLocalizations.first == "de" ? nil : .lowercase

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

/// Whose colours the app wears: the open blog's -- its ground, its ink,
/// its rules, as its pages have them -- or its own, when the blog has
/// said none or when it is asked to keep to its own. The last is for eyes
/// that a blog's palette does not serve: the app's own are always the
/// same, whatever a blog chose.
@Observable final class Look {
    static let shared = Look()
    static let key = "ownColours"

    /// Keep to the app's own colours, the accent included.
    var own: Bool {
        didSet { UserDefaults.standard.set(own, forKey: Self.key) }
    }

    private init() {
        own = UserDefaults.standard.bool(forKey: Self.key)
    }

    /// The two schemes everything is drawn in now.
    var worn: (light: Tones.Scheme, dark: Tones.Scheme) {
        let blog = Blogs.shared.current
        return Tones.worn(own: own, light: blog?.tonesLight, dark: blog?.tonesDark)
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

/// The size of the type where the app sets it by its own hand: an iPad
/// app on a Mac, which the system gives one size of type and no way to
/// another. Everywhere else the system enlarges the faces itself, and
/// this only keeps what was chosen.
@Observable final class TypeScale {
    static let shared = TypeScale()

    /// The system has no larger type to give here. (The flag is for
    /// seeing the Mac's way in a simulator.)
    static let ownHand: Bool = {
        #if TYPE_BY_OWN_HAND
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }()

    var size: TextSize {
        didSet { UserDefaults.standard.set(size.rawValue, forKey: TextSize.key) }
    }

    private init() {
        size = TextSize(kept: UserDefaults.standard.integer(forKey: TextSize.key))
    }

    /// How much larger every face is drawn by the app itself.
    var factor: CGFloat { Self.ownHand ? size.zoom : 1 }

    /// Type so large that a name and its value no longer share a row --
    /// what the system calls an accessibility size where it has one.
    var crowded: Bool { Self.ownHand && size == .four }
}

extension Font {
    /// What a screen is: its name, the blog's name.
    static func display(_ size: CGFloat) -> Font {
        if let name = Typeface.display { return face(name, size, .largeTitle) }
        return .system(size: size * TypeScale.shared.factor, weight: .medium, design: .monospaced)
    }

    /// What a screen holds.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let name = Typeface.sans(weight) { return face(name, size, .body) }
        return .system(size: size * TypeScale.shared.factor, weight: weight)
    }

    /// What the engine says.
    static func mono(_ size: CGFloat, bold: Bool = true) -> Font {
        face(bold ? "CourierNewPS-BoldMT" : "CourierNewPSMT", size, .caption)
    }

    /// A face at a size the system enlarges with its own scale -- or,
    /// where it has none to enlarge with, at the size the app works out.
    private static func face(_ name: String, _ size: CGFloat, _ style: Font.TextStyle) -> Font {
        if TypeScale.ownHand { return .custom(name, fixedSize: size * TypeScale.shared.factor) }
        return .custom(name, size: size, relativeTo: style)
    }
}

extension Text {
    /// A line in the engine's voice: typewriter, lower case, a little air
    /// between the letters.
    func engineLabel(_ size: CGFloat = 12, bold: Bool = true) -> some View {
        font(.mono(size, bold: bold)).tracking(size * 0.06).textCase(Theme.voiceCase)
    }
}

extension EnvironmentValues {
    /// How much larger than on a phone the first screen draws itself: one,
    /// or more where it is a page of its own on a wide screen.
    @Entry var scale: CGFloat = 1
    /// How tall the page a form stands on is: what the text of a post
    /// measures its own room by.
    @Entry var pageHeight: CGFloat = 800
    /// Where the keyboard's upper edge is on the screen while it is up.
    @Entry var keyboardTop: CGFloat? = nil
}

/// The type as large as was chosen in the settings: the system's size and
/// the steps above it. Set once, on the window -- a sheet is drawn in the
/// window and not inside the screen under it, so a size set on that
/// screen alone would stop at the sheet's edge.
struct TextSized: ViewModifier {
    func body(content: Content) -> some View {
        // Where the app enlarges its own type there is nothing to ask of the window.
        content.background(WindowType(size: TypeScale.ownHand ? .system : TypeScale.shared.size))
    }
}

private struct WindowType: UIViewRepresentable {
    let size: TextSize

    func makeUIView(context: Context) -> Anchor { Anchor() }
    func updateUIView(_ view: Anchor, context: Context) { view.size = size }

    /// Nothing to see: only a place in the window, to reach it from.
    final class Anchor: UIView {
        var size = TextSize.system { didSet { apply() } }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isHidden = true
            // The steps stand on the system's size: when that moves, so do they.
            NotificationCenter.default.addObserver(self, selector: #selector(apply),
                                                   name: UIContentSizeCategory.didChangeNotification, object: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        @objc private func apply() {
            guard let window else { return }
            guard size != .system else {
                window.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
                return
            }
            let system = DynamicTypeSize(UIApplication.shared.preferredContentSizeCategory) ?? .large
            window.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(size.applied(to: system))
        }
    }
}

/// How large the type is: the same two letters in five sizes, the first
/// of them the system's own. The letters keep their sizes whatever is
/// chosen -- they are the scale, not what is measured on it.
struct TextSizePicker: View {
    private var scale = TypeScale.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
        HStack(spacing: 0) {
            ForEach(TextSize.allCases) { size in
                let chosen = size == scale.size
                if size != .system {
                    Rectangle().fill(Theme.line).frame(width: 1)
                }
                Button { scale.size = size } label: {
                    Text(verbatim: "Aa")
                        .font(.custom(Typeface.sans(.medium) ?? "Helvetica Neue", fixedSize: size.sample))
                        .foregroundStyle(chosen ? Theme.onInk : Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(chosen ? Theme.ink : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(Self.name(size))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .background(shape.fill(Theme.card))
        .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
        .clipShape(shape)
    }

    private static func name(_ size: TextSize) -> Text {
        switch size {
        case .system: Text("As the system has it")
        case .one: Text("One step larger")
        case .two: Text("Two steps larger")
        case .three: Text("Three steps larger")
        case .four: Text("Four steps larger")
        }
    }
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
            .textCase(Theme.voiceCase)
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
                .textCase(Theme.voiceCase)
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
    /// What a screen is stands in its bar, beside the way back: the page
    /// under it is the screen's own from its first line. A screen of the
    /// app's says its name, in the display face, and how many it holds; a
    /// screen about one post says the post's title.
    func namedByItsHeader(name: String? = nil, count: String? = nil, title: String? = nil) -> some View {
        toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BarName(name: name, count: count, title: title)
                }
            }
    }

    /// A list on paper: no cards of the system's, no ground but ours.
    func paperList(name: String? = nil, count: String? = nil) -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .namedByItsHeader(name: name, count: count)
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
    /// What the screen is, said in the bar beside the way back.
    var name: String?
    /// How many it holds, beside its name.
    var count: String?
    /// ...or, where it is about one post, that post's title: its own
    /// words, so in the plain face and with its capitals.
    var title: String?
    /// Counted by a form each time an action of its has answered -- a
    /// result or a refusal, written at the form's end. The page then goes
    /// there and the keyboard out of the way: an answer under the edge of
    /// the screen is an answer nobody got.
    var answered = 0
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 800
    @State private var keyboardTop: CGFloat?
    @State private var position = ScrollPosition()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 2)
                .padding(.bottom, 28)
                .environment(\.pageHeight, height)
                .environment(\.keyboardTop, keyboardTop)
        }
        .scrollPosition($position)
        .onChange(of: answered) {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            Task {
                // Once the answer is laid out and the keyboard has gone.
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation { position.scrollTo(edge: .bottom) }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            // Off the lower edge of the screen it is down, whatever it says of its size.
            let screen = (note.object as? UIScreen)?.bounds.height ?? .greatestFiniteMagnitude
            keyboardTop = frame.height > 0 && frame.minY < screen ? frame.minY : nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardTop = nil
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.paper.ignoresSafeArea())
        .namedByItsHeader(name: name, count: count, title: title)
    }
}

/// What stands in a bar where the system would put its title: the
/// screen's name, or a post's. It takes all the room between the way
/// back and whatever keys stand at the far end, and starts at the near
/// edge of it.
///
/// A post's title is somebody's own words and can be long: on one line
/// while it fits, and when it does not, smaller on two -- between a way
/// back and a key or two a single line would cut most titles short. What
/// does not fit on two is cut at its end.
struct BarName: View {
    var name: String?
    var count: String?
    var title: String?

    var body: some View {
        Group {
            if let title, !title.isEmpty {
                ViewThatFits(in: .horizontal) {
                    Text(verbatim: title)
                        .font(.ui(18, weight: .bold))
                        .lineLimit(1)
                    Text(verbatim: title)
                        .font(.ui(14, weight: .bold))
                        .lineSpacing(-2)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        // As tall as its two lines: the bar would hold it to one.
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.ink)
            } else if let name, !name.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: name)
                        .font(.display(21))
                        .textCase(Theme.voiceCase)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let count {
                        Text(verbatim: count)
                            .font(.mono(12))
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            } else {
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            }
        }
        // The bar gives its middle what the middle asks for and centres
        // it; asked for more than there is, it gives all there is -- and
        // the name then starts at the near edge of that, beside the way back.
        .frame(idealWidth: 4000, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// What the engine calls a post, or where the post is: the first line of
/// a screen about it, under the title that stands in the bar.
struct PostSlug: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.mono(12, bold: false))
            .foregroundStyle(Theme.muted)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
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
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        if let value, !value.isEmpty {
            // At the largest sizes the two do not share a row: the value
            // stands under its name and has the whole width.
            if size.isAccessibilitySize || TypeScale.shared.crowded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).engineLabel().foregroundStyle(Theme.muted)
                    words(value, .leading)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(label).engineLabel().foregroundStyle(Theme.muted).fixedSize()
                    Spacer(minLength: 8)
                    // The value has the row: it wraps rather than being cut, and the
                    // label keeps to its own width.
                    words(value, .trailing).layoutPriority(1)
                }
            }
        }
    }

    private func words(_ value: String, _ side: TextAlignment) -> some View {
        Text(verbatim: value)
            .font(mono ? .mono(13, bold: false) : .ui(15))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(side)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
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
    @Environment(\.dynamicTypeSize) private var size
    /// How much the label's type has grown, in hundredths: its column grows with it.
    @ScaledMetric(relativeTo: .caption) private var grown: CGFloat = 100

    var body: some View {
        // At the largest sizes a column for the name leaves the field too
        // little of the row: the name stands over it instead.
        if size.isAccessibilitySize || TypeScale.shared.crowded {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).engineLabel().foregroundStyle(Theme.muted)
                field
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).engineLabel().foregroundStyle(Theme.muted)
                    .frame(width: labelWidth * grown / 100 * TypeScale.shared.factor, alignment: .leading)
                field
            }
        }
    }

    private var field: some View {
        TextField("", text: $text, prompt: Text(verbatim: prompt).foregroundStyle(Theme.muted))
            .font(mono ? .mono(15, bold: false) : .ui(16))
            .foregroundStyle(Theme.ink)
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
                .textCase(Theme.voiceCase)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                // Large type fills the row: the words keep off the round ends.
                .padding(.horizontal, 18)
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
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        // At the largest sizes the choice would be cut short beside its
        // name: it stands under it, and may take a second line.
        if size.isAccessibilitySize || TypeScale.shared.crowded {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).engineLabel().foregroundStyle(Theme.muted)
                choice(lines: 2)
            }
        } else {
            HStack(spacing: 12) {
                Text(label).engineLabel().foregroundStyle(Theme.muted).fixedSize()
                Spacer(minLength: 8)
                choice(lines: 1)
            }
        }
    }

    private func choice(lines: Int) -> some View {
        Menu {
            Picker(label, selection: $selection) { options }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: chosen)
                    .font(.ui(15))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(lines)
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
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
    /// Where the caret is, for a form that puts something there itself --
    /// a picture's mark; a form that does not need it leaves it out.
    private var outer: Binding<TextSelection?>?
    var minHeight: CGFloat = 220
    @State private var whole = false
    @State private var inner: TextSelection?

    init(text: Binding<String>, selection: Binding<TextSelection?>? = nil, minHeight: CGFloat = 220) {
        _text = text
        outer = selection
        self.minHeight = minHeight
    }

    private var selection: Binding<TextSelection?> { outer ?? $inner }
    @Environment(\.pageHeight) private var pageHeight
    @Environment(\.keyboardTop) private var keyboardTop
    /// Where the text's own upper edge is on the screen.
    @State private var top: CGFloat = 0

    /// As tall as the text asks, up to what stays in sight: a text that
    /// grew on down the page took its caret behind the keyboard, and the
    /// page does not follow a caret. Past that height the text moves
    /// inside its own frame, which does. With a keyboard up the text has
    /// everything down to it -- what stands under the text, the tags, is
    /// not needed while writing; without one, half the page. For more room
    /// there is the whole screen, one key away.
    private var room: CGFloat {
        let half = (pageHeight * 0.5).rounded()
        guard let keyboardTop else { return max(180, half) }
        return min(max(180, (keyboardTop - top - 6).rounded()), max(180, pageHeight * 0.9))
    }

    var body: some View {
        EditorKeys(text: $text, selection: selection, symbol: "arrow.up.left.and.arrow.down.right",
                   label: String(localized: "editor.whole", defaultValue: "Write on the whole screen")) { whole = true }
        TextEditor(text: $text, selection: selection)
            .font(.mono(15, bold: false))
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden)
            .frame(minHeight: min(minHeight, room), maxHeight: room)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY.rounded() } action: { top = $0 }
            .padding(.horizontal, -5)
            .padding(.vertical, -4)
            .fullScreenCover(isPresented: $whole) { WritingScreen(text: $text) }
    }
}

extension TextSelection {
    /// The caret or the selection as the text view counts it, in UTF-16;
    /// nothing when it does not lie in this text any more.
    func range(in text: String) -> NSRange? {
        switch indices {
        case .selection(let picked):
            guard picked.lowerBound >= text.startIndex, picked.upperBound <= text.endIndex else { return nil }
            return NSRange(picked, in: text)
        case .multiSelection(let set):
            guard let first = set.ranges.first, first.upperBound <= text.endIndex else { return nil }
            return NSRange(first, in: text)
        @unknown default:
            return nil
        }
    }

    /// The caret at a UTF-16 offset of this text.
    init?(caret: Int, in text: String) {
        guard let at = Range(NSRange(location: caret, length: 0), in: text) else { return nil }
        self.init(insertionPoint: at.lowerBound)
    }
}

/// Nothing but the text: the marks over it, the paper under it, the
/// keyboard up. The text has the whole width of the screen or the window,
/// however wide: how long a line is, is the writer's to say, by the size
/// of the window.
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
        let range = selection?.range(in: text) ?? NSRange(location: whole, length: 0)
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
