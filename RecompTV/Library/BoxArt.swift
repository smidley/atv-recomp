import CoreImage
import SwiftUI
import RecompSources
import UIKit

/// What's on a game's cartridge: RomM's photo of the whole cartridge, or a drawn label for the grey body.
enum CartridgeArt {
    case photo(CGImage)
    case label(CGImage)
}

/// The images for one game's 3D box. The spine image goes on both sides.
struct BoxArt {
    let front, back, spine: CGImage
    let cartridge: CartridgeArt
    let tint: Color
}

/// Loads each game's box faces from RomM and draws the ones it doesn't have, once per game. A face
/// that fails to load, offline or after its connection is removed, is drawn instead.
@MainActor final class BoxArtLoader {
    private var cache = [String: BoxArt]()

    func art(for rom: ImportedROM, library: LibraryModel) async -> BoxArt {
        if let cached = cache[rom.id] { return cached }
        let faces = BoxFaces(rom.artwork)
        func image(_ source: BoxFaceSource) async -> CGImage? {
            guard case .remote(let path) = source, let artwork = rom.artwork,
                  let data = await library.artworkData(at: path, artwork: artwork, sourceID: rom.sourceID) else { return nil }
            return UIImage(data: data)?.cgImage
        }
        let cover = await image(faces.front)
        let tint = cover.flatMap(Self.averageColor) ?? Palette.raised
        var screenshots = [CGImage]()
        for path in (rom.artwork?.screenshots ?? []).prefix(2) {
            if let shot = await image(.remote(path)) { screenshots.append(shot) }
        }
        let title = rom.title
        let back = await image(faces.back)
        let spine = await image(faces.spine)
        let photo = await image(faces.label)
        let art = BoxArt(
            front: cover ?? Self.render(TitleArt(title: title), width: 340, height: 248),
            back: back ?? Self.render(DrawnBack(title: title, summary: rom.artwork?.summary, screenshots: screenshots, tint: tint),
                                      width: 340, height: 248),
            spine: spine ?? Self.render(DrawnSpine(title: title, tint: tint), width: 68, height: 248),
            // The drawn label is sized to the label printed on the cartridge's face, about 2 to 1.
            cartridge: photo.map(CartridgeArt.photo)
                ?? .label(Self.render(DrawnLabel(title: title, cover: cover, tint: tint), width: 212, height: 105)),
            tint: tint)
        cache[rom.id] = art
        return art
    }

    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// The cover's average color, for the drawn spine's stripe and the back's wash.
    static func averageColor(_ image: CGImage) -> Color? {
        let input = CIImage(cgImage: image)
        guard let output = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input,
                                                                         kCIInputExtentKey: CIVector(cgRect: input.extent)])?.outputImage
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8,
                       colorSpace: nil)
        return Color(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }

    /// A drawn face at twice its point size, in the app's dark appearance.
    private static func render(_ view: some View, width: CGFloat, height: CGFloat) -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height).environment(\.colorScheme, .dark))
        renderer.scale = 2
        if let image = renderer.cgImage { return image }
        // Rendering can't fail for these views; a plain face beats a missing one if it ever does.
        let fallback = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            UIColor(Palette.raised).setFill(); context.fill(context.format.bounds)
        }
        return fallback.cgImage!
    }
}

private let spineColor = Color(red: 0.082, green: 0.090, blue: 0.114)  // #15171D
private let backColor = Color(red: 0.063, green: 0.071, blue: 0.090)   // #101217

/// A spine for a box RomM has no spine for: the title down a dark band, under a stripe of the cover's color.
private struct DrawnSpine: View {
    let title: String, tint: Color

    var body: some View {
        VStack(spacing: 0) {
            tint.frame(height: 36)
            // Laid out across, then turned to read top to bottom like a real spine.
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(2).truncationMode(.tail)
                .frame(width: 156, height: 56, alignment: .leading)
                .rotationEffect(.degrees(90))
                .frame(width: 68, height: 168)
            Text("Nintendo 64").font(.system(size: 11)).foregroundStyle(Color(white: 0.64)).frame(height: 44)
        }
        .frame(width: 68, height: 248)
        .background(spineColor)
    }
}

/// A back for a box RomM has no back for: the title, two screenshots and RomM's description.
private struct DrawnBack: View {
    let title: String, summary: String?, screenshots: [CGImage], tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            HStack(alignment: .top, spacing: 12) {
                if !screenshots.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(screenshots.indices, id: \.self) { index in
                            Image(decorative: screenshots[index], scale: 1).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 80).clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
                Text(summary ?? "").font(.system(size: 11)).foregroundStyle(Color(white: 0.78)).lineLimit(6)
            }
            Spacer(minLength: 0)
            Text("Nintendo 64").font(.system(size: 10)).foregroundStyle(Color(white: 0.64))
        }
        .padding(16)
        .frame(width: 340, height: 248, alignment: .topLeading)
        .background(tint.opacity(0.22))
        .background(backColor)
    }
}

/// A cartridge label for a game RomM has no cartridge art for: its cover, or its title on the cover's color.
private struct DrawnLabel: View {
    let title: String, cover: CGImage?, tint: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let cover {
                Image(decorative: cover, scale: 1).resizable().aspectRatio(contentMode: .fill)
            } else {
                tint
                LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(2).padding(8)
            }
        }
        .frame(width: 212, height: 105)
        .clipped()
    }
}
