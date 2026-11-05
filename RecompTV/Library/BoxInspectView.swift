import RealityKit
import RecompSources
import SwiftUI
import UIKit

/// A picked game's box, brought forward over the library: left and right turn it, Select opens it so
/// its cartridge comes out, and Select again starts the game. Back puts things away one step at a time.
@MainActor
struct BoxInspectView: View {
    let rom: ImportedROM
    let library: LibraryModel
    /// Remote presses applied once the box is shown, for the simulator fixtures.
    var initialInputs: [RemoteInput] = []
    @Environment(\.dismiss) private var dismiss
    @State private var inspection = BoxInspection()
    @State private var scene = InspectScene()
    @State private var unavailable = false
    @FocusState private var sceneFocused: Bool

    var body: some View {
        let favorite = library.favorites.contains(rom.id)
        VStack(alignment: .leading, spacing: 24) {
            // A button, so the remote's Select reaches it; its style draws the scene unchanged.
            Button { press(.select) } label: {
                RealityView { content in
                    content.add(scene.root)
                    // The first half second is the scene loading, not the shelf moving.
                    var warmUp = 30
                    scene.frameSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                        if warmUp > 0 { warmUp -= 1 } else { ShelfFrameLog.record(event.deltaTime) }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 640)
            }
            .buttonStyle(SceneButtonStyle())
            .focused($sceneFocused)
            .onMoveCommand { direction in
                if direction == .left { press(.left) }
                if direction == .right { press(.right) }
            }
            .onExitCommand { press(.back) }
            .accessibilityLabel(rom.title)
            .accessibilityValue(inspection.stage == .looking ? "\(inspection.side)" : "Open")
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(rom.title).font(.title3).fontWeight(.medium)
                    Text([rom.revision, rom.name].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(unavailable ? "Use the Nativecade scheme to build the playable app"
                     : inspection.stage == .looking ? "Swipe to turn it · Select opens it" : "Select plays · Back puts it away")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button { library.toggleFavorite(rom) } label: {
                Label(favorite ? "Remove from Favorites" : "Add to Favorites", systemImage: favorite ? "star.fill" : "star")
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await scene.load(rom, library: library)
            for input in initialInputs { press(input, animated: false) }
        }
        .onAppear { sceneFocused = true }
        .onDisappear { ShelfFrameLog.write() }
    }

    private func press(_ input: RemoteInput, animated: Bool = true) {
        if input == .select, inspection.stage == .open, library.isImporting { return }
        let effect = inspection.handle(input)
        switch effect {
        case .play?:
            if GameRuntime.available {
                Task { await library.play(rom) }
                dismiss()
                return
            }
            // The harness build can't play; the cartridge stays out and the caption says why.
            unavailable = true
            var open = BoxInspection()
            _ = open.handle(.select)
            inspection = open
        case .dismiss?:
            dismiss()
            return
        case nil:
            break
        }
        scene.show(inspection, animated: animated)
    }
}

/// The RealityKit side of a picked box: a camera, lights and the box, which turns, and opens to bring
/// its cartridge forward.
@MainActor final class InspectScene {
    let root = Entity()
    var frameSubscription: EventSubscription?
    private var box: ModelEntity?
    private var materials = [any RealityKit.Material]()
    private var shown = BoxInspection()
    private static let cartridgeRest = (ShelfMetrics.cartridge.y - ShelfMetrics.box.y) / 2 + 0.004

    init() {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 30
        camera.look(at: [0, 0.01, 0], from: [0, 0.03, 0.45], relativeTo: nil)
        root.addChild(camera)
        root.addChild(BoxEntities.lights())
    }

    func load(_ rom: ImportedROM, library: LibraryModel) async {
        let art = await library.boxArt.art(for: rom, library: library)
        guard let box = try? await BoxEntities.box(art) else { return }
        materials = box.model?.materials ?? []
        // It enters from below center, growing into place.
        box.transform = Transform(scale: [0.6, 0.6, 0.6], rotation: simd_quatf(), translation: [0, -0.2, 0])
        root.addChild(box)
        self.box = box
        box.move(to: Transform(), relativeTo: root, duration: 0.6, timingFunction: ShelfScene.curve)
        show(shown, animated: false)
    }

    func show(_ inspection: BoxInspection, animated: Bool) {
        shown = inspection
        guard let box else { return }
        let open = inspection.stage != .looking
        let turned = Transform(scale: .one, rotation: simd_quatf(angle: -Float(inspection.quarterTurns) * .pi / 2, axis: [0, 1, 0]),
                               translation: .zero)
        // A set without animation also ends one still running, such as the entrance.
        if animated { box.move(to: turned, relativeTo: root, duration: 0.6, timingFunction: ShelfScene.curve) }
        else { box.stopAllAnimations(); box.transform = turned }
        // Open, the box dims behind its cartridge.
        box.model?.materials = open ? materials.map(Self.dimmed) : materials
        guard let cartridge = box.findEntity(named: "cartridge") else { return }
        var lifted = cartridge.transform
        lifted.translation = open ? [0, Self.cartridgeRest + 0.06, 0.10] : [0, Self.cartridgeRest, 0]
        if animated { cartridge.move(to: lifted, relativeTo: box, duration: 0.7, timingFunction: ShelfScene.curve) }
        else { cartridge.stopAllAnimations(); cartridge.transform = lifted }
    }

    private static func dimmed(_ material: any RealityKit.Material) -> any RealityKit.Material {
        guard var material = material as? PhysicallyBasedMaterial else { return material }
        var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 1
        material.baseColor.tint.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        material.baseColor.tint = UIColor(red: red * 0.45, green: green * 0.45, blue: blue * 0.45, alpha: alpha)
        return material
    }
}
