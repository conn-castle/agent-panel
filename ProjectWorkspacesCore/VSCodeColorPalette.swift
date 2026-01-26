import Foundation

/// Typed errors for VS Code color customization derivation.
public enum VSCodeColorError: Error, Equatable, Sendable {
    case invalidHex(String)
}

/// Dictionary of VS Code theme color customizations.
public typealias VSCodeColorCustomizations = [String: String]

/// Builds VS Code color customizations from a project color.
public struct VSCodeColorPalette: Sendable {
    /// Creates a color palette builder.
    public init() {}

    /// Builds VS Code color customizations from a `#RRGGBB` base color.
    /// - Parameter colorHex: Base color in `#RRGGBB` format.
    /// - Returns: Customizations dictionary or a validation error.
    public func customizations(for colorHex: String) -> Result<VSCodeColorCustomizations, VSCodeColorError> {
        guard let baseColor = RGBColor(hex: colorHex) else {
            return .failure(.invalidHex(colorHex))
        }

        let titleActiveBg = baseColor
        let titleInactiveBg = baseColor.darkened(by: 0.35)
        let activityBg = baseColor.darkened(by: 0.15)
        let statusBg = baseColor.darkened(by: 0.20)
        let hoverBg: RGBColor
        if statusBg.foregroundColor() == .white {
            hoverBg = statusBg.lightened(by: 0.08)
        } else {
            hoverBg = statusBg.darkened(by: 0.08)
        }
        let badgeBg: RGBColor
        if activityBg.foregroundColor() == .white {
            badgeBg = baseColor.lightened(by: 0.25)
        } else {
            badgeBg = baseColor.darkened(by: 0.25)
        }

        let titleForeground = titleActiveBg.foregroundColor()
        let activityForeground = activityBg.foregroundColor()
        let badgeForeground = badgeBg.foregroundColor()
        let statusForeground = statusBg.foregroundColor()

        let customizations: VSCodeColorCustomizations = [
            "titleBar.activeBackground": titleActiveBg.hexString,
            "titleBar.activeForeground": titleForeground.hexString,
            "titleBar.inactiveBackground": titleInactiveBg.hexString,
            "titleBar.inactiveForeground": titleForeground.dimmed.hexString,
            "activityBar.background": activityBg.hexString,
            "activityBar.foreground": activityForeground.hexString,
            "activityBar.inactiveForeground": activityForeground.dimmed.hexString,
            "activityBarBadge.background": badgeBg.hexString,
            "activityBarBadge.foreground": badgeForeground.hexString,
            "statusBar.background": statusBg.hexString,
            "statusBar.foreground": statusForeground.hexString,
            "statusBarItem.hoverBackground": hoverBg.hexString
        ]

        return .success(customizations)
    }
}

private struct RGBColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    /// Creates a color from a `#RRGGBB` string.
    /// - Parameter hex: Color in `#RRGGBB` format.
    init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#") else {
            return nil
        }
        let hexDigits = String(hex.dropFirst())
        guard let value = Int(hexDigits, radix: 16) else {
            return nil
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.red = r
        self.green = g
        self.blue = b
    }

    /// Hex string representation in `#RRGGBB` format.
    var hexString: String {
        let r = RGBColor.clampedByte(from: red)
        let g = RGBColor.clampedByte(from: green)
        let b = RGBColor.clampedByte(from: blue)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Returns a color blended toward another color by the given factor.
    /// - Parameters:
    ///   - other: Color to blend toward.
    ///   - t: Blend factor in the range 0...1.
    func blended(toward other: RGBColor, t: Double) -> RGBColor {
        precondition((0.0...1.0).contains(t), "Blend factor must be between 0 and 1")
        let red = self.red + (other.red - self.red) * t
        let green = self.green + (other.green - self.green) * t
        let blue = self.blue + (other.blue - self.blue) * t
        return RGBColor(
            red: RGBColor.clampUnit(red),
            green: RGBColor.clampUnit(green),
            blue: RGBColor.clampUnit(blue)
        )
    }

    /// Returns a color darkened toward black by the given factor.
    /// - Parameter t: Blend factor in the range 0...1.
    func darkened(by t: Double) -> RGBColor {
        blended(toward: .black, t: t)
    }

    /// Returns a color lightened toward white by the given factor.
    /// - Parameter t: Blend factor in the range 0...1.
    func lightened(by t: Double) -> RGBColor {
        blended(toward: .white, t: t)
    }

    /// Returns the preferred foreground color based on relative luminance.
    func foregroundColor() -> RGBColor {
        relativeLuminance() < 0.55 ? .white : .black
    }

    /// Returns the dimmed foreground color for inactive UI states.
    var dimmed: RGBColor {
        self == .white ? .dimWhite : .dimBlack
    }

    /// Returns the relative luminance of the color using sRGB linearization.
    private func relativeLuminance() -> Double {
        let r = RGBColor.linearize(red)
        let g = RGBColor.linearize(green)
        let b = RGBColor.linearize(blue)
        return (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
    }

    fileprivate static let white = RGBColor(red: 1.0, green: 1.0, blue: 1.0)
    fileprivate static let black = RGBColor(red: 0.0, green: 0.0, blue: 0.0)
    private static let dimWhite = RGBColor(red: 0.8, green: 0.8, blue: 0.8) // #CCCCCC
    private static let dimBlack = RGBColor(red: 0.2, green: 0.2, blue: 0.2) // #333333

    private static func clampUnit(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private static func clampedByte(from value: Double) -> Int {
        let clamped = clampUnit(value)
        return Int((clamped * 255.0).rounded())
    }

    private static func linearize(_ component: Double) -> Double {
        if component <= 0.03928 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }

    private init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}
