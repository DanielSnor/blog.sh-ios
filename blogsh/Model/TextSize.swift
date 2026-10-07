import SwiftUI

/// How large the app sets its type: as the system has it, or one to four
/// steps above that. The device's own and not a blog's -- eyes do not
/// change with the blog -- and the only way to a larger type where the
/// system offers none, which is an iPad app on a Mac.
///
/// The steps are longer on a wide screen -- a tablet, a Mac -- than on a
/// phone: it is read from further away and has the room, so its last step
/// is a good deal past where a phone's ends.
nonisolated enum TextSize: Int, CaseIterable, Identifiable, Sendable {
    case system, one, two, three, four

    /// Where the choice is kept.
    static let key = "textSize"

    var id: Int { rawValue }

    /// What is kept, read back; anything else is the system's size.
    init(kept: Int) { self = TextSize(rawValue: kept) ?? .system }

    /// How many sizes of the system's own scale it stands above the
    /// system's: one after another on a phone, in longer strides on a
    /// wide screen.
    func strides(wide: Bool = false) -> Int {
        wide ? [0, 2, 4, 5, 6][rawValue] : rawValue
    }

    /// The system's size moved up by the steps chosen, as far as its scale goes.
    func applied(to size: DynamicTypeSize, wide: Bool = false) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        guard let at = all.firstIndex(of: size) else { return size }
        return all[min(at + strides(wide: wide), all.count - 1)]
    }

    /// How much a page of the blog is enlarged with it, and every face
    /// where the app sets its type by its own hand: what that many sizes
    /// of the system's scale come to, from its usual one.
    func zoom(wide: Bool = false) -> CGFloat {
        [1, 1.12, 1.24, 1.35, 1.65, 1.94, 2.35][strides(wide: wide)]
    }

    /// The two letters that stand for it where it is chosen, in points.
    func sample(wide: Bool = false) -> CGFloat {
        (wide ? [14, 18, 23, 27, 32] : [14, 16, 18, 21, 25])[rawValue]
    }
}
