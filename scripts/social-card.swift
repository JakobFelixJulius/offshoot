// Renders the GitHub social preview card (docs/images/social-card.png), the image that
// shows when the repository is shared on Slack, X, LinkedIn or Hacker News.
// Usage: swift scripts/social-card.swift [output.png]
import AppKit

let width: CGFloat = 1280
let height: CGFloat = 640
let output = CommandLine.arguments.dropFirst().first ?? "docs/images/social-card.png"

/// The app icon's branch-and-leaf glyph, drawn on the 1024pt canvas of IconRenderer.swift.
func drawGlyph(in ctx: CGContext, color: CGColor) {
    ctx.setStrokeColor(color)
    ctx.setFillColor(color)
    ctx.setLineCap(.round)

    let stemX: CGFloat = 372
    let bottom = CGPoint(x: stemX, y: 268)
    let top = CGPoint(x: stemX, y: 742)
    let fork = CGPoint(x: stemX, y: 430)
    let tip = CGPoint(x: 590, y: 600)

    ctx.setLineWidth(54)
    ctx.move(to: bottom)
    ctx.addLine(to: top)
    ctx.strokePath()

    ctx.move(to: fork)
    ctx.addCurve(to: tip, control1: CGPoint(x: stemX, y: 560), control2: CGPoint(x: 500, y: 540))
    ctx.strokePath()

    for point in [bottom, top] {
        ctx.fillEllipse(in: CGRect(x: point.x - 66, y: point.y - 66, width: 132, height: 132))
    }
    ctx.setBlendMode(.clear)
    for point in [bottom, top] {
        ctx.fillEllipse(in: CGRect(x: point.x - 30, y: point.y - 30, width: 60, height: 60))
    }
    ctx.setBlendMode(.normal)

    ctx.saveGState()
    ctx.translateBy(x: tip.x, y: tip.y)
    ctx.rotate(by: -.pi / 4)
    let leaf = CGMutablePath()
    leaf.move(to: CGPoint(x: 0, y: -10))
    leaf.addQuadCurve(to: CGPoint(x: 0, y: 230), control: CGPoint(x: 125, y: 110))
    leaf.addQuadCurve(to: CGPoint(x: 0, y: -10), control: CGPoint(x: -125, y: 110))
    ctx.addPath(leaf)
    ctx.fillPath()
    ctx.restoreGState()
}

func draw(_ text: String, _ font: NSFont, _ color: NSColor, at point: NSPoint) {
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        .draw(at: point)
}

let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
    let space = CGColorSpaceCreateDeviceRGB()

    // Deep green background, lighter towards the glyph.
    let background = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 0.07, green: 0.30, blue: 0.25, alpha: 1),
            CGColor(red: 0.03, green: 0.15, blue: 0.14, alpha: 1),
        ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        background, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Glow behind the glyph.
    let glow = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 0.27, green: 0.84, blue: 0.55, alpha: 0.30),
            CGColor(red: 0.27, green: 0.84, blue: 0.55, alpha: 0),
        ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(
        glow, startCenter: CGPoint(x: 285, y: 330), startRadius: 0,
        endCenter: CGPoint(x: 285, y: 330), endRadius: 320, options: [])

    // Glyph on the left, scaled from the 1024pt icon canvas.
    ctx.saveGState()
    let scale: CGFloat = 0.42
    ctx.translateBy(x: 285 - 480 * scale, y: 330 - 500 * scale)
    ctx.scaleBy(x: scale, y: scale)
    drawGlyph(in: ctx, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.restoreGState()

    // Wordmark and tagline on the right.
    let textX: CGFloat = 520
    draw("Offshoot", .systemFont(ofSize: 104, weight: .bold), .white, at: NSPoint(x: textX, y: 384))
    draw(
        "Switch branches and pull your everyday git\nrepositories from the macOS menu bar.",
        .systemFont(ofSize: 36, weight: .regular), NSColor(white: 1, alpha: 0.88),
        at: NSPoint(x: textX, y: 246))
    draw(
        "Built for working with AI coding agents  ·  macOS 14+  ·  MIT",
        .systemFont(ofSize: 25, weight: .medium), NSColor(red: 0.45, green: 0.93, blue: 0.68, alpha: 1),
        at: NSPoint(x: textX, y: 178))
    return true
}

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else { fatalError("Could not render the social card") }
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
