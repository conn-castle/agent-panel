import CoreGraphics
import Foundation

/// Errors thrown when normalized geometry is invalid.
enum NormalizedRectError: Error, Equatable {
    case invalid(String)
}

/// Normalized rectangle values relative to a visible frame.
struct NormalizedRect: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    /// Creates a normalized rectangle.
    /// - Parameters:
    ///   - x: Normalized x origin in the range `[0, 1]`.
    ///   - y: Normalized y origin in the range `[0, 1]`.
    ///   - width: Normalized width in the range `[0, 1]`.
    ///   - height: Normalized height in the range `[0, 1]`.
    /// - Throws: `NormalizedRectError` if values are out of range or exceed bounds.
    init(x: Double, y: Double, width: Double, height: Double) throws {
        let bounds = NormalizedRectBounds(x: x, y: y, width: width, height: height)
        guard bounds.isValid else {
            throw NormalizedRectError.invalid(bounds.errorMessage)
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Decodes and validates a normalized rect.
    /// - Parameter decoder: Decoder to read values from.
    /// - Throws: `DecodingError` when validation fails.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        let width = try container.decode(Double.self, forKey: .width)
        let height = try container.decode(Double.self, forKey: .height)
        do {
            try self.init(x: x, y: y, width: width, height: height)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .x,
                in: container,
                debugDescription: "Invalid normalized rect: \(error)"
            )
        }
    }
}

/// Normalized layout for a project workspace.
struct ProjectLayout: Codable, Equatable {
    let ideRect: NormalizedRect
    let chromeRect: NormalizedRect

    enum CodingKeys: String, CodingKey {
        case ideRect = "ide"
        case chromeRect = "chrome"
    }
}

/// Converts a normalized rect into an absolute frame in points.
/// - Parameters:
///   - rect: Normalized rect to convert.
///   - visibleFramePoints: Visible frame in points used as the coordinate space.
/// - Returns: Absolute frame in points.
func denormalize(_ rect: NormalizedRect, in visibleFramePoints: CGRect) -> CGRect {
    let originX = visibleFramePoints.origin.x + CGFloat(rect.x) * visibleFramePoints.width
    let originY = visibleFramePoints.origin.y + CGFloat(rect.y) * visibleFramePoints.height
    let width = CGFloat(rect.width) * visibleFramePoints.width
    let height = CGFloat(rect.height) * visibleFramePoints.height
    return CGRect(x: originX, y: originY, width: width, height: height)
}

/// Provides locked default layouts for each display mode.
struct DefaultLayoutProvider {
    /// Creates a default layout provider.
    init() {}

    /// Returns the default layout for a display mode.
    /// - Parameter displayMode: The current display mode.
    /// - Returns: Default layout for the display mode.
    func layout(for displayMode: DisplayMode) -> ProjectLayout {
        switch displayMode {
        case .laptop:
            return DefaultLayoutProvider.laptopLayout
        case .ultrawide:
            return DefaultLayoutProvider.ultrawideLayout
        }
    }

    private static let laptopLayout: ProjectLayout = {
        let full = makeNormalizedRect(x: 0, y: 0, width: 1, height: 1)
        return ProjectLayout(ideRect: full, chromeRect: full)
    }()

    private static let ultrawideLayout: ProjectLayout = {
        let segment = 1.0 / 8.0
        let ideRect = makeNormalizedRect(x: segment * 2, y: 0, width: segment * 3, height: 1)
        let chromeRect = makeNormalizedRect(x: segment * 5, y: 0, width: segment * 3, height: 1)
        return ProjectLayout(ideRect: ideRect, chromeRect: chromeRect)
    }()

    /// Creates a normalized rect or fails loudly if values are invalid.
    /// - Parameters:
    ///   - x: Normalized x origin.
    ///   - y: Normalized y origin.
    ///   - width: Normalized width.
    ///   - height: Normalized height.
    /// - Returns: Validated normalized rect.
    private static func makeNormalizedRect(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> NormalizedRect {
        do {
            return try NormalizedRect(x: x, y: y, width: width, height: height)
        } catch {
            preconditionFailure("Invalid normalized rect: \(error)")
        }
    }
}

private struct NormalizedRectBounds {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var isValid: Bool {
        guard x >= 0, y >= 0, width >= 0, height >= 0 else {
            return false
        }
        guard x <= 1, y <= 1, width <= 1, height <= 1 else {
            return false
        }
        guard x + width <= 1, y + height <= 1 else {
            return false
        }
        return true
    }

    var errorMessage: String {
        "Normalized rect must satisfy 0 ≤ x,y,w,h ≤ 1 and x+w ≤ 1, y+h ≤ 1."
    }
}
