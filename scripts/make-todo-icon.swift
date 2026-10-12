import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "HangTodo.png"
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor(srgbRed: 0.13, green: 0.22, blue: 0.29, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 190, yRadius: 190).fill()
let rope = NSBezierPath()
rope.move(to: NSPoint(x: 96, y: 755))
rope.curve(to: NSPoint(x: 928, y: 755), controlPoint1: NSPoint(x: 300, y: 700), controlPoint2: NSPoint(x: 720, y: 700))
rope.lineWidth = 9
NSColor(srgbRed: 0.73, green: 0.79, blue: 0.79, alpha: 1).setStroke()
rope.stroke()

NSColor(srgbRed: 0.95, green: 0.94, blue: 0.90, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 274, y: 250, width: 476, height: 455), xRadius: 44, yRadius: 44).fill()
NSColor(srgbRed: 0.84, green: 0.42, blue: 0.32, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 489, y: 653, width: 46, height: 120), xRadius: 15, yRadius: 15).fill()

let ink = NSColor(srgbRed: 0.13, green: 0.22, blue: 0.29, alpha: 1)
ink.setStroke()
let check = NSBezierPath()
check.move(to: NSPoint(x: 334, y: 560))
check.line(to: NSPoint(x: 360, y: 534))
check.line(to: NSPoint(x: 412, y: 594))
check.lineWidth = 18
check.lineCapStyle = .round
check.lineJoinStyle = .round
check.stroke()
ink.setFill()
NSBezierPath(roundedRect: NSRect(x: 450, y: 558, width: 216, height: 18), xRadius: 9, yRadius: 9).fill()
ink.withAlphaComponent(0.28).setFill()
NSBezierPath(roundedRect: NSRect(x: 334, y: 465, width: 330, height: 16), xRadius: 8, yRadius: 8).fill()
NSBezierPath(roundedRect: NSRect(x: 334, y: 416, width: 252, height: 16), xRadius: 8, yRadius: 8).fill()
let colors: [NSColor] = [.systemRed, .systemBlue, .systemOrange, .systemGreen]
for (index, color) in colors.enumerated() {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: CGFloat(334 + index * 87), y: 321, width: 62, height: 28), xRadius: 9, yRadius: 9).fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
