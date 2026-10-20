import AppKit
import CoreGraphics

// Original MacTVMate icon: macOS squircle, deep-blue gradient, white TV with antennas and a play button.
let size: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// Squircle body (Big Sur grid: 824pt body inside 1024, with drop shadow).
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset + 8, width: size - 2 * inset, height: size - 2 * inset)
let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: c(0x000000, 0.35))
ctx.addPath(squircle); ctx.setFillColor(c(0x1565C0)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let grad = CGGradient(colorsSpace: cs, colors: [c(0x42A5F5), c(0x1E88E5), c(0x0D47A1)] as CFArray, locations: [0, 0.45, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
// Soft top highlight.
let shine = CGGradient(colorsSpace: cs, colors: [c(0xFFFFFF, 0.22), c(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(shine, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY + 40), options: [])
ctx.restoreGState()

// Antennas.
ctx.setStrokeColor(c(0xFFFFFF)); ctx.setLineWidth(30); ctx.setLineCap(.round)
let top = CGPoint(x: size / 2, y: 650)
ctx.move(to: top); ctx.addLine(to: CGPoint(x: 400, y: 778))
ctx.move(to: top); ctx.addLine(to: CGPoint(x: 624, y: 778))
ctx.strokePath()
ctx.setFillColor(c(0xFFFFFF))
for p in [CGPoint(x: 400, y: 778), CGPoint(x: 624, y: 778)] { ctx.fillEllipse(in: CGRect(x: p.x - 26, y: p.y - 26, width: 52, height: 52)) }

// TV body with a cut-out screen.
let tv = CGRect(x: 232, y: 262, width: 560, height: 400)
let screen = tv.insetBy(dx: 46, dy: 46)
let tvPath = CGMutablePath()
tvPath.addPath(CGPath(roundedRect: tv, cornerWidth: 86, cornerHeight: 86, transform: nil))
tvPath.addPath(CGPath(roundedRect: screen, cornerWidth: 46, cornerHeight: 46, transform: nil))
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: c(0x0A2A66, 0.45))
ctx.addPath(tvPath); ctx.setFillColor(c(0xFFFFFF)); ctx.fillPath(using: .evenOdd)
ctx.restoreGState()

// Play button in the screen.
let cx = screen.midX + 14, cy = screen.midY
let tri = CGMutablePath()
tri.move(to: CGPoint(x: cx - 62, y: cy + 82))
tri.addLine(to: CGPoint(x: cx - 62, y: cy - 82))
tri.addLine(to: CGPoint(x: cx + 86, y: cy))
tri.closeSubpath()
ctx.addPath(tri); ctx.setFillColor(c(0xFFFFFF)); ctx.setLineJoin(.round); ctx.setLineWidth(26)
ctx.setStrokeColor(c(0xFFFFFF)); ctx.drawPath(using: .fillStroke)

// Stand.
ctx.setFillColor(c(0xFFFFFF))
ctx.addPath(CGPath(roundedRect: CGRect(x: 412, y: 210, width: 200, height: 34), cornerWidth: 17, cornerHeight: 17, transform: nil)); ctx.fillPath()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon_1024.png"))
print("ok")
