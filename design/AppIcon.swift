// Source of the app icon: an illithid tadpole on a deep purple tile.
// Regenerate with:
//   swift design/AppIcon.swift design/icon_1024.png
// then resize into App/Assets.xcassets/AppIcon.appiconset (design/make_icons.sh).

import AppKit
import CoreGraphics

// 1024×1024, following Apple's macOS icon grid: an 824-pt rounded square
// centered with room for the drop shadow.
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.4))
ctx.addPath(tilePath); ctx.setFillColor(color(0x1A0E30)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
// Background: deep violet, lighter at the top.
let background = CGGradient(colorsSpace: space, colors: [color(0x3B1D63), color(0x1B0F33), color(0x0E0820)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// Psionic glow behind the tadpole.
let glow = CGGradient(colorsSpace: space, colors: [color(0xB57BFF, 0.55), color(0x7B3FE4, 0.18), color(0x7B3FE4, 0)] as CFArray, locations: [0, 0.5, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 560, y: 560), startRadius: 0, endCenter: CGPoint(x: 560, y: 560), endRadius: 420, options: [])
// A few faint motes.
for (x, y, r) in [(250.0, 760.0, 7.0), (300.0, 690.0, 4.0), (760.0, 300.0, 6.0), (820.0, 400.0, 4.0), (700.0, 820.0, 5.0), (220.0, 420.0, 5.0)] {
    ctx.setFillColor(color(0xE6C9FF, 0.55))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}
ctx.restoreGState()

// The tadpole: a round head (top right) and a tapered, S-curved tail.
func cubic(_ t: CGFloat, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}
let head = CGPoint(x: 600, y: 590)
let headRadius: CGFloat = 150
let p0 = head, p1 = CGPoint(x: 470, y: 470), p2 = CGPoint(x: 470, y: 280), p3 = CGPoint(x: 250, y: 250)
var left: [CGPoint] = [], right: [CGPoint] = []
let steps = 80
for i in 0...steps {
    let t = CGFloat(i) / CGFloat(steps)
    let point = cubic(t, p0, p1, p2, p3)
    let ahead = cubic(min(1, t + 0.01), p0, p1, p2, p3)
    let behind = cubic(max(0, t - 0.01), p0, p1, p2, p3)
    var dx = ahead.x - behind.x, dy = ahead.y - behind.y
    let length = max(0.001, hypot(dx, dy)); dx /= length; dy /= length
    let width = (1 - t) * (1 - t) * 118 + 4  // thick at the head, a point at the end
    left.append(CGPoint(x: point.x - dy * width, y: point.y + dx * width))
    right.append(CGPoint(x: point.x + dy * width, y: point.y - dx * width))
}
// Separate shapes: in one path, the tail's and the head's opposite windings
// would cut a hole where they overlap.
let tail = CGMutablePath()
tail.addLines(between: left + right.reversed())
tail.closeSubpath()
let headShape = CGPath(ellipseIn: CGRect(x: head.x - headRadius, y: head.y - headRadius, width: headRadius * 2, height: headRadius * 2), transform: nil)
let parts: [CGPath] = [tail, headShape]

// Little tentacles at the front of the head.
let tentacles = CGMutablePath()
// Fanned out from the front of the head, each with a gentle curl.
for (angle, length, curl) in [(0.3, 105.0, 0.5), (0.8, 125.0, -0.4), (1.3, 105.0, -0.55)] as [(CGFloat, CGFloat, CGFloat)] {
    let base = CGPoint(x: head.x + cos(angle) * (headRadius - 25), y: head.y + sin(angle) * (headRadius - 25))
    let tip = CGPoint(x: head.x + cos(angle) * (headRadius + length), y: head.y + sin(angle) * (headRadius + length))
    // The control point sits beside the middle of the tentacle.
    let middle = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
    let side = CGPoint(x: -sin(angle), y: cos(angle))
    let bend = CGPoint(x: middle.x + side.x * curl * length, y: middle.y + side.y * curl * length)
    tentacles.move(to: base)
    tentacles.addQuadCurve(to: tip, control: bend)
}

// Soft glow around the creature, then its fleshy fill.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 40, color: color(0xC48CFF, 0.9))
ctx.addPath(tentacles)
ctx.setLineWidth(30); ctx.setLineCap(.round)
ctx.setStrokeColor(color(0xD9A2E8)); ctx.strokePath()
for part in parts {
    ctx.addPath(part); ctx.setFillColor(color(0xD9A2E8)); ctx.fillPath()
}
ctx.restoreGState()

let flesh = CGGradient(colorsSpace: space, colors: [color(0xFFE3F6), color(0xE3A6E6), color(0x9A55C8)] as CFArray, locations: [0, 0.45, 1])!
for part in parts {
    ctx.saveGState()
    ctx.addPath(part); ctx.clip()
    ctx.drawRadialGradient(flesh, startCenter: CGPoint(x: head.x + 45, y: head.y + 55), startRadius: 10,
                           endCenter: head, endRadius: 520, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
}
// Tentacle tips a shade lighter.
ctx.addPath(tentacles)
ctx.setLineWidth(18); ctx.setLineCap(.round)
ctx.setStrokeColor(color(0xF3C8F0)); ctx.strokePath()

// A sheen on the head.
ctx.saveGState()
ctx.setFillColor(color(0xFFFFFF, 0.55))
ctx.fillEllipse(in: CGRect(x: head.x - 20, y: head.y + 50, width: 70, height: 42))
ctx.restoreGState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
