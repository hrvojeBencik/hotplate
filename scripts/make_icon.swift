import AppKit

// Usage: swift scripts/make_icon.swift <output.iconset>
let sizes: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    let s = CGFloat(px)
    let rect = NSRect(x: s*0.05, y: s*0.05, width: s*0.9, height: s*0.9)
    let path = NSBezierPath(roundedRect: rect, xRadius: s*0.2, yRadius: s*0.2)
    let grad = NSGradient(starting: NSColor(calibratedRed: 0.02, green: 0.35, blue: 0.85, alpha: 1),
                          ending: NSColor(calibratedRed: 0.20, green: 0.70, blue: 0.95, alpha: 1))!
    grad.draw(in: path, angle: -60)
    let tri = NSBezierPath()
    tri.move(to: NSPoint(x: s*0.38, y: s*0.26)); tri.line(to: NSPoint(x: s*0.38, y: s*0.74)); tri.line(to: NSPoint(x: s*0.80, y: s*0.5)); tri.close()
    NSColor.white.setFill(); tri.fill()
    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: s*0.34, y: s*0.90)); bolt.line(to: NSPoint(x: s*0.18, y: s*0.62)); bolt.line(to: NSPoint(x: s*0.28, y: s*0.62))
    bolt.line(to: NSPoint(x: s*0.20, y: s*0.40)); bolt.line(to: NSPoint(x: s*0.38, y: s*0.70)); bolt.line(to: NSPoint(x: s*0.28, y: s*0.70)); bolt.close()
    NSColor(calibratedRed: 1, green: 0.85, blue: 0.2, alpha: 1).setFill(); bolt.fill()
    img.unlockFocus()
    return img
}

for (pt, scale) in sizes {
    let px = pt * scale
    let img = render(px)
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    try! png.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
