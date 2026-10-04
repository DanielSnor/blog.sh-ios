import UIKit

/// The icon on the home screen with its cursor in the open blog's accent.
/// An icon cannot be drawn while the app runs: the system only lets an app
/// choose among the icons it was built with. So the catalog holds the icon
/// in thirty-six hues, ten degrees apart (`AppIcon-h000` ... `AppIcon-h350`),
/// and the one nearest the accent is chosen. An accent without a colour of
/// its own -- a grey, a black -- leaves the icon as it was built.
enum AppIcon {
    /// The catalog's name for the icon nearest this accent, nil for the built-in one.
    static func name(for hex: String) -> String? {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        guard digits.hasPrefix("#") else { return nil }
        digits.removeFirst()
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        let color = UIColor(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                            blue: CGFloat(value & 0xff) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil),
              saturation >= 0.25, brightness >= 0.25 else { return nil }
        let step = Int((hue * 36).rounded()) % 36
        return String(format: "AppIcon-h%03d", step * 10)
    }

    /// Changes the icon when the accent asks for another one. The system
    /// tells the person it did; that notice is its own and cannot be kept
    /// back, so the icon is only touched when it would really change. A
    /// blog that has not said its accent yet leaves the icon alone.
    static func follow(_ hex: String) {
        guard !hex.isEmpty else { return }
        let app = UIApplication.shared
        let wanted = name(for: hex)
        guard app.supportsAlternateIcons, app.alternateIconName != wanted else { return }
        app.setAlternateIconName(wanted) { _ in }
    }
}
