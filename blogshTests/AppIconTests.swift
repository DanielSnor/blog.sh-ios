import Testing
@testable import blogsh

/// The icon nearest a blog's accent, of the thirty-six the app is built with.
@Suite struct AppIconTests {
    @Test func aBlueAccentTakesTheBlueIcon() {
        #expect(AppIcon.name(for: "#1da1f2") == "AppIcon-h200")
    }

    @Test func anOrangeAccentTakesTheOrangeIcon() {
        #expect(AppIcon.name(for: "#FF5A00") == "AppIcon-h020")
    }

    @Test func aShortHexIsTheSameColour() {
        #expect(AppIcon.name(for: "#f00") == "AppIcon-h000")
        #expect(AppIcon.name(for: "#ff0000") == "AppIcon-h000")
    }

    /// The circle of hues closes: a red just under 360 degrees is the red at 0.
    @Test func aHueAtTheEndOfTheCircleWrapsToItsStart() {
        #expect(AppIcon.name(for: "#ff0010") == "AppIcon-h000")
    }

    @Test func everyNameIsOneTheCatalogHas() {
        let hexes = ["#ff0000", "#ff8800", "#ffff00", "#00ff00", "#00ffff", "#0000ff", "#ff00ff", "#3366cc", "#cc3366"]
        for hex in hexes {
            let name = AppIcon.name(for: hex)
            let degrees = name.flatMap { Int($0.dropFirst("AppIcon-h".count)) }
            #expect(degrees != nil && degrees! % 10 == 0 && (0..<360).contains(degrees!), "\(hex) gave \(name ?? "nil")")
        }
    }

    /// A grey or a near-black has no hue to follow: the icon stays as built.
    @Test func anAccentWithoutColourLeavesTheIcon() {
        #expect(AppIcon.name(for: "#888888") == nil)
        #expect(AppIcon.name(for: "#101010") == nil)
        #expect(AppIcon.name(for: "#ffffff") == nil)
    }

    @Test func whatIsNotAHexColourLeavesTheIcon() {
        #expect(AppIcon.name(for: "") == nil)
        #expect(AppIcon.name(for: "blue") == nil)
        #expect(AppIcon.name(for: "rgb(1, 2, 3)") == nil)
        #expect(AppIcon.name(for: "#12345") == nil)
    }
}
