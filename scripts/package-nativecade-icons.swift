// Mechanical asset-catalog exports of the approved opaque branding artwork.
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("RecompTV/Assets.xcassets")
let brand = catalog.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
let metadata: [String: Any] = ["author": "xcode", "version": 1]
func json(_ path: URL, _ value: [String: Any]) throws {
    try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: path)
}
enum ExportError: Error { case image }
func image(_ path: String) throws -> NSBitmapImageRep {
    guard let result = NSBitmapImageRep(data: try Data(contentsOf: root.appendingPathComponent(path))) else { throw ExportError.image }
    return result
}
let icon = try image("docs/branding/nativecade/nativecade-tv-icon.png")
let logo = try image("docs/branding/nativecade/nativecade-logo-on-light.png")
func export(_ source: NSBitmapImageRep, to path: URL, width: Int, height: Int, backgroundOnly: Bool = false) throws {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
              bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let color = source.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB),
          let cgImage = source.cgImage else { throw ExportError.image }
    context.interpolationQuality = .high
    context.setFillColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    if !backgroundOnly {
        let scale = min(Double(width) / Double(source.pixelsWide), Double(height) / Double(source.pixelsHigh))
        let w = Double(source.pixelsWide) * scale, h = Double(source.pixelsHigh) * scale
        context.draw(cgImage, in: CGRect(x: (Double(width) - w) / 2, y: (Double(height) - h) / 2, width: w, height: h))
    }
    guard let rendered = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else { throw ExportError.image }
    try data.write(to: path)
}
try json(catalog.appendingPathComponent("Contents.json"), ["info": metadata])
var assets = [[String: Any]]()
for (name, w, h, scales) in [("App Icon", 400, 240, [1, 2]), ("App Store Icon", 1280, 768, [1])] {
    let stack = brand.appendingPathComponent(name + ".imagestack")
    // Keep the approved opaque face. The matching back plane prevents exposed
    // transparent edges when tvOS tilts the layered icon on focus.
    let layers = ["Front", "Back"]
    try json(stack.appendingPathComponent("Contents.json"), ["info": metadata,
        "layers": layers.map { ["filename": $0 + ".imagestacklayer"] }])
    for layer in layers {
        let folder = stack.appendingPathComponent(layer + ".imagestacklayer")
        let set = folder.appendingPathComponent("Content.imageset")
        try json(folder.appendingPathComponent("Contents.json"), ["info": metadata])
        try json(set.appendingPathComponent("Contents.json"), ["info": metadata,
            "images": scales.map { ["filename": "icon@\($0)x.png", "idiom": "tv", "scale": "\($0)x"] }])
        for scale in scales {
            try export(icon, to: set.appendingPathComponent("icon@\(scale)x.png"), width: w * scale,
                       height: h * scale, backgroundOnly: layer == "Back")
        }
    }
    assets.append(["filename": name + ".imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "\(w)x\(h)"])
}
for (name, width, role) in [("Top Shelf", 1920, "top-shelf-image"), ("Top Shelf Wide", 2320, "top-shelf-image-wide")] {
    let set = brand.appendingPathComponent(name + ".imageset")
    try json(set.appendingPathComponent("Contents.json"), ["info": metadata,
        "images": [1, 2].map { ["filename": "shelf@\($0)x.png", "idiom": "tv", "scale": "\($0)x"] }])
    for scale in [1, 2] {
        try export(logo, to: set.appendingPathComponent("shelf@\(scale)x.png"), width: width * scale, height: 720 * scale)
    }
    assets.append(["filename": name + ".imageset", "idiom": "tv", "role": role, "size": "\(width)x720"])
}
try json(brand.appendingPathComponent("Contents.json"), ["info": metadata, "assets": assets])
try json(catalog.appendingPathComponent("AccentColor.colorset/Contents.json"), ["info": metadata,
    "colors": [["idiom": "universal", "color": ["color-space": "srgb", "components":
        ["red": "1.000", "green": "0.416", "blue": "0.286", "alpha": "1.000"]]]]])
print("Exported Nativecade Apple TV branding to \(catalog.path)")
