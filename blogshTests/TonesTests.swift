import Testing
@testable import blogsh

/// The colours a blog says and the ones the app wears. A mistake here is
/// a screen in half a palette, or one that cannot be read at all.
@Suite struct TonesTests {
    private let cream = Tones(bg: "#fff7eb", text: "#1e1d1c", metaText: "#6b6862", border: "#d7d0c6")
    private let night = Tones(bg: "#000000", text: "#e6dccb", metaText: "#a1988a", border: "#3c3935")

    @Test func aColourIsReadTheWayAPaletteWritesIt() {
        #expect(Tones.value("#fff7eb") == 0xFFF7EB)
        #expect(Tones.value("#FFF7EB") == 0xFFF7EB)
        #expect(Tones.value(" #000000 ") == 0)
        #expect(Tones.value("#fc0") == 0xFFCC00)
    }

    @Test func whatIsNotAColourIsNone() {
        #expect(Tones.value("fff7eb") == nil)
        #expect(Tones.value("#fff7e") == nil)
        #expect(Tones.value("#gggggg") == nil)
        #expect(Tones.value("red") == nil)
        #expect(Tones.value("rgb(1, 2, 3)") == nil)
        #expect(Tones.value("") == nil)
    }

    @Test func aPaletteReadsWholeOrNotAtAll() {
        #expect(cream.values?.bg == 0xFFF7EB)
        #expect(cream.values?.text == 0x1E1D1C)
        #expect(cream.values?.metaText == 0x6B6862)
        #expect(cream.values?.border == 0xD7D0C6)
        var broken = cream
        broken.border = "papayawhip"
        #expect(broken.values == nil)
    }

    @Test func theBlogsPaletteIsWornWhenItHasSaidBothSchemes() {
        let worn = Tones.worn(own: false, light: cream, dark: night)
        #expect(worn.light.bg == 0xFFF7EB)
        #expect(worn.dark.text == 0xE6DCCB)
    }

    /// Half a palette is none: a cream day with the app's own night would
    /// be two looks in one app.
    @Test func withoutBothSchemesTheAppWearsItsOwn() {
        for worn in [Tones.worn(own: false, light: nil, dark: nil),
                     Tones.worn(own: false, light: cream, dark: nil),
                     Tones.worn(own: false, light: nil, dark: night)] {
            #expect(worn.light == Tones.ownLight)
            #expect(worn.dark == Tones.ownDark)
        }
        var broken = night
        broken.bg = "black"
        let worn = Tones.worn(own: false, light: cream, dark: broken)
        #expect(worn.light == Tones.ownLight)
        #expect(worn.dark == Tones.ownDark)
    }

    @Test func askedToKeepToItsOwnTheAppDoesWhateverTheBlogSaid() {
        let worn = Tones.worn(own: true, light: cream, dark: night)
        #expect(worn.light == Tones.ownLight)
        #expect(worn.dark == Tones.ownDark)
    }

    /// The app's own is the palette the engine ships with, to the last hex.
    @Test func theAppsOwnIsTheEnginesShippedPalette() {
        #expect(Tones.ownLight == (0xF5F8FA, 0x444A5A, 0x657784, 0xE1E8ED))
        #expect(Tones.ownDark == (0x111111, 0xFFFFFF, 0x6A7F8C, 0x263340))
        #expect(Tones.ownAccent == (0x1DA1F2, 0x4AB3F4))
    }
}
