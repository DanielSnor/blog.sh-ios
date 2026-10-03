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

    static let display: String? = UIFont.fontNames(forFamilyName: "Forum").first
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
        return .system(size: size, weight: .regular, design: .serif)
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

/// A row of its own on the ground: a hairline around, a large corner.
struct Card<Content: View>: View {
    var highlighted = false
    var capsule = false
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: capsule ? 999 : Theme.corner, style: .continuous)
        HStack(spacing: 10) { content }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { if highlighted { shape.fill(.tint.opacity(0.12)) } else { shape.fill(Theme.card) } }
            .overlay { if highlighted { shape.strokeBorder(.tint, lineWidth: 1) } else { shape.strokeBorder(Theme.line, lineWidth: 1) } }
            .contentShape(shape)
    }
}

/// How many: the accent, filled, with the number in the engine's voice.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: "\(count)")
            .font(.mono(12))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
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
                .font(.display(34))
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
    /// A list on paper: no cards of the system's, no ground but ours, and
    /// the screen's name said by its header rather than by the bar.
    func paperList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
            }
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
