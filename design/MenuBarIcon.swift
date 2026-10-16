// Source of the menu bar icon: the app icon's tadpole as a black silhouette
// (a template image macOS tints for light and dark menu bars), in PDF.
// Regenerate with:
//   swift design/MenuBarIcon.swift App/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.pdf

import AppKit
import CoreGraphics

// The same shapes as AppIcon.swift, drawn in its 1024-point space and scaled
// to an 18-point square around the creature.
let points: CGFloat = 18
let crop = CGRect(x: 205, y: 205, width: 680, height: 680)
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "MenuBarIcon.pdf")
var box = CGRect(x: 0, y: 0, width: points, height: points)
let ctx = CGContext(out as CFURL, mediaBox: &box, nil)!
ctx.beginPDFPage(nil)
ctx.scaleBy(x: points / crop.width, y: points / crop.height)
ctx.translateBy(x: -crop.minX, y: -crop.minY)
ctx.setFillColor(.black)
ctx.setStrokeColor(.black)

func cubic(_ t: CGFloat, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}
let head = CGPoint(x: 600, y: 590)
let headRadius: CGFloat = 150
let p0 = head, p1 = CGPoint(x: 470, y: 470), p2 = CGPoint(x: 470, y: 280), p3 = CGPoint(x: 250, y: 250)
var left: [CGPoint] = [], right: [CGPoint] = []
for i in 0...80 {
    let t = CGFloat(i) / 80
    let point = cubic(t, p0, p1, p2, p3)
    let ahead = cubic(min(1, t + 0.01), p0, p1, p2, p3)
    let behind = cubic(max(0, t - 0.01), p0, p1, p2, p3)
    var dx = ahead.x - behind.x, dy = ahead.y - behind.y
    let length = max(0.001, hypot(dx, dy)); dx /= length; dy /= length
    let width = (1 - t) * (1 - t) * 118 + 14  // a rounder tip than the icon's: it's tiny here
    left.append(CGPoint(x: point.x - dy * width, y: point.y + dx * width))
    right.append(CGPoint(x: point.x + dy * width, y: point.y - dx * width))
}
ctx.addLines(between: left + right.reversed())
ctx.closePath()
ctx.fillPath()
ctx.fillEllipse(in: CGRect(x: head.x - headRadius, y: head.y - headRadius, width: headRadius * 2, height: headRadius * 2))

// Tentacles, thicker than the icon's so they show at menu bar size.
for (angle, length, curl) in [(0.3, 105.0, 0.5), (0.8, 125.0, -0.4), (1.3, 105.0, -0.55)] as [(CGFloat, CGFloat, CGFloat)] {
    let base = CGPoint(x: head.x + cos(angle) * (headRadius - 25), y: head.y + sin(angle) * (headRadius - 25))
    let tip = CGPoint(x: head.x + cos(angle) * (headRadius + length), y: head.y + sin(angle) * (headRadius + length))
    let middle = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
    let side = CGPoint(x: -sin(angle), y: cos(angle))
    ctx.move(to: base)
    ctx.addQuadCurve(to: tip, control: CGPoint(x: middle.x + side.x * curl * length, y: middle.y + side.y * curl * length))
}
ctx.setLineWidth(46)
ctx.setLineCap(.round)
ctx.strokePath()

ctx.endPDFPage()
ctx.closePDF()
print("Wrote \(out.path)")
