import AppKit

// Finder icon coordinates use a top-left origin; draw into the same coordinate space.
let size = NSSize(width: 720, height: 440)
let image = NSImage(size: size)
image.lockFocusFlipped(true)
NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

func text(_ value: String, y: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (value as NSString).draw(in: NSRect(x: 20, y: y, width: 680, height: 40), withAttributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph
    ])
}

text("ScriptDeck", y: 34, font: .systemFont(ofSize: 27, weight: .semibold),
     color: NSColor(calibratedWhite: 0.15, alpha: 1))
text("Drag ScriptDeck to Applications", y: 78, font: .systemFont(ofSize: 15),
     color: NSColor(calibratedWhite: 0.38, alpha: 1))
text("将 ScriptDeck 拖到 Applications 即可安装", y: 103, font: .systemFont(ofSize: 13),
     color: NSColor(calibratedWhite: 0.45, alpha: 1))

NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.91, alpha: 1).setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 312, y: 205))
arrow.line(to: NSPoint(x: 408, y: 205))
arrow.move(to: NSPoint(x: 390, y: 187))
arrow.line(to: NSPoint(x: 408, y: 205))
arrow.line(to: NSPoint(x: 390, y: 223))
arrow.stroke()

text("Examples & documentation · 示例与文档", y: 398,
     font: .systemFont(ofSize: 12), color: NSColor(calibratedWhite: 0.45, alpha: 1))
image.unlockFocus()

guard CommandLine.arguments.count == 2,
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Expected a PNG output path")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
