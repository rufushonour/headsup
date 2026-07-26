import AppKit

let size = 1024
let canvas = NSRect(x: 0, y: 0, width: size, height: size)

func tightAlphaBounds(of image: NSImage) -> NSRect {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(image.size.width),
        pixelsHigh: Int(image.size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()

    let w = rep.pixelsWide
    let h = rep.pixelsHigh
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h {
        for x in 0..<w {
            let alpha = rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
            if alpha > 0.05 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard minX < maxX, minY < maxY else { return NSRect(origin: .zero, size: image.size) }
    // NSBitmapImageRep is top-down in pixel indexing here; flip Y back to AppKit coords.
    let flippedMinY = h - 1 - maxY
    return NSRect(x: minX, y: flippedMinY, width: maxX - minX, height: maxY - minY)
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Squircle background (approximated with a rounded rect)
let cornerRadius = CGFloat(size) * 0.2237
let backgroundPath = NSBezierPath(roundedRect: canvas, xRadius: cornerRadius, yRadius: cornerRadius)
backgroundPath.addClip()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.31, green: 0.27, blue: 0.90, alpha: 1.0), // indigo-600 ish
    NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.29, alpha: 1.0)  // deep indigo/navy
])
gradient?.draw(in: canvas, angle: -90)

// Render the bell glyph to measure its true (tight) visual bounds, then center that.
let bellPointSize = CGFloat(size) * 0.50
var bellFinalRect = NSRect.zero
if let bell = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: bellPointSize, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    if let configured = bell.withSymbolConfiguration(config) {
        let tight = tightAlphaBounds(of: configured)
        // Offset so the tight bbox center lands on canvas center.
        let offsetX = canvas.midX - (tight.midX)
        let offsetY = canvas.midY - (tight.midY)
        let origin = NSPoint(x: offsetX, y: offsetY)
        configured.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
        bellFinalRect = tight.offsetBy(dx: offsetX, dy: offsetY)
    }
}

// Accent badge, tucked against the bell's upper-right shoulder like a notification badge.
let badgeDiameter = CGFloat(size) * 0.19
let badgeCenter = NSPoint(x: bellFinalRect.maxX - badgeDiameter * 0.25, y: bellFinalRect.maxY - badgeDiameter * 0.55)
let badgeRect = NSRect(
    x: badgeCenter.x - badgeDiameter / 2,
    y: badgeCenter.y - badgeDiameter / 2,
    width: badgeDiameter,
    height: badgeDiameter
)
// Solid ring (background color) behind the badge, so it separates from the white bell
// without punching a transparent hole in the icon.
let ringDiameter = badgeDiameter * 1.28
let ringRect = NSRect(
    x: badgeCenter.x - ringDiameter / 2,
    y: badgeCenter.y - ringDiameter / 2,
    width: ringDiameter,
    height: ringDiameter
)
NSColor(calibratedRed: 0.16, green: 0.14, blue: 0.45, alpha: 1.0).setFill()
NSBezierPath(ovalIn: ringRect).fill()

NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.09, alpha: 1.0).setFill() // orange-500 ish
NSBezierPath(ovalIn: badgeRect).fill()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("Failed to render icon")
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
