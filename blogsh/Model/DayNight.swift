import Foundation

/// Whether the app is read on its day ground or its night ground: as the
/// system has it -- light by day, dark by night, or whichever the device
/// was set to stay in -- or held to one of the two, whatever the system
/// says. Chosen in the settings; the settings draw the choice and the
/// window wears it, this only keeps what was chosen.
nonisolated enum DayNight: Int, CaseIterable, Identifiable, Sendable {
    case system, day, night

    /// Where the choice is kept.
    static let key = "dayNight"

    var id: Int { rawValue }

    /// What is kept, read back; anything else is the system's own.
    init(kept: Int) { self = DayNight(rawValue: kept) ?? .system }
}
