import SwiftUI

/// How large the app sets its type: as the system has it, or one to four
/// steps above that. The device's own and not a blog's -- eyes do not
/// change with the blog -- and the only way to a larger type where the
/// system offers none, which is an iPad app on a Mac.
nonisolated enum TextSize: Int, CaseIterable, Identifiable, Sendable {
    case system, one, two, three, four

    /// Where the choice is kept.
    static let key = "textSize"

    var id: Int { rawValue }

    /// What is kept, read back; anything else is the system's size.
    init(kept: Int) { self = TextSize(rawValue: kept) ?? .system }

    /// The system's size moved up by the steps chosen, as far as its scale goes.
    func applied(to size: DynamicTypeSize) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        guard let at = all.firstIndex(of: size) else { return size }
        return all[min(at + rawValue, all.count - 1)]
    }

    /// How much a page of the blog is enlarged with it: the steps of the
    /// system's own scale, from its usual size.
    var zoom: CGFloat {
        switch self {
        case .system: 1
        case .one: 1.12
        case .two: 1.24
        case .three: 1.35
        case .four: 1.65
        }
    }

    /// The two letters that stand for it where it is chosen, in points.
    var sample: CGFloat {
        switch self {
        case .system: 14
        case .one: 16
        case .two: 18
        case .three: 21
        case .four: 25
        }
    }
}
