import Foundation

/// Whose colours the app wears: the open blog's, the app's own -- the
/// same whatever a blog chose, for eyes a blog's palette does not serve --
/// or the ones chosen on this device, colour by colour.
nonisolated enum Colouring: String, CaseIterable, Identifiable, Sendable {
    case blog, own, chosen

    /// Where the choice is kept, and where it was kept while it was a
    /// switch between the first two.
    static let key = "colours"
    static let switchKey = "ownColours"

    var id: String { rawValue }

    /// What is kept, read back: the word, or -- from before there were
    /// three -- the switch that stood for the second.
    init(kept: String?, switchedToOwn: Bool) {
        self = kept.flatMap(Colouring.init(rawValue:)) ?? (switchedToOwn ? .own : .blog)
    }
}

/// The colours of one scheme, as numbers: the ground, what is written on
/// it, what is written beside it, its rules, and the accent.
nonisolated struct Shades: Codable, Equatable, Sendable {
    var bg: UInt32
    var text: UInt32
    var metaText: UInt32
    var border: UInt32
    var accent: UInt32

    init(_ scheme: Tones.Scheme, accent: UInt32) {
        bg = scheme.bg
        text = scheme.text
        metaText = scheme.metaText
        border = scheme.border
        self.accent = accent
    }

    /// One of the five, by what it is for: a row of the table they are chosen in.
    enum Part: CaseIterable, Identifiable, Sendable {
        case bg, text, metaText, border, accent

        var id: Self { self }

        var path: WritableKeyPath<Shades, UInt32> {
            switch self {
            case .bg: \.bg
            case .text: \.text
            case .metaText: \.metaText
            case .border: \.border
            case .accent: \.accent
            }
        }
    }

    /// What is out of reach is written in: the ink mixed with the ground,
    /// 45 to 55. One tone for everything such a thing is made of -- its
    /// mark, its word, its number -- between the muted tone and a hairline.
    var faded: UInt32 {
        func mixed(_ shift: UInt32) -> UInt32 {
            let ink = Double((text >> shift) & 0xff), ground = Double((bg >> shift) & 0xff)
            return UInt32((ink * 0.45 + ground * 0.55).rounded())
        }
        return mixed(16) << 16 | mixed(8) << 8 | mixed(0)
    }

    /// How far what is written stands from what it is written on: the
    /// ratio of their luminances, from one (the same colour) to twenty-one
    /// (black on white).
    var contrast: Double {
        let (a, b) = (Self.luminance(text), Self.luminance(bg))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The writing can be told from the ground at all. Not a verdict on a
    /// palette -- the ratio is a poor judge of that -- only the line under
    /// which a screen cannot be read to be put right.
    var legible: Bool { contrast >= 1.5 }

    private static func luminance(_ value: UInt32) -> Double {
        func linear(_ part: UInt32) -> Double {
            let c = Double(part & 0xff) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(value >> 16) + 0.7152 * linear(value >> 8) + 0.0722 * linear(value)
    }
}

/// The two schemes the app is drawn in, by day and by night.
nonisolated struct Colours: Codable, Equatable, Sendable {
    var light: Shades
    var dark: Shades

    /// Where the ones chosen on this device are kept.
    static let key = "chosenColours"

    /// The app's own: the palette the engine ships with.
    static let own = Colours(light: Shades(Tones.ownLight, accent: Tones.ownAccent.light),
                             dark: Shades(Tones.ownDark, accent: Tones.ownAccent.dark))

    /// What a blog said of itself: its palette where it said both schemes
    /// and both read whole, its accents where each is a colour -- and the
    /// app's own for whatever it did not say.
    static func said(light: Tones?, dark: Tones?, accentLight: String, accentDark: String) -> Colours {
        let tones = Tones.worn(own: false, light: light, dark: dark)
        return Colours(light: Shades(tones.light, accent: Tones.value(accentLight) ?? Tones.ownAccent.light),
                       dark: Shades(tones.dark, accent: Tones.value(accentDark) ?? Tones.ownAccent.dark))
    }

    /// What is worn: by the choice, and with nothing chosen yet, the blog's.
    static func worn(_ wearing: Colouring, chosen: Colours?, blog: Colours) -> Colours {
        switch wearing {
        case .blog: blog
        case .own: own
        case .chosen: chosen ?? blog
        }
    }

    /// What is kept, read back; anything else is nothing chosen.
    init?(kept: Data?) {
        guard let kept, let colours = try? JSONDecoder().decode(Colours.self, from: kept) else { return nil }
        self = colours
    }

    init(light: Shades, dark: Shades) {
        self.light = light
        self.dark = dark
    }

    var kept: Data? { try? JSONEncoder().encode(self) }
}
