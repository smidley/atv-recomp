import RealityKit
import RecompSources
import SwiftUI
import UIKit

/// The 3D pieces of a shelf: a game's box with its cartridge inside, the walnut plank and the lights.
/// Sizes are in meters, from `ShelfMetrics`.
@MainActor enum BoxEntities {
    /// The cartridge's grey plastic.
    static let cartridgeGrey = UIColor(red: 0.553, green: 0.561, blue: 0.580, alpha: 1)

    enum Face {
        case image(CGImage)
        case color(UIColor)
    }

    /// A game's box, with its cartridge resting inside as the child named "cartridge".
    static func box(_ art: BoxArt) async throws -> ModelEntity {
        let edge = Face.color(UIColor(art.tint).withAlphaComponent(1))
        let box = try await box(faces: [.image(art.front), edge, .image(art.back), edge, .image(art.spine), .image(art.spine)])
        let cartridge = try await cartridge(art.cartridge)
        cartridge.name = "cartridge"
        cartridge.position.y = (ShelfMetrics.cartridge.y - ShelfMetrics.box.y) / 2 + 0.004
        box.addChild(cartridge)
        return box
    }

    /// A box from six faces, in `generateBox`'s split order: front, top, back, bottom, right, left.
    static func box(faces: [Face]) async throws -> ModelEntity {
        let size = ShelfMetrics.box
        let mesh = MeshResource.generateBox(width: size.x, height: size.y, depth: size.z, cornerRadius: 0.002, splitFaces: true)
        var materials = [PhysicallyBasedMaterial]()
        for face in faces { materials.append(try await material(face, roughness: 0.55)) }
        let box = ModelEntity(mesh: mesh, materials: materials)
        box.components.set(GroundingShadowComponent(castsShadow: true))
        return box
    }

    /// A grey cartridge. RomM's photo of the cartridge covers its whole front; a drawn label sits low on it.
    static func cartridge(_ art: CartridgeArt) async throws -> Entity {
        let size = ShelfMetrics.cartridge
        let body = ModelEntity(mesh: .generateBox(width: size.x, height: size.y, depth: size.z, cornerRadius: 0.003),
                               materials: [material(cartridgeGrey, roughness: 0.45)])
        let face: ModelEntity
        switch art {
        case .photo(let photo):
            face = ModelEntity(mesh: .generatePlane(width: size.x, height: size.y, cornerRadius: 0.003),
                               materials: [try await material(.image(photo), roughness: 0.45)])
        case .label(let label):
            face = ModelEntity(mesh: .generatePlane(width: size.x * 0.84, height: size.y * 0.64, cornerRadius: 0.002),
                               materials: [try await material(.image(label), roughness: 0.5)])
            face.position.y = -size.y * 0.12
        }
        face.position.z = size.z / 2 + 0.0005
        body.addChild(face)
        body.components.set(GroundingShadowComponent(castsShadow: true))
        return body
    }

    /// A walnut plank whose top is at y = 0, where boxes stand.
    static func shelf(width: Float) -> ModelEntity {
        let plank = ModelEntity(mesh: .generateBox(width: width, height: 0.026, depth: 0.18),
                                materials: [material(UIColor(red: 0.231, green: 0.173, blue: 0.133, alpha: 1), roughness: 0.6)])
        plank.position.y = -0.013
        return plank
    }

    /// A key light from above and in front, casting the boxes' shadows, and a dim fill from the left.
    static func lights() -> Entity {
        let lights = Entity()
        let key = DirectionalLight()
        key.light.intensity = 3000
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 3, depthBias: 2)
        key.look(at: .zero, from: [0.3, 0.8, 0.9], relativeTo: nil)
        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.look(at: .zero, from: [-0.6, 0.3, 0.8], relativeTo: nil)
        lights.addChild(key)
        lights.addChild(fill)
        return lights
    }

    private static func material(_ face: Face, roughness: Float) async throws -> PhysicallyBasedMaterial {
        switch face {
        case .image(let image):
            var material = material(.white, roughness: roughness)
            material.baseColor = .init(texture: .init(try await TextureResource(image: image, options: .init(semantic: .color))))
            return material
        case .color(let color):
            return material(color, roughness: roughness)
        }
    }

    private static func material(_ color: UIColor, roughness: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = 0.0
        return material
    }
}

#if DEBUG && targetEnvironment(simulator)
/// `--setup-fixture-step box-faces`: one box four times, turned 0, 90, 180 and 270 degrees, each face a
/// named color, so a screenshot shows which material lands on which face. Turning a box 90 degrees
/// brings its left face to the camera, so the expected names are front, left, back and right.
struct BoxFacesFixture: View {
    var body: some View {
        RealityView { content in
            let names = ["front", "top", "back", "bottom", "right", "left"]
            let colors: [UIColor] = [.systemRed, .systemGreen, .systemBlue, .systemYellow, .systemOrange, .systemPurple]
            let faces = names.indices.map { BoxEntities.Face.image(Self.label(names[$0], colors[$0])) }
            for turn in 0..<4 {
                guard let box = try? await BoxEntities.box(faces: faces) else { continue }
                box.position = [Float(turn) * 0.26 - 0.39, 0, 0]
                box.orientation = simd_quatf(angle: Float(turn) * .pi / 2, axis: [0, 1, 0])
                content.add(box)
            }
            content.add(BoxEntities.lights())
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 40
            camera.look(at: .zero, from: [0, 0.12, 1.1], relativeTo: nil)
            content.add(camera)
        }
        .background(Palette.page)
    }

    private static func label(_ name: String, _ color: UIColor) -> CGImage {
        UIGraphicsImageRenderer(size: CGSize(width: 340, height: 248)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 340, height: 248))
            (name as NSString).draw(at: CGPoint(x: 24, y: 24),
                                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 56), .foregroundColor: UIColor.white])
        }.cgImage!
    }
}
#endif
