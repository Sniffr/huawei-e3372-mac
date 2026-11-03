// Renders the app icon: a green rounded square with a white keypad glyph.
import AppKit

let out = CommandLine.arguments[1]
let sizes = [16, 32, 64, 128, 256, 512, 1024]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

for size in sizes {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
        let inset = s * 0.1
        let tile = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: s * 0.18, yRadius: s * 0.18)
        NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.80, blue: 0.40, alpha: 1),
                            NSColor(calibratedRed: 0.05, green: 0.55, blue: 0.30, alpha: 1)])!
            .draw(in: tile, angle: -90)
        let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let glyph = NSImage(systemSymbolName: "circle.grid.3x3.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let g = glyph.size
            glyph.draw(in: NSRect(x: (s - g.width) / 2, y: (s - g.height) / 2, width: g.width, height: g.height))
        }
        return true
    }
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let png = rep.representation(using: .png, properties: [:])!
    for (name, px) in [("icon_\(size)x\(size).png", size), ("icon_\(size / 2)x\(size / 2)@2x.png", size)] where px >= 32 || name.hasPrefix("icon_16x16.") {
        try! png.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    }
}
