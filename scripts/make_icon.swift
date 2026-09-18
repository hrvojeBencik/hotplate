import AppKit

// Usage: swift scripts/make_icon.swift <output.iconset> [preview.png]
// Draws the Hotplate icon: a navy squircle tile with a glowing induction coil and a play triangle.
let sizes: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ px: Int) -> NSBitmapImageRep {
    // Draw into an explicit RGBA bitmap so the corners outside the tile stay transparent.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))
    let s = CGFloat(px)
    // Apple's macOS icon grid: the tile is ~80% of the canvas, centered, with a soft shadow.
    let tileSize = s * 0.805
    let tile = NSRect(x: (s - tileSize) / 2, y: (s - tileSize) / 2 + s * 0.012, width: tileSize, height: tileSize)
    let radius = tileSize * 0.225
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    // Shadow under the tile
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    rgb(0x0B2A4A).setFill(); tilePath.fill()
    ctx.restoreGState()

    // Tile gradient: deep navy at the top to Flutter blue at the bottom
    ctx.saveGState()
    tilePath.addClip()
    NSGradient(colorsAndLocations: (rgb(0x0A2036), 0.0), (rgb(0x0C3F6E), 0.55), (rgb(0x0D85D9), 1.0))!
        .draw(in: tile, angle: -90)
    // Soft top-light highlight, fading out by the middle of the tile
    NSGradient(colorsAndLocations: (NSColor.white.withAlphaComponent(0.0), 0.0), (NSColor.white.withAlphaComponent(0.0), 0.45),
               (NSColor.white.withAlphaComponent(0.14), 1.0))!
        .draw(in: tile, angle: 90)

    let center = CGPoint(x: tile.midX, y: tile.midY)
    let coilR = tileSize * 0.31
    let coilW = tileSize * 0.082

    // Heat glow behind the coil
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: tileSize * 0.16, color: rgb(0xFF7A2E, 0.85).cgColor)
    let glowRing = NSBezierPath(ovalIn: NSRect(x: center.x - coilR, y: center.y - coilR, width: coilR * 2, height: coilR * 2))
    glowRing.lineWidth = coilW
    rgb(0xFF8A3D, 0.9).setStroke(); glowRing.stroke()
    ctx.restoreGState()

    // The coil itself: amber→orange gradient along the ring, drawn as a clipped gradient
    ctx.saveGState()
    let ring = NSBezierPath()
    ring.appendOval(in: NSRect(x: center.x - coilR - coilW / 2, y: center.y - coilR - coilW / 2, width: (coilR + coilW / 2) * 2, height: (coilR + coilW / 2) * 2))
    ring.appendOval(in: NSRect(x: center.x - coilR + coilW / 2, y: center.y - coilR + coilW / 2, width: (coilR - coilW / 2) * 2, height: (coilR - coilW / 2) * 2))
    ring.windingRule = .evenOdd
    ring.addClip()
    NSGradient(colorsAndLocations: (rgb(0xFFD25A), 0.0), (rgb(0xFF9A3C), 0.5), (rgb(0xFF6A2A), 1.0))!
        .draw(in: NSRect(x: center.x - coilR - coilW, y: center.y - coilR - coilW, width: (coilR + coilW) * 2, height: (coilR + coilW) * 2), angle: -60)
    ctx.restoreGState()

    // Thin inner ring, like the second element of a hotplate
    let innerR = tileSize * 0.205
    let inner = NSBezierPath(ovalIn: NSRect(x: center.x - innerR, y: center.y - innerR, width: innerR * 2, height: innerR * 2))
    inner.lineWidth = tileSize * 0.026
    rgb(0xFFB24A, 0.55).setStroke(); inner.stroke()

    // Play triangle, optically centered (shifted slightly right)
    let t = tileSize * 0.24
    let tri = NSBezierPath()
    let tx = center.x + t * 0.10
    tri.move(to: CGPoint(x: tx - t * 0.42, y: center.y - t * 0.5))
    tri.line(to: CGPoint(x: tx - t * 0.42, y: center.y + t * 0.5))
    tri.line(to: CGPoint(x: tx + t * 0.50, y: center.y))
    tri.close()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.006), blur: s * 0.02, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.white.setFill(); tri.fill()
    ctx.restoreGState()

    ctx.restoreGState()   // tile clip
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep) -> Data? { rep.representation(using: .png, properties: [:]) }

for (pt, scale) in sizes {
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    if let data = png(render(pt * scale)) { try! data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name)) }
}
if CommandLine.arguments.count > 2, let data = png(render(512)) {
    try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
