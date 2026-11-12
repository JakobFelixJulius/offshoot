// Renders the Offshoot app icon: a git branch sprouting a leaf on a green squircle.
// Usage: swift scripts/IconRenderer.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
    let space = CGColorSpaceCreateDeviceRGB()

    // macOS icon grid: 824pt body inset 100pt, continuous corners.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186).cgPath

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -14), blur: 28,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(red: 0.05, green: 0.35, blue: 0.27, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bg = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 0.27, green: 0.84, blue: 0.55, alpha: 1),
            CGColor(red: 0.07, green: 0.52, blue: 0.43, alpha: 1),
        ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        bg, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Soft top sheen.
    let sheen = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // Glyph.
    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let stemX: CGFloat = 372
    let bottom = CGPoint(x: stemX, y: 268)
    let top = CGPoint(x: stemX, y: 742)
    let fork = CGPoint(x: stemX, y: 430)
    let tip = CGPoint(x: 590, y: 600)

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -6), blur: 14,
        color: CGColor(red: 0.02, green: 0.25, blue: 0.2, alpha: 0.35))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    ctx.setStrokeColor(white)
    ctx.setLineWidth(54)
    ctx.setLineCap(.round)

    ctx.move(to: bottom)
    ctx.addLine(to: top)
    ctx.strokePath()

    ctx.move(to: fork)
    ctx.addCurve(to: tip, control1: CGPoint(x: stemX, y: 560), control2: CGPoint(x: 500, y: 540))
    ctx.strokePath()

    // Commit nodes.
    ctx.setFillColor(white)
    for point in [bottom, top] {
        ctx.fillEllipse(in: CGRect(x: point.x - 66, y: point.y - 66, width: 132, height: 132))
    }
    // Hollow centers read as git commits.
    ctx.setBlendMode(.clear)
    for point in [bottom, top] {
        ctx.fillEllipse(in: CGRect(x: point.x - 30, y: point.y - 30, width: 60, height: 60))
    }
    ctx.setBlendMode(.normal)

    // Leaf at the branch tip.
    ctx.saveGState()
    ctx.translateBy(x: tip.x, y: tip.y)
    ctx.rotate(by: -.pi / 4)
    let leaf = CGMutablePath()
    leaf.move(to: CGPoint(x: 0, y: -10))
    leaf.addQuadCurve(to: CGPoint(x: 0, y: 230), control: CGPoint(x: 120, y: 110))
    leaf.addQuadCurve(to: CGPoint(x: 0, y: -10), control: CGPoint(x: -120, y: 110))
    ctx.addPath(leaf)
    ctx.setFillColor(white)
    ctx.fillPath()
    // Midrib.
    ctx.setStrokeColor(CGColor(red: 0.12, green: 0.6, blue: 0.45, alpha: 1))
    ctx.setLineWidth(9)
    ctx.move(to: CGPoint(x: 0, y: 10))
    ctx.addLine(to: CGPoint(x: 0, y: 165))
    ctx.strokePath()
    ctx.restoreGState()

    ctx.endTransparencyLayer()
    ctx.restoreGState()
    return true
}

guard let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("Could not render icon")
}
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
