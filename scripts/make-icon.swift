import AppKit

let iconsetDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let icnsOutput = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

let navyTop = NSColor(srgbRed: 23.0/255, green: 52.0/255, blue: 84.0/255, alpha: 1)
let navyBot = NSColor(srgbRed: 14.0/255, green: 32.0/255, blue: 54.0/255, alpha: 1)
let sky     = NSColor(srgbRed: 127.0/255, green: 179.0/255, blue: 218.0/255, alpha: 1)
let rust    = NSColor(srgbRed: 176.0/255, green: 85.0/255, blue: 46.0/255, alpha: 1)

for (name, pixels) in sizes {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let ctx = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / 1024.0
    ctx.scaleBy(x: scale, y: scale)

    // macOS squircle background tile
    let tileRect = NSRect(x: 68, y: 68, width: 888, height: 888)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: 204, yRadius: 204)
    if let grad = NSGradient(starting: navyBot, ending: navyTop) {
        grad.draw(in: tile, angle: 90)
    }

    // Subtle inner specular frame
    let innerTile = NSBezierPath(roundedRect: tileRect.insetBy(dx: 10, dy: 10), xRadius: 194, yRadius: 194)
    sky.withAlphaComponent(0.22).setStroke()
    innerTile.lineWidth = 10
    innerTile.stroke()

    // Subtle recessed module grid backdrop
    let gridFrame = NSBezierPath(roundedRect: NSRect(x: 214, y: 214, width: 596, height: 596), xRadius: 126, yRadius: 126)
    NSColor.white.withAlphaComponent(0.035).setFill()
    gridFrame.fill()

    // Architectural CubeBit "G" monogram (Cocoa bottom-left coordinates)
    // Top bar (y: 632..750)
    sky.setFill()
    NSBezierPath(roundedRect: NSRect(x: 274, y: 632, width: 476, height: 118), xRadius: 59, yRadius: 59).fill()
    // Left vertical pillar (x: 274..392, y: 274..750)
    NSBezierPath(roundedRect: NSRect(x: 274, y: 274, width: 118, height: 476), xRadius: 59, yRadius: 59).fill()
    // Bottom bar (y: 274..392)
    NSBezierPath(roundedRect: NSRect(x: 274, y: 274, width: 476, height: 118), xRadius: 59, yRadius: 59).fill()
    // Lower-right vertical leg (x: 632..750, stops cleanly beneath the rust pill)
    NSBezierPath(roundedRect: NSRect(x: 632, y: 274, width: 118, height: 238), xRadius: 59, yRadius: 59).fill()

    // CubeBit Rust precision crossbar / action pill (center-right)
    rust.setFill()
    NSBezierPath(roundedRect: NSRect(x: 478, y: 454, width: 272, height: 118), xRadius: 59, yRadius: 59).fill()

    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    try png.write(to: iconsetDir.appendingPathComponent(name + ".png"))
}

func bigEndian32(_ value: Int) -> Data {
    var big = UInt32(value).bigEndian
    return withUnsafeBytes(of: &big) { Data($0) }
}

var records = Data()
let icnsEntries: [(String, String)] = [
    ("ic07", "icon_128x128"), ("ic08", "icon_256x256"),
    ("ic09", "icon_512x512"), ("ic10", "icon_512x512@2x"),
    ("ic11", "icon_16x16@2x"), ("ic12", "icon_32x32@2x"),
    ("ic13", "icon_128x128@2x"), ("ic14", "icon_256x256@2x")
]
for (chunkType, fileName) in icnsEntries {
    let png = try Data(contentsOf: iconsetDir.appendingPathComponent(fileName + ".png"))
    records.append(Data(chunkType.utf8))
    records.append(bigEndian32(png.count + 8))
    records.append(png)
}
var icns = Data("icns".utf8)
icns.append(bigEndian32(records.count + 8))
icns.append(records)
try icns.write(to: icnsOutput)
print("Generated \(icnsOutput.path)")
