import AppKit

/// The app icon's leaf glyph as a monochrome template image, drawn as vectors so it
/// stays sharp at any scale and tints with the menu bar like a system symbol.
/// The behind-count is drawn into the same image: SwiftUI drops custom images that
/// are interpolated into a menu bar `Text`.
@MainActor
enum MenuBarIcon {
    enum Style: String, CaseIterable, Identifiable {
        case leaf, symbol
        var id: Self { self }
        var title: String { self == .leaf ? "Offshoot leaf" : "Branch symbol" }
    }

    static let styleKey = "menuBarIconStyle"

    private static let glyphSize = NSSize(width: 15, height: 18)
    private static let gap: CGFloat = 3
    private static var cache: [String: NSImage] = [:]

    private static let symbol = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))

    static func image(count: Int, style: Style = .leaf) -> NSImage {
        let key = "\(style.rawValue)-\(count)"
        if let cached = cache[key] { return cached }
        let symbolSize = symbol?.size ?? glyphSize
        let iconSize = style == .leaf ? glyphSize : NSSize(width: ceil(symbolSize.width), height: glyphSize.height)

        let label =
            count > 0
            ? NSAttributedString(
                string: "\(count)",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: NSColor.black,
                ]) : nil
        let labelSize = label?.size() ?? .zero
        let width = iconSize.width + (label == nil ? 0 : gap + ceil(labelSize.width))

        let image = NSImage(size: NSSize(width: width, height: glyphSize.height), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            if style == .leaf {
                ctx.saveGState()
                drawGlyph(in: ctx)
                ctx.restoreGState()
            } else if let symbol {
                symbol.draw(
                    in: NSRect(
                        x: 0, y: (glyphSize.height - symbolSize.height) / 2,
                        width: symbolSize.width, height: symbolSize.height))
            }
            label?.draw(at: NSPoint(x: iconSize.width + gap, y: (glyphSize.height - labelSize.height) / 2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = count > 0 ? "Offshoot, \(count) behind" : "Offshoot"
        cache[key] = image
        return image
    }

    private static func drawGlyph(in ctx: CGContext) {
        // Geometry is shared with scripts/IconRenderer.swift (1024pt canvas).
        let scale: CGFloat = 16.4 / 610
        ctx.translateBy(x: 0.6, y: 0.8)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -296, y: -196)

        ctx.setStrokeColor(.black)
        ctx.setFillColor(.black)
        ctx.setLineCap(.round)

        let stemX: CGFloat = 372
        let bottom = CGPoint(x: stemX, y: 268)
        let top = CGPoint(x: stemX, y: 742)
        let fork = CGPoint(x: stemX, y: 430)
        let tip = CGPoint(x: 590, y: 600)

        ctx.setLineWidth(62)
        ctx.move(to: CGPoint(x: stemX, y: bottom.y + 60))
        ctx.addLine(to: CGPoint(x: stemX, y: top.y - 60))
        ctx.strokePath()

        ctx.move(to: fork)
        ctx.addCurve(to: tip, control1: CGPoint(x: stemX, y: 560), control2: CGPoint(x: 500, y: 540))
        ctx.strokePath()

        // Commit nodes as rings.
        ctx.setLineWidth(42)
        for point in [bottom, top] {
            ctx.strokeEllipse(in: CGRect(x: point.x - 56, y: point.y - 56, width: 112, height: 112))
        }

        // Leaf.
        ctx.translateBy(x: tip.x, y: tip.y)
        ctx.rotate(by: -.pi / 4)
        let leaf = CGMutablePath()
        leaf.move(to: CGPoint(x: 0, y: -10))
        leaf.addQuadCurve(to: CGPoint(x: 0, y: 230), control: CGPoint(x: 125, y: 110))
        leaf.addQuadCurve(to: CGPoint(x: 0, y: -10), control: CGPoint(x: -125, y: 110))
        ctx.addPath(leaf)
        ctx.fillPath()
    }
}
