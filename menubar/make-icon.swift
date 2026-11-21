import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 206, yRadius: 206)
    // Flat CubeBit palette: navy foundation, sky detail, restrained rust accent.
    let navy = NSColor(srgbRed: 19.0/255, green: 42.0/255, blue: 69.0/255, alpha: 1)
    let sky = NSColor(srgbRed: 127.0/255, green: 179.0/255, blue: 218.0/255, alpha: 1)
    let rust = NSColor(srgbRed: 176.0/255, green: 85.0/255, blue: 46.0/255, alpha: 1)
    navy.setFill(); tile.fill()
    let handle = NSBezierPath(roundedRect: NSRect(x: 634, y: 420, width: 156, height: 174), xRadius: 70, yRadius: 70)
    sky.setStroke(); handle.lineWidth = 26; handle.stroke()
    let cup = NSBezierPath()
    cup.move(to: NSPoint(x: 278, y: 646))
    cup.line(to: NSPoint(x: 676, y: 646))
    cup.line(to: NSPoint(x: 676, y: 438))
    cup.curve(to: NSPoint(x: 588, y: 350), controlPoint1: NSPoint(x: 676, y: 386), controlPoint2: NSPoint(x: 640, y: 350))
    cup.line(to: NSPoint(x: 366, y: 350))
    cup.curve(to: NSPoint(x: 278, y: 438), controlPoint1: NSPoint(x: 314, y: 350), controlPoint2: NSPoint(x: 278, y: 386))
    cup.close()
    navy.setFill(); cup.fill()
    sky.setStroke(); cup.lineWidth = 26; cup.lineJoinStyle = .round; cup.stroke()
    let saucer = NSBezierPath()
    saucer.move(to: NSPoint(x: 252, y: 274)); saucer.line(to: NSPoint(x: 730, y: 274))
    saucer.lineWidth = 28; saucer.lineCapStyle = .round; rust.setStroke(); saucer.stroke()
    for x in [356.0, 477.0, 598.0] {
        let steam = NSBezierPath()
        steam.move(to: NSPoint(x: x, y: 704))
        steam.curve(to: NSPoint(x: x + 6, y: 800), controlPoint1: NSPoint(x: x - 35, y: 745), controlPoint2: NSPoint(x: x + 40, y: 758))
        steam.lineWidth = 19; steam.lineCapStyle = .round; sky.setStroke(); steam.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
}
// Modern ICNS records carry PNG bytes, so packaging needs no GUI-backed icon service.
func integer(_ value: Int) -> Data {
    var big = UInt32(value).bigEndian; return withUnsafeBytes(of: &big) { Data($0) }
}
var records = Data()
for (type, name) in [("ic07", "icon_128x128"), ("ic08", "icon_256x256"), ("ic09", "icon_512x512"), ("ic10", "icon_512x512@2x"), ("ic11", "icon_16x16@2x"), ("ic12", "icon_32x32@2x"), ("ic13", "icon_128x128@2x"), ("ic14", "icon_256x256@2x")] {
    let png = try Data(contentsOf: output.appendingPathComponent(name + ".png"))
    records.append(Data(type.utf8)); records.append(integer(png.count + 8)); records.append(png)
}
var icon = Data("icns".utf8); icon.append(integer(records.count + 8)); icon.append(records)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
