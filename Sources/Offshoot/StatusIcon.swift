import AppKit

/// Colored menu item icons. Menus render SF Symbols as monochrome templates, so the
/// color is baked into a non-template image: a white glyph on a colored disc,
/// like the status badges in System Settings.
@MainActor
enum StatusIcon {
    case upToDate, behind, dirty, diverged, ahead, error, busy, unknown

    var image: NSImage {
        Self.render(symbol, color)
    }

    static func action(_ symbol: String, _ color: NSColor) -> NSImage {
        render(symbol, color)
    }

    private var symbol: String {
        switch self {
        case .upToDate: "checkmark.circle.fill"
        case .behind: "arrow.down.circle.fill"
        case .dirty: "pencil.circle.fill"
        case .diverged: "arrow.up.arrow.down.circle.fill"
        case .ahead: "arrow.up.circle.fill"
        case .error: "exclamationmark.circle.fill"
        case .busy: "arrow.triangle.2.circlepath.circle.fill"
        case .unknown: "circle.dotted"
        }
    }

    private var color: NSColor {
        switch self {
        case .upToDate: .systemGreen
        case .behind: .systemBlue
        case .dirty, .diverged: .systemOrange
        case .ahead, .busy, .unknown: .systemGray
        case .error: .systemRed
        }
    }

    private static var cache: [String: NSImage] = [:]

    private static func render(_ symbol: String, _ color: NSColor) -> NSImage {
        let key = "\(symbol)-\(color)"
        if let cached = cache[key] { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(
                NSImage.SymbolConfiguration(paletteColors: symbol.hasSuffix(".fill") ? [.white, color] : [color]))
        let image =
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = false
        cache[key] = image
        return image
    }
}
