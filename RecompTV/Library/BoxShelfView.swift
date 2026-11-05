import RealityKit
import RecompSources
import SwiftUI

/// A row of games as 3D boxes on a walnut shelf, facing out or spines out. Left and right move the
/// focus along it, Select picks the focused game, and up and down leave it for the next shelf.
@MainActor
struct BoxShelfView: View {
    let games: [ImportedROM]
    let style: ShelfStyle
    let library: LibraryModel
    let onPick: (ImportedROM) -> Void
    @State private var focus = 0
    @State private var scene = ShelfScene()
    @FocusState private var focused: Bool

    private var layout: ShelfLayout {
        ShelfLayout(count: games.count, style: style, focus: focus, viewportWidth: ShelfScene.viewportWidth, raised: focused)
    }

    var body: some View {
        let layout = layout
        let title = games.indices.contains(layout.focus) ? games[layout.focus].title : ""
        VStack(alignment: .leading, spacing: 12) {
            // A button, so the remote's Select reaches it; its style draws the scene unchanged.
            Button { if games.indices.contains(layout.focus) { onPick(games[layout.focus]) } } label: {
                RealityView { content in content.add(scene.root) }
                    .frame(height: 380)
            }
            .buttonStyle(SceneButtonStyle())
            .focused($focused)
            .onMoveCommand { direction in
                if direction == .left { focus = layout.moved(.left).focus }
                if direction == .right { focus = layout.moved(.right).focus }
            }
            // Kept in the layout while hidden, so shelves don't jump as focus moves between them.
            HStack(spacing: 16) {
                Text(title).fontWeight(.medium)
                PlaysNowMark()
                Text("Plays now").foregroundStyle(.secondary)
            }
            .font(.callout)
            .opacity(focused ? 1 : 0)
        }
        .task(id: ShelfKey(layout: layout, games: games.map(\.id))) {
            scene.show(layout, games: games, library: library)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(layout.focus + 1) of \(games.count)")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { focus = layout.moved(.right).focus }
            if direction == .decrement { focus = layout.moved(.left).focus }
        }
    }
}

private struct ShelfKey: Equatable {
    let layout: ShelfLayout
    let games: [String]
}

/// Draws a 3D scene's button unchanged: the scene shows focus itself.
struct SceneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// The RealityKit side of one shelf: a camera, lights and a plank, and a row of boxes that slides as
/// the focus moves. Only the boxes in view exist; each is built once its art is ready.
@MainActor final class ShelfScene {
    /// The shelf's width in view, in meters: a little less than the camera below sees across, about 1.4.
    static let viewportWidth: Float = 1.3
    static let curve = AnimationTimingFunction.cubicBezier(controlPoint1: [0.22, 1], controlPoint2: [0.36, 1])
    let root = Entity()
    private let row = Entity()
    private var boxes = [String: Entity]()
    private var loading = Set<String>()
    private var layout: ShelfLayout?
    private var games = [ImportedROM]()
    /// Where the first box stands: far enough in that it stays whole when it turns to face the viewer.
    private static let start = -viewportWidth / 2 + ShelfMetrics.box.x / 2 + 0.05

    init() {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 20
        camera.look(at: [0, 0.07, 0], from: [0, 0.2, 0.9], relativeTo: nil)
        root.addChild(camera)
        root.addChild(BoxEntities.lights())
        // Longer than any row, so its ends never come into view.
        root.addChild(BoxEntities.shelf(width: 60))
        row.position.x = Self.start
        root.addChild(row)
    }

    func show(_ layout: ShelfLayout, games: [ImportedROM], library: LibraryModel) {
        let first = self.layout == nil
        self.layout = layout
        self.games = games
        var slide = row.transform
        slide.translation.x = Self.start - layout.scroll
        move(row, to: slide, duration: first ? 0 : 0.55)
        let visible = Set(layout.visible.map { games[$0].id })
        for (id, box) in boxes where !visible.contains(id) {
            box.removeFromParent()
            boxes[id] = nil
        }
        for index in layout.visible {
            let rom = games[index]
            if let box = boxes[rom.id] {
                place(box, at: index, duration: first ? 0 : 0.55)
            } else if !loading.contains(rom.id) {
                loading.insert(rom.id)
                Task {
                    defer { loading.remove(rom.id) }
                    let art = await library.boxArt.art(for: rom, library: library)
                    // Placed where the shelf is now, which may have moved while the art loaded.
                    guard let box = try? await BoxEntities.box(art), boxes[rom.id] == nil,
                          let index = self.games.firstIndex(where: { $0.id == rom.id }),
                          self.layout?.visible.contains(index) == true else { return }
                    boxes[rom.id] = box
                    row.addChild(box)
                    place(box, at: index, duration: 0)
                }
            }
        }
    }

    private func place(_ box: Entity, at index: Int, duration: TimeInterval) {
        guard let layout else { return }
        let placement = layout.placement(of: index)
        move(box, to: Transform(scale: .one, rotation: simd_quatf(angle: placement.yaw, axis: [0, 1, 0]),
                                translation: [placement.x, ShelfMetrics.box.y / 2 + placement.lift, placement.forward]),
             duration: duration)
        if let cartridge = box.findEntity(named: "cartridge") {
            var lifted = cartridge.transform
            lifted.translation.y = (ShelfMetrics.cartridge.y - ShelfMetrics.box.y) / 2 + 0.004 + placement.cartridgeRise
            move(cartridge, to: lifted, duration: duration == 0 ? 0 : 0.6)
        }
    }

    /// Moves an entity relative to its parent, at once or along the app's one easing curve.
    private func move(_ entity: Entity, to transform: Transform, duration: TimeInterval) {
        if duration == 0 { entity.stopAllAnimations(); entity.transform = transform }
        else { entity.move(to: transform, relativeTo: entity.parent, duration: duration, timingFunction: Self.curve) }
    }
}
