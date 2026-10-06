import Testing
import SwiftUI
@testable import blogsh

/// The size of the type chosen in the settings. A mistake here is type
/// that grows the wrong way, or a kept choice that no longer reads.
@Suite struct TextSizeTests {
    @Test func theSystemsSizeIsLeftAsItIs() {
        for size in DynamicTypeSize.allCases {
            #expect(TextSize.system.applied(to: size) == size)
        }
    }

    @Test func eachStepIsOneOfTheSystemsOwn() {
        #expect(TextSize.one.applied(to: .large) == .xLarge)
        #expect(TextSize.two.applied(to: .large) == .xxLarge)
        #expect(TextSize.three.applied(to: .large) == .xxxLarge)
        #expect(TextSize.four.applied(to: .large) == .accessibility1)
    }

    /// The steps stand on what the system has, not on its usual size:
    /// somebody who already reads large gets larger, never smaller.
    @Test func theStepsStartFromTheSystemsSize() {
        #expect(TextSize.one.applied(to: .xxLarge) == .xxxLarge)
        #expect(TextSize.two.applied(to: .small) == .large)
        for size in DynamicTypeSize.allCases {
            for step in TextSize.allCases {
                #expect(step.applied(to: size) >= size)
            }
        }
    }

    @Test func theScaleEndsWhereTheSystemsDoes() {
        #expect(TextSize.four.applied(to: .accessibility4) == .accessibility5)
        #expect(TextSize.four.applied(to: .accessibility5) == .accessibility5)
    }

    @Test func aChoiceThatIsNotOneIsTheSystems() {
        #expect(TextSize(kept: 0) == .system)
        #expect(TextSize(kept: 4) == .four)
        #expect(TextSize(kept: 5) == .system)
        #expect(TextSize(kept: -1) == .system)
    }

    /// A page of the blog and the letters in the picker grow with the steps.
    @Test func everyStepIsLargerThanTheOneBefore() {
        let all = TextSize.allCases
        #expect(TextSize.system.zoom == 1)
        for (smaller, larger) in zip(all, all.dropFirst()) {
            #expect(smaller.zoom < larger.zoom)
            #expect(smaller.sample < larger.sample)
        }
    }
}
