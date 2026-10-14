// Draws AINCRAD's app icon (the menu motif: a selected round button beside three panels) into
// an asset-catalog icon set. Usage: swift scripts/make_icon.swift AINCRAD/Assets.xcassets
import AppKit

func draw(_ px: Int) -> Data {
    let s = CGFloat(px) / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) in CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }

    // Tile: standard macOS 824 pt body inset in the 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(tilePath); ctx.setFillColor(rgb(20, 27, 38, 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let sky = CGGradient(colorsSpace: nil, colors: [rgb(58, 92, 138, 1), rgb(22, 30, 46, 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // Panels on the right; the middle one is selected.
    let panelX: CGFloat = 470, w: CGFloat = 330, h: CGFloat = 104, gap: CGFloat = 34
    for (i, selected) in [false, true, false].enumerated() {
        let y = 512 - h / 2 + CGFloat(1 - i) * (h + gap)
        let r = CGRect(x: panelX, y: y, width: w, height: h)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: selected ? 26 : 10,
                      color: selected ? rgb(242, 165, 22, 0.8) : rgb(0, 0, 0, 0.35))
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.setFillColor(selected ? rgb(242, 165, 22, 1) : rgb(243, 243, 243, selected ? 1 : 0.92))
        ctx.fillPath()
        ctx.restoreGState()
        // Icon badge and a text bar inside each panel.
        let badge = CGRect(x: r.minX + 18, y: r.midY - 34, width: 68, height: 68)
        ctx.setFillColor(selected ? rgb(255, 255, 255, 1) : rgb(90, 94, 102, 1))
        ctx.fillEllipse(in: badge)
        ctx.setFillColor(selected ? rgb(255, 255, 255, 0.95) : rgb(78, 82, 88, 0.85))
        ctx.fill(CGRect(x: badge.maxX + 22, y: r.midY - 9, width: w - 150, height: 18))
    }

    // Pointer from the button to the selected panel.
    ctx.setFillColor(rgb(242, 165, 22, 1))
    ctx.move(to: CGPoint(x: panelX - 18, y: 512 - 22)); ctx.addLine(to: CGPoint(x: panelX - 18, y: 512 + 22))
    ctx.addLine(to: CGPoint(x: panelX - 44, y: 512)); ctx.closePath(); ctx.fillPath()

    // Selected round button with its ring and a star glyph.
    let c = CGPoint(x: 300, y: 512)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: rgb(242, 165, 22, 0.9))
    ctx.setStrokeColor(rgb(242, 165, 22, 1)); ctx.setLineWidth(12)
    ctx.strokeEllipse(in: CGRect(x: c.x - 118, y: c.y - 118, width: 236, height: 236))
    ctx.restoreGState()
    let orb = CGGradient(colorsSpace: nil, colors: [rgb(255, 196, 70, 1), rgb(232, 140, 10, 1)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - 96, y: c.y - 96, width: 192, height: 192)); ctx.clip()
    ctx.drawLinearGradient(orb, start: CGPoint(x: c.x, y: c.y + 96), end: CGPoint(x: c.x, y: c.y - 96), options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(rgb(255, 255, 255, 1)); ctx.setLineWidth(8)
    ctx.strokeEllipse(in: CGRect(x: c.x - 96, y: c.y - 96, width: 192, height: 192))
    let star = CGMutablePath()
    for k in 0..<10 {
        let a = CGFloat(k) * .pi / 5 + .pi / 2, rr: CGFloat = k % 2 == 0 ? 62 : 26
        let p = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
        k == 0 ? star.move(to: p) : star.addLine(to: p)
    }
    star.closeSubpath()
    ctx.addPath(star); ctx.setFillColor(rgb(255, 255, 255, 1)); ctx.fillPath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let catalog = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets.xcassets")
let set = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
try Data(#"{"info":{"version":1,"author":"xcode"}}"#.utf8).write(to: catalog.appendingPathComponent("Contents.json"))
var images: [String] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try draw(pt * scale).write(to: set.appendingPathComponent(name))
        images.append(#"{"size":"\#(pt)x\#(pt)","idiom":"mac","filename":"\#(name)","scale":"\#(scale)x"}"#)
    }
}
try Data(#"{"images":[\#(images.joined(separator: ","))],"info":{"version":1,"author":"xcode"}}"#.utf8)
    .write(to: set.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icon sizes to \(set.path)")
