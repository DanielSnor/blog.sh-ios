import Foundation
import Testing
@testable import blogsh

/// Whose colours the app wears, and the ones chosen on the device. A
/// mistake here is an app in somebody else's colours, or one that cannot
/// be read to be put right.
@Suite struct ColoursTests {
    private let cream = Tones(bg: "#fff7eb", text: "#1e1d1c", metaText: "#6b6862", border: "#d7d0c6")
    private let night = Tones(bg: "#000000", text: "#e6dccb", metaText: "#a1988a", border: "#3c3935")

    private var blog: Colours {
        Colours.said(light: cream, dark: night, accentLight: "#a81800", accentDark: "#ff7a5c")
    }

    @Test func theChoiceIsReadBackAndTheOldSwitchWithIt() {
        #expect(Colouring(kept: "chosen", switchedToOwn: false) == .chosen)
        #expect(Colouring(kept: "own", switchedToOwn: false) == .own)
        #expect(Colouring(kept: "blog", switchedToOwn: true) == .blog)
        // From before there were three: the switch, on or off.
        #expect(Colouring(kept: nil, switchedToOwn: true) == .own)
        #expect(Colouring(kept: nil, switchedToOwn: false) == .blog)
        #expect(Colouring(kept: "rainbow", switchedToOwn: false) == .blog)
    }

    @Test func aBlogSaysItsPaletteAndItsAccents() {
        #expect(blog.light.bg == 0xFFF7EB)
        #expect(blog.dark.text == 0xE6DCCB)
        #expect(blog.light.accent == 0xA81800)
        #expect(blog.dark.accent == 0xFF7A5C)
    }

    /// Each on its own, as before: a blog with an accent and no palette
    /// wears its accent on the app's ground, and the other way round.
    @Test func whatABlogDidNotSayIsTheAppsOwn() {
        let accentOnly = Colours.said(light: nil, dark: nil, accentLight: "#a81800", accentDark: "")
        #expect(accentOnly.light.bg == Tones.ownLight.bg)
        #expect(accentOnly.light.accent == 0xA81800)
        #expect(accentOnly.dark.accent == Tones.ownAccent.dark)
        let silent = Colours.said(light: nil, dark: nil, accentLight: "", accentDark: "teal")
        #expect(silent == Colours.own)
    }

    @Test func whatIsWornGoesByTheChoice() {
        var mine = Colours.own
        mine.light.bg = 0x123456
        #expect(Colours.worn(.blog, chosen: mine, blog: blog) == blog)
        #expect(Colours.worn(.own, chosen: mine, blog: blog) == Colours.own)
        #expect(Colours.worn(.chosen, chosen: mine, blog: blog) == mine)
        // Asked for the chosen ones before any were: the blog's.
        #expect(Colours.worn(.chosen, chosen: nil, blog: blog) == blog)
    }

    @Test func theChosenOnesAreKeptAndReadBack() {
        var mine = blog
        mine.dark[keyPath: Shades.Part.accent.path] = 0x00FF88
        #expect(Colours(kept: mine.kept) == mine)
        #expect(Colours(kept: nil) == nil)
        #expect(Colours(kept: Data("{}".utf8)) == nil)
        #expect(Colours(kept: Data("not json".utf8)) == nil)
    }

    @Test func everyPartOfASchemeIsOneOfItsFive() {
        var shades = Colours.own.light
        for (step, part) in Shades.Part.allCases.enumerated() {
            shades[keyPath: part.path] = UInt32(step + 1)
        }
        #expect([shades.bg, shades.text, shades.metaText, shades.border, shades.accent] == [1, 2, 3, 4, 5])
    }

    /// The line under which the settings themselves could not be read.
    @Test func writingThatCannotBeToldFromItsGroundIsNotLegible() {
        var shades = Colours.own.light
        #expect(shades.legible)
        #expect(Colours.own.dark.legible)
        shades.text = shades.bg
        #expect(shades.contrast == 1)
        #expect(!shades.legible)
        shades.bg = 0xFFFFFF
        shades.text = 0xF0F0F0
        #expect(!shades.legible)
        // Faint, and still there to be read.
        shades.text = 0x999999
        #expect(shades.legible)
        shades.bg = 0x000000
        shades.text = 0xFFFFFF
        #expect(abs(shades.contrast - 21) < 0.001)
    }
}
