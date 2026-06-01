#!/usr/bin/env swift
//
// Renders the BrewBrowser app icon — a frothy beer mug under a tap — to a
// 1024×1024 PNG. tools/make_icon.sh then downsizes it into the asset catalog.
//
// Flat, geometric design drawn in a top-left coordinate space.
import AppKit

let S: CGFloat = 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsctx
let cg = nsctx.cgContext

// Flip to a top-left origin so the math below reads naturally.
cg.translateBy(x: 0, y: S)
cg.scaleBy(x: 1, y: -1)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a).cgColor
}
func roundRect(_ rect: CGRect, _ radius: CGFloat, _ color: CGColor) {
    cg.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    cg.setFillColor(color)
    cg.fillPath()
}

// --- Background squircle with an amber gradient -----------------------------
let inset: CGFloat = 94
let bg = CGRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)
let bgPath = CGPath(roundedRect: bg, cornerWidth: 185, cornerHeight: 185, transform: nil)
cg.saveGState()
cg.addPath(bgPath); cg.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [rgb(255, 209, 122), rgb(224, 138, 30)] as CFArray,
                      locations: [0, 1])!
cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: inset),
                      end: CGPoint(x: 0, y: S - inset), options: [])
cg.restoreGState()

// --- Tap / faucet (steel + red handle) --------------------------------------
let steel = rgb(54, 60, 68)
let steelDark = rgb(38, 43, 50)
roundRect(CGRect(x: 430, y: 208, width: 232, height: 62), 28, steel)   // cross bar
roundRect(CGRect(x: 470, y: 250, width: 84, height: 120), 22, steel)   // body
roundRect(CGRect(x: 486, y: 356, width: 52, height: 78), 16, steelDark)// down spout
roundRect(CGRect(x: 504, y: 150, width: 36, height: 78), 14, steel)    // handle stem
roundRect(CGRect(x: 466, y: 118, width: 112, height: 48), 22, rgb(196, 52, 46)) // red knob

// --- Pour stream ------------------------------------------------------------
roundRect(CGRect(x: 497, y: 430, width: 30, height: 96), 14, rgb(255, 224, 150, 0.95))

// --- Contact shadow ---------------------------------------------------------
cg.setFillColor(rgb(120, 70, 10, 0.18))
cg.fillEllipse(in: CGRect(x: 372, y: 792, width: 300, height: 60))

// --- Mug handle (thick arc on the right) ------------------------------------
cg.setStrokeColor(rgb(247, 165, 40))
cg.setLineWidth(50)
cg.setLineCap(.round)
cg.addArc(center: CGPoint(x: 648, y: 648), radius: 82,
          startAngle: -0.95, endAngle: 0.95, clockwise: false)
cg.strokePath()

// --- Mug glass: beer + foam -------------------------------------------------
let glass = CGRect(x: 360, y: 500, width: 296, height: 300)
let glassPath = CGPath(roundedRect: glass, cornerWidth: 42, cornerHeight: 42, transform: nil)

cg.saveGState()
cg.addPath(glassPath); cg.clip()
// beer
cg.setFillColor(rgb(245, 164, 33))
cg.fill(glass)
// foam band
cg.setFillColor(rgb(255, 252, 245))
cg.fill(CGRect(x: 360, y: 500, width: 296, height: 78))
// frothy underside of foam
for x in stride(from: CGFloat(388), through: 628, by: 60) {
    cg.fillEllipse(in: CGRect(x: x - 34, y: 548, width: 68, height: 68))
}
// left glass highlight
cg.setFillColor(rgb(255, 255, 255, 0.16))
cg.fill(CGRect(x: 388, y: 590, width: 40, height: 190))
cg.restoreGState()

// foam overflow peeking above the rim
cg.setFillColor(rgb(255, 252, 245))
for (x, r) in [(404.0, 40.0), (470.0, 50.0), (540.0, 48.0), (606.0, 38.0)] {
    cg.fillEllipse(in: CGRect(x: CGFloat(x) - CGFloat(r), y: 500 - CGFloat(r),
                              width: CGFloat(r)*2, height: CGFloat(r)*2))
}

// glass outline for definition
cg.addPath(glassPath)
cg.setStrokeColor(rgb(255, 255, 255, 0.5))
cg.setLineWidth(7)
cg.strokePath()

NSGraphicsContext.restoreGraphicsState()

let outDir = "tools/icon_src"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let url = URL(fileURLWithPath: "\(outDir)/icon_1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: url)
print("wrote \(url.path)")
