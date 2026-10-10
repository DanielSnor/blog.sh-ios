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
    @MainActor static var paper: Color { colour(\.bg) }
    /// What is written on it.
    @MainActor static var ink: Color { colour(\.text) }
    /// What is written beside it: tags, dates, hints.
    @MainActor static var muted: Color { colour(\.metaText) }
    /// A hairline: the edge of a card, the rule between two rows.
    @MainActor static var line: Color { colour(\.border) }
    /// What is out of reach, in every part of it: see `Shades.faded`.
    @MainActor static var faded: Color { colour(\.faded) }
    /// The inside of a card, barely off the ground.
    @MainActor static var card: Color { colour(\.text, lightAlpha: 0.03, darkAlpha: 0.05) }
    /// The one accent: every control of the app, its links, its counts.
    @MainActor static var accent: Color { colour(\.accent) }
    /// What cannot be taken back: a delete, a refusal. The one colour
    /// beside the accent, and never a fill.
    static let danger = dynamic(light: 0xC62800, dark: 0xFF7A5C)

    /// The engine's voice and the names of screens are set in lower case
    /// -- except in German, which reads its nouns by their capitals: there
    /// the words stand as they are written.
    static let voiceCase: Text.Case? = Bundle.main.preferredLocalizations.first == "de" ? nil : .lowercase

    static let corner: CGFloat = 14
    static let gutter: CGFloat = 20

    /// One of the worn colours, by day and by night.
    @MainActor private static func colour(_ part: KeyPath<Shades, UInt32>, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        colour(part, of: Look.shared.worn, lightAlpha: lightAlpha, darkAlpha: darkAlpha)
    }

    fileprivate static func colour(_ part: KeyPath<Shades, UInt32>, of colours: Colours, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        dynamic(light: colours.light[keyPath: part], dark: colours.dark[keyPath: part], lightAlpha: lightAlpha, darkAlpha: darkAlpha)
    }

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

/// The colours of a part of a screen that does not wear the worn ones:
/// the place the colours are chosen in keeps to the app's own once the
/// chosen ones cannot be read, so there is always a way back. Handed down
/// to the few pieces such a part is built of; everything else asks the
/// theme.
nonisolated struct Ground: Sendable {
    let paper: Color
    let ink: Color
    let muted: Color
    let line: Color
    let card: Color
    let accent: Color

    /// The app's own, whatever is worn.
    static let plain = Ground(paper: Theme.colour(\.bg, of: .own),
                              ink: Theme.colour(\.text, of: .own),
                              muted: Theme.colour(\.metaText, of: .own),
                              line: Theme.colour(\.border, of: .own),
                              card: Theme.colour(\.text, of: .own, lightAlpha: 0.03, darkAlpha: 0.05),
                              accent: Theme.colour(\.accent, of: .own))
}

extension EnvironmentValues {
    /// Nil wherever the worn colours are the ones to draw in.
    @Entry var ground: Ground? = nil
}

/// Whose colours the app wears, and the ones chosen here: the open
/// blog's -- its ground, its ink, its rules, its accent, as its pages have
/// them -- the app's own, or the ones somebody chose on this device,
/// colour by colour. The device's, not a blog's: eyes do not change with
/// the blog.
@Observable final class Look {
    static let shared = Look()

    var wearing: Colouring {
        didSet { UserDefaults.standard.set(wearing.rawValue, forKey: Colouring.key) }
    }
    /// The ones chosen here; nil until somebody chose.
    var chosen: Colours? {
        didSet { UserDefaults.standard.set(chosen?.kept, forKey: Colours.key) }
    }

    private init() {
        let defaults = UserDefaults.standard
        wearing = Colouring(kept: defaults.string(forKey: Colouring.key), switchedToOwn: defaults.bool(forKey: Colouring.switchKey))
        chosen = Colours(kept: defaults.data(forKey: Colours.key))
    }

    /// What the open blog said of itself.
    var blog: Colours {
        let blog = Blogs.shared.current
        return Colours.said(light: blog?.tonesLight, dark: blog?.tonesDark,
                            accentLight: blog?.accentLight ?? "", accentDark: blog?.accentDark ?? "")
    }

    /// The two schemes everything is drawn in now.
    var worn: Colours { Colours.worn(wearing, chosen: chosen, blog: blog) }

    /// Wears the chosen ones -- which, the first time, are the ones worn
    /// until then, so that choosing starts from a screen that reads.
    func wearChosen() {
        if chosen == nil { chosen = worn }
        wearing = .chosen
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

    /// A screen with room for longer steps: a tablet, and so a Mac too,
    /// which runs the tablet's app.
    static let wide = UIDevice.current.userInterfaceIdiom == .pad

    var size: TextSize {
        didSet { UserDefaults.standard.set(size.rawValue, forKey: TextSize.key) }
    }

    private init() {
        size = TextSize(kept: UserDefaults.standard.integer(forKey: TextSize.key))
    }

    /// How much larger every face is drawn by the app itself.
    var factor: CGFloat { Self.ownHand ? zoom : 1 }

    /// How much a page of the blog is enlarged, here.
    var zoom: CGFloat { size.zoom(wide: Self.wide) }

    /// Type so large that a name and its value no longer share a row --
    /// what the system calls an accessibility size where it has one.
    var crowded: Bool { Self.ownHand && zoom >= 1.65 }
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

/// The distance between two parts of a screen -- a section and the one
/// before it, a plate and its hint. It grows with the type: a gap that
/// tells two groups apart at the usual size is lost between lines twice
/// as tall, and a screen of large type reads as one unbroken column.
struct Gap: ViewModifier {
    private let points: CGFloat
    private let edge: Edge.Set
    @ScaledMetric private var grown: CGFloat

    init(_ points: CGFloat, _ edge: Edge.Set) {
        self.points = points
        self.edge = edge
        _grown = ScaledMetric(wrappedValue: points, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        // Where the app enlarges its type by its own hand, its gaps too.
        content.padding(edge, TypeScale.ownHand ? points * TypeScale.shared.factor : grown)
    }
}

extension View {
    func gap(_ points: CGFloat, _ edge: Edge.Set = .top) -> some View {
        modifier(Gap(points, edge))
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
            window.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(size.applied(to: system, wide: TypeScale.wide))
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
                        .font(.custom(Typeface.sans(.medium) ?? "Helvetica Neue", fixedSize: size.sample(wide: TypeScale.wide)))
                        .wordUnderPointer(chosen ? .white : Theme.ink, moves: !chosen)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(chosen ? Theme.accent : .clear)
                        .contentShape(Rectangle())
                        .underPointer()
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
    /// Something that wants looking at before it is lost sight of: the
    /// card stands on the colour of what cannot be taken back, thinned to
    /// a wash -- told apart at a glance from the cards that only report.
    var warning = false
    @ViewBuilder var content: Content
    @Environment(\.scale) private var scale
    @Environment(\.outOfReach) private var out

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: capsule ? 999 : Theme.corner * scale, style: .continuous)
        HStack(spacing: 10 * scale) { content }
            .padding(.horizontal, 13 * scale)
            .padding(.vertical, 12 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Out of reach: no fill, and the plain outline.
                if out { shape.fill(.clear) }
                else if warning { shape.fill(Theme.danger.opacity(0.10)) }
                else if highlighted { shape.fill(.tint.opacity(0.12)) }
                else { shape.fill(Theme.card) }
            }
            .overlay {
                if out { KeyOutline(shape: shape) }
                else if warning { shape.strokeBorder(Theme.danger.opacity(0.55), lineWidth: 1) }
                else if highlighted { shape.strokeBorder(.tint, lineWidth: 1) }
                else { KeyOutline(shape: shape) }
            }
            .contentShape(shape)
            .underPointer()
    }
}

/// How many: the number in the engine's voice and in ink. The accent on
/// such a card is its mark's; the number beside it is only a number, as
/// the counts beside the marks are on the blog's own pages.
struct CountBadge: View {
    let count: Int
    @Environment(\.scale) private var scale

    var body: some View {
        Text(verbatim: "\(count)")
            .font(.mono(13 * scale))
            .tone(Theme.ink)
            .padding(.horizontal, 4 * scale)
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
            // The chosen one is filled with the accent, as on the blog's
            // own pages; the others are a hairline and a muted word.
            .wordUnderPointer(selected ? .white : Theme.muted, moves: !selected)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background { if selected { Capsule().fill(.tint) } }
            .overlay { if selected { Capsule().strokeBorder(.tint, lineWidth: 1) } else { KeyOutline(shape: Capsule()) } }
            .contentShape(Capsule())
            .underPointer()
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
    func namedByItsHeader(name: String? = nil, count: String? = nil, title: String? = nil, symbol: String? = nil) -> some View {
        modifier(NamedInBar(name: name, count: count, title: title, symbol: symbol))
            .modifier(BackKeyInBar())
            .modifier(MenuKeyInBar())
    }

    /// A list on paper: no cards of the system's, no ground but ours.
    func paperList(name: String? = nil, count: String? = nil, symbol: String? = nil) -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .clearOfItsBar()
            .background(Theme.paper.ignoresSafeArea())
            .namedByItsHeader(name: name, count: count, symbol: symbol)
    }

    /// What scrolls ends where the bar begins, instead of running on
    /// under it: the screen's name is read over plain paper, not over the
    /// rows passing behind it -- which a bar of glass shows half, and a bar
    /// with no ground at all (an iPad app on a Mac) shows whole. A scroll
    /// view only runs under a bar it touches; a point's distance is enough.
    func clearOfItsBar() -> some View {
        padding(.top, 1)
            // With nothing running under it, the bar would put a ground of its own there.
            .toolbarBackground(.hidden, for: .navigationBar)
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
    /// The mark before the name, where the screen is one of the menu's.
    var symbol: String?
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
        .clearOfItsBar()
        .background(Theme.paper.ignoresSafeArea())
        .namedByItsHeader(name: name, count: count, title: title, symbol: symbol)
    }
}

/// The screen's name in its bar. The bar measures its middle once and
/// keeps what it measured: a screen that grew wider -- the menu beside it
/// put away, its window pulled out -- had its name left at the old width
/// and set in the middle of the new, away from the way back. So the name
/// is told how wide its screen is, and asks anew whenever that changes.
private struct NamedInBar: ViewModifier {
    let name: String?
    let count: String?
    let title: String?
    let symbol: String?
    @State private var room: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BarName(name: name, count: count, title: title, symbol: symbol, room: room)
                }
            }
    }
}

/// What stands in a bar where the system would put its title: the
/// screen's name, or a post's. It takes all the room between the way
/// back and whatever keys stand at the far end, and starts at the near
/// edge of it.
///
/// A post's title is somebody's own words and can be long: the bar has
/// one line for it, at one size on every screen, and cuts what does not
/// fit at its end. The whole of it stands on the page under the bar, in
/// a field of its own (`TitleField`).
struct BarName: View {
    var name: String?
    var count: String?
    var title: String?
    /// The mark of the tile the screen was opened from, before its name:
    /// the six screens of the menu wear the mark they are known by there.
    var symbol: String?
    /// How wide the screen under the bar is. Nothing is drawn by it: it
    /// only makes what the name asks for differ from one width to the
    /// next, which is what has the bar measure it again.
    var room: CGFloat = 0

    var body: some View {
        Group {
            if let title, !title.isEmpty {
                Text(verbatim: title)
                    .font(.ui(18, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.ink)
            } else if let name, !name.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let symbol {
                        // In ink, as the name is: here the mark is a part of
                        // what the screen is called, not a key. The accent
                        // in a bar is for the keys beside it.
                        Image(systemName: symbol)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: name)
                        .font(.display(21))
                        .textCase(Theme.voiceCase)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let count {
                        // How many is said small and grey: the accent is
                        // for the thing itself, where a screen names one.
                        Text(verbatim: count)
                            .font(.mono(12))
                            .foregroundStyle(Theme.muted)
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
        .frame(idealWidth: 4000 + room.rounded(), maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// What a post is, as its row in a list knew it, the first thing on a
/// screen about it and one table: its whole title, however long -- the
/// bar over the screen has one line for it; what the engine calls it;
/// what state it is in, and since or until when; its tags, or its type
/// where it has none. A row with nothing to say is not drawn: a post
/// without a title has no first row.
struct PostFacts: View {
    let post: PostRow

    var body: some View {
        Plate {
            InfoRow(label: "Title", value: post.title)
            InfoRow(label: "slug", value: post.slug, mono: true)
            if post.scheduled {
                InfoRow(label: "scheduled", value: when)
            } else {
                InfoRow(label: "state", value: state)
            }
            if post.tags.isEmpty {
                InfoRow(label: "type", value: post.type)
            } else {
                InfoRow(label: "tags", value: post.tags.joined(separator: ", "))
            }
        }
        .padding(.top, 4)
    }

    /// The day and the hour, in the blog's own zone said out: the phone may be abroad.
    private var when: String? {
        guard let date = post.date.flatMap({ ISO8601DateFormatter.engine.date(from: $0) }) else { return post.date }
        return date.formatted(.dateTime.year().month().day().hour().minute().timeZone())
    }

    /// In the words the properties screen has for it.
    private var state: String {
        guard post.state == .published else { return String(localized: "saved.draft", defaultValue: "draft") }
        guard let when else { return String(localized: "saved.published", defaultValue: "published") }
        return String(localized: "published, \(when)") + (post.pinned ? " · " + String(localized: "browse.state.pinned", defaultValue: "pinned") : "")
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
    @Environment(\.ground) private var ground

    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim: String) { text = Text(verbatim: verbatim) }

    var body: some View {
        // The name of a section is in the accent, as the names of the
        // boxes are on the blog's own pages; the names of the rows inside
        // a plate stay muted -- those are fields, not sections.
        text.engineLabel()
            .foregroundStyle(ground?.accent ?? Theme.accent)
            .gap(22)
            .gap(8, .bottom)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A word of explanation under a plate.
struct Hint: View {
    let text: Text
    @Environment(\.ground) private var ground

    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim: String) { text = Text(verbatim: verbatim) }

    var body: some View {
        text.font(.ui(13))
            .foregroundStyle(ground?.muted ?? Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .gap(8)
    }
}

extension View {
    /// What the server would have to answer for, while the server is
    /// silent: drawn without its colour and faint, and deaf to a tap.
    func outOfReach(_ out: Bool) -> some View {
        modifier(OutOfReach(out: out))
    }

    /// A colour of this thing's own -- which it gives up when it is out
    /// of reach, for the one tone everything out of reach is drawn in.
    func tone(_ colour: Color) -> some View {
        modifier(Tone(colour: colour))
    }
}

extension EnvironmentValues {
    /// This is part of something that cannot be used just now.
    @Entry var outOfReach = false
}

/// The state "out of reach": the thing keeps its place and its outline
/// and goes quiet. Everything in it is drawn in one tone -- the accent
/// says "a key", and what cannot be pressed does not wear it -- it has no
/// fill, and it answers to nothing. Never done by making the whole thing
/// transparent: that fades a fill, an outline and a picture each its own
/// way, and comes out differently over every ground.
private struct OutOfReach: ViewModifier {
    let out: Bool

    func body(content: Content) -> some View {
        if out {
            content
                .disabled(true)
                .tint(Theme.faded)
                .environment(\.outOfReach, true)
        } else {
            content
        }
    }
}

private struct Tone: ViewModifier {
    let colour: Color
    @Environment(\.outOfReach) private var out

    func body(content: Content) -> some View {
        content.foregroundStyle(out ? Theme.faded : colour)
    }
}

/// What is being written on this device, as far as the first screen
/// needs to know: that it changed, so the list of things begun is read again.
@Observable final class Desk {
    static let shared = Desk()
    private(set) var changes = 0
    func changed() { changes += 1 }

    /// A post that waited to be sent, taken back to be written on: held
    /// here on its way to the form, which takes it when it opens.
    @ObservationIgnored private var handed: Waiting?
    func hand(_ post: Waiting) { handed = post }
    var holdsHanded: Bool { handed != nil }
    func takeHanded() -> Waiting? {
        defer { handed = nil }
        return handed
    }

    /// The blogs whose new post is on its way just now. The form is left
    /// alone while its post goes: what is typed into it then would belong
    /// to neither the post that went nor the next one.
    private(set) var sending: Set<UUID> = []
    /// Counted when a new post has arrived, and for which blog: a form
    /// opened meanwhile holds the post that went, and lets go of it.
    private(set) var arrived = 0
    private(set) var arrivedAt: UUID?

    /// Counted when a command that changes the blog has answered -- a
    /// publish, a move in the queue, a delivery: what the first screen
    /// says of the blog is read again, also where that screen is beside
    /// the one that made the change and nobody "comes back" to it.
    private(set) var writes = 0
    func wrote() { writes += 1 }

    func began(_ blog: UUID) { sending.insert(blog) }
    func ended(_ blog: UUID, arrived came: Bool) {
        sending.remove(blog)
        guard came else { return }
        arrivedAt = blog
        arrived += 1
    }
}

extension Unsaved {
    /// What the screen says of changes it brought back: when they were
    /// written, that the post has moved on under them where it has, and
    /// that pictures chosen for them have to be chosen again.
    @MainActor static func words(_ kept: Unsaved, over base: String, media: [String]?) -> Text {
        var words = Text("Back in the editor: the changes written here \(kept.at.spoken) and not saved.")
        if kept.base != base {
            words = words + Text(verbatim: " ") + Text("The post has changed on the blog since; saving puts this text in its place.")
        }
        if let media, kept.namesPictures(beyond: media) {
            words = words + Text(verbatim: " ") + Text("Its pictures were not kept; add them again.")
        }
        return words
    }
}

extension EnvironmentValues {
    /// Brings the menu back beside the open screen, where it was put out
    /// of the way and there is room for both; nil everywhere else.
    @Entry var showMenu: (@MainActor () -> Void)? = nil
}

/// The key that shows and hides the menu's column on a wide screen, in
/// the accent like every other key of the app: the system's own stands in
/// the bar in ink, as if it were not one of them.
struct MenuKey: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "sidebar.left") }
            .tint(Theme.accent)
            .accessibilityLabel(Text("Show or hide the menu"))
    }
}

/// The way back, in the accent like every other key. The system's own
/// arrow stands in the bar in ink and takes no colour from anybody -- not
/// from the app's tint, not from the window's, not from the bar's -- so
/// it is taken out and the app's own key put in its place, wherever
/// there is something to go back to.
private struct BackKeyInBar: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @State private var deeper = false

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .background(StackPlace(deeper: $deeper))
            .toolbar {
                if deeper {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "chevron.backward") }
                            .tint(Theme.accent)
                            .accessibilityLabel(Text("Back"))
                    }
                }
            }
    }
}

/// Where a screen stands in its stack: on something, or at its foot.
/// SwiftUI does not say; the stack under it does.
private struct StackPlace: UIViewControllerRepresentable {
    @Binding var deeper: Bool

    func makeUIViewController(context: Context) -> Probe { Probe() }

    func updateUIViewController(_ probe: Probe, context: Context) {
        probe.report = { now in if deeper != now { deeper = now } }
        probe.look()
    }

    final class Probe: UIViewController {
        var report: ((Bool) -> Void)?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            look()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            look()
        }

        func look() {
            guard let stack = navigationController else { return }
            // Which of the stack's screens holds this one.
            var holder: UIViewController? = self
            while let one = holder, !stack.viewControllers.contains(one) { holder = one.parent }
            guard let holder, let at = stack.viewControllers.firstIndex(of: holder) else { return }
            // On a phone the open screen's own stack stands on the menu's:
            // its first screen has the menu to go back to.
            let deeper = at > 0 || stack.navigationController != nil
            // With the system's arrow gone, its swipe would go with it.
            for one in [stack, stack.navigationController].compactMap({ $0 }) {
                one.interactivePopGestureRecognizer?.delegate = SwipeBack.shared
                one.interactivePopGestureRecognizer?.isEnabled = true
            }
            DispatchQueue.main.async { [weak self] in self?.report?(deeper) }
        }
    }
}

/// Lets the swipe from the edge go back wherever there is a screen to go
/// back to -- which the system stops asking once its own arrow is hidden.
private final class SwipeBack: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBack()

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        var responder: UIResponder? = recognizer.view
        while let one = responder {
            if let stack = one as? UINavigationController { return stack.viewControllers.count > 1 }
            responder = one.next
        }
        return false
    }
}

/// On a screen whose menu was put out of the way, the key that brings it back.
private struct MenuKeyInBar: ViewModifier {
    @Environment(\.showMenu) private var showMenu

    func body(content: Content) -> some View {
        content.toolbar {
            if let showMenu {
                ToolbarItem(placement: .topBarLeading) { MenuKey(action: showMenu) }
            }
        }
    }
}

/// Said at the head of a form that opened with something in it nobody
/// typed just now: writing that was kept from the last time, brought
/// back -- and the one key that puts it away again.
struct BroughtBack: View {
    let words: Text
    let key: LocalizedStringKey
    let putAway: () -> Void

    var body: some View {
        Plate {
            words
                .font(.ui(14))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Command(key, symbol: "xmark", danger: true, action: putAway)
        }
    }
}

/// Changes kept on the device whose post could not be opened -- it was
/// renamed or deleted elsewhere, or the blog cannot be reached. They are
/// shown, to be read and copied, with the one key that lets go of them;
/// without it they would wait on the first screen for good.
struct Stranded: View {
    let kept: Unsaved
    let discard: () -> Void
    @State private var confirming = false

    var body: some View {
        Hint("Written here \(kept.at.spoken) and never saved; the post itself could not be opened. The words are below, to copy.")
            .gap(14)
        Plate {
            Text(verbatim: kept.text)
                .font(.mono(14, bold: false))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        Plate {
            Command("Throw away", symbol: "trash", danger: true) { confirming = true }
                .confirmationDialog("Throw these changes away? They were never saved; nothing of them is kept.",
                                    isPresented: $confirming, titleVisibility: .visible) {
                    Button("Throw away", role: .destructive, action: discard)
                }
        }
        .gap(14)
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
            .gap(10)
            .textSelection(.enabled)
    }
}

/// Several rows that belong together, on one card: a hairline around
/// them and one between each two. A row that draws nothing takes no
/// place and leaves no rule behind.
struct Plate<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.ground) private var ground

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
        let line = ground?.line ?? Theme.line
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        Rectangle().fill(line).frame(height: 1)
                    }
                    row.padding(.horizontal, PlateRow.side)
                        .padding(.vertical, PlateRow.above)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(shape.fill(ground?.card ?? Theme.card))
        .overlay(shape.strokeBorder(line, lineWidth: 1))
        .clipShape(shape)
    }
}

// MARK: - Under the pointer

extension EnvironmentValues {
    /// The pointer is over the key this view is a part of.
    @Entry var underPointer = false
}

/// A key says that the pointer is over it: its outline and its word go
/// into the accent, as on the blog's own pages -- where something filled
/// keeps its fill, and the title of a post in a list stays as it is. Only
/// where there is a pointer: a Mac, a tablet with a mouse.
private struct UnderPointer: ViewModifier {
    @State private var over = false

    func body(content: Content) -> some View {
        content
            .environment(\.underPointer, over)
            .onHover { over = $0 }
    }
}

/// The hairline around a key: the rules' colour, the accent under the pointer.
struct KeyOutline<S: InsettableShape>: View {
    let shape: S
    @Environment(\.underPointer) private var over
    @Environment(\.outOfReach) private var out

    var body: some View {
        // Out of reach it answers to nothing, the pointer included.
        shape.strokeBorder(over && !out ? Theme.accent : Theme.line, lineWidth: 1)
    }
}

private struct WordUnderPointer: ViewModifier {
    let rest: Color
    let moves: Bool
    @Environment(\.underPointer) private var over
    @Environment(\.outOfReach) private var out

    func body(content: Content) -> some View {
        content.foregroundStyle(out ? Theme.faded : (over && moves ? Theme.accent : rest))
    }
}

extension View {
    /// This is a key: what it is made of may answer to the pointer.
    func underPointer() -> some View { modifier(UnderPointer()) }

    /// A key's word, in its own colour until the pointer is over the key.
    func wordUnderPointer(_ rest: Color, moves: Bool = true) -> some View {
        modifier(WordUnderPointer(rest: rest, moves: moves))
    }
}

/// The room a plate leaves around each of its rows.
nonisolated enum PlateRow {
    static let side: CGFloat = 13
    static let above: CGFloat = 12
}

/// A row of a plate that says "done": the thing a key was for has just
/// happened. Filled with the accent from one edge of the plate to the
/// other, as a link that was copied is on the blog's own pages, and
/// gone again when the key is a key once more.
struct DoneRow: View {
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 22)
            Text(label).font(.ui(15, weight: .medium))
            Spacer(minLength: 6)
        }
        .foregroundStyle(.white)
        // Out to the plate's own edges: the fill is the row, not a box in it.
        .background(Theme.accent.padding(.horizontal, -PlateRow.side).padding(.vertical, -PlateRow.above))
        .accessibilityElement(children: .combine)
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
        // A row that cannot be pressed just now is out of reach like any
        // other key: one tone, and no making it transparent. (What is put
        // out of reach is disabled with it, so the one question covers both.)
        let quiet = !enabled
        HStack(spacing: 11) {
            Group {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 16))
                        .foregroundStyle(quiet ? AnyShapeStyle(Theme.faded) : (danger ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(.tint)))
                }
            }
            .frame(width: 22)
            label.font(.ui(15, weight: .medium))
                .wordUnderPointer(danger ? Theme.danger : Theme.ink, moves: !danger)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 6)
            if leads {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .tone(Theme.muted)
            }
        }
        .environment(\.outOfReach, quiet)
        .contentShape(Rectangle())
        .underPointer()
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
                .foregroundStyle(enabled ? Color.white : Theme.faded)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                // Large type fills the row: the words keep off the round ends.
                .padding(.horizontal, 18)
                // Out of reach it gives up its fill, as everything out of
                // reach does, and keeps its shape as an outline in the one
                // tone: never the filled key made transparent.
                .background { if enabled { Capsule().fill(.tint) } }
                .overlay { if !enabled { Capsule().strokeBorder(Theme.faded, lineWidth: 1) } }
                .opacity(enabled && configuration.isPressed ? 0.7 : 1)
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
            // The words are the switch as much as the switch is: a tap
            // anywhere on the row turns it, not only one on its far end.
            Group {
                if property {
                    Text(label).engineLabel().foregroundStyle(Theme.muted)
                } else {
                    Text(label).font(.ui(15)).foregroundStyle(Theme.ink)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 31, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { isOn.toggle() }
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
        // Keys, so in the accent like every other key.
        .foregroundStyle(.tint)
        .frame(width: 34, height: 30)
        .overlay(KeyOutline(shape: shape))
        .contentShape(shape)
        .underPointer()
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
                .gap(8)
        }
        Hint("A picture is shrunk to \(String(Pictures.maxEdge)) px on its long edge before it goes; a video is converted to H.264 at 720p. The whole post -- text, pictures, video -- has to stay under \(maxMb) MB, the server's limit, and the limit is measured on the encoded transfer, a third larger than the files: the files themselves get about \(Int(Double(maxMb) * 0.73)) MB.")
    }
}


/// The label of the one filled button, with a spinner while it works.
struct PrimaryLabel: View {
    let label: LocalizedStringKey
    var busy = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 8) {
            // The wheel in the words' own colour: white on the fill, the
            // faded tone on the outline the key is while it works.
            if busy { ProgressView().controlSize(.small).tint(enabled ? Color.white : Theme.faded) }
            Text(label)
        }
    }
}
