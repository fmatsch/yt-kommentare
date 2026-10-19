// Zeichnet das App-Icon (1024×1024) → icon-1024.png.
// Hintergrund wie YTUploader (gleiche Familie), Motiv wie CommentMonitor
// (Sprechblase) — darin Play-Dreieck und der Stimmungsbalken der App.
import AppKit

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("Kein Grafikkontext") }
ctx.clear(CGRect(origin: .zero, size: size))

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a).cgColor
}

// ── Hintergrund: identisch mit YTUploader ────────────────────────────────────
let rect = CGRect(x: 64, y: 64, width: 896, height: 896)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 200, cornerHeight: 200, transform: nil))
ctx.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [rgb(1.00, 0.38, 0.32), rgb(0.70, 0.10, 0.10)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 960), end: CGPoint(x: 512, y: 64), options: [])
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
ctx.setLineWidth(6)
ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerWidth: 197, cornerHeight: 197, transform: nil))
ctx.strokePath()
ctx.restoreGState()

// ── Sprechblase mit Schwanz, weiß, leichter Schatten ─────────────────────────
let bubbleRect = CGRect(x: 222, y: 340, width: 580, height: 430)
let bubble = CGMutablePath()
bubble.addPath(CGPath(roundedRect: bubbleRect, cornerWidth: 96, cornerHeight: 96, transform: nil))
let tail = CGMutablePath()
tail.move(to: CGPoint(x: 300, y: 360))
tail.addLine(to: CGPoint(x: 262, y: 236))
tail.addLine(to: CGPoint(x: 432, y: 352))
tail.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(0.35, 0, 0, 0.35))
ctx.setFillColor(NSColor.white.cgColor)
ctx.addPath(bubble)
ctx.fillPath()
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setLineJoin(.round)
ctx.setLineWidth(22)
ctx.addPath(tail)
ctx.drawPath(using: .fillStroke)
ctx.restoreGState()

// ── Rotes Play-Dreieck mit runden Ecken ──────────────────────────────────────
let red = rgb(0.82, 0.16, 0.14)
ctx.setFillColor(red)
ctx.setStrokeColor(red)
ctx.setLineJoin(.round)
ctx.setLineWidth(46)
let tri = CGMutablePath()
tri.move(to: CGPoint(x: 462, y: 690))
tri.addLine(to: CGPoint(x: 462, y: 530))
tri.addLine(to: CGPoint(x: 604, y: 610))
tri.closeSubpath()
ctx.addPath(tri)
ctx.drawPath(using: .fillStroke)

// ── Stimmungsbalken: positiv · neutral · negativ ─────────────────────────────
let barY: CGFloat = 418, barH: CGFloat = 40, gap: CGFloat = 16
let barX: CGFloat = 322, barW: CGFloat = 380
let shares: [(CGFloat, CGColor)] = [
    (0.46, rgb(0.13, 0.64, 0.23)),   // positiv
    (0.24, rgb(0.78, 0.78, 0.81)),   // neutral
    (0.30, red),                     // negativ
]
var x = barX
let usable = barW - gap * CGFloat(shares.count - 1)
for (share, color) in shares {
    let w = usable * share
    ctx.setFillColor(color)
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: barY, width: w, height: barH),
                       cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
    ctx.fillPath()
    x += w + gap
}

image.unlockFocus()
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG fehlgeschlagen") }
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"))
print("Icon geschrieben")
