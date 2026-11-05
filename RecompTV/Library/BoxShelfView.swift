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
            // Actions read self.layout, the current focus: fast swipes send several moves before a redraw.
            Button { if games.indices.contains(self.layout.focus) { onPick(games[self.layout.focus]) } } label: {
                RealityView { content in
                    content.add(scene.root)
                    // The first half second is the scene loading, not the shelf moving.
                    var warmUp = 30
                    scene.frameSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                        if warmUp > 0 { warmUp -= 1 } else { ShelfFrameLog.record(event.deltaTime) }
                    }
                }
                .frame(height: 380)
            }
            .buttonStyle(SceneButtonStyle())
            .focused($focused)
            .onMoveCommand { direction in
                if direction == .left { focus = self.layout.moved(.left).focus }
                if direction == .right { focus = self.layout.moved(.right).focus }
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
        .task(id: ShelfKey(layout: layout, games: games.map(\.id), artwork: games.map(\.artwork))) {
            scene.show(layout, games: games, library: library)
        }
        .onDisappear { ShelfFrameLog.write() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(layout.focus + 1) of \(games.count)")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { focus = self.layout.moved(.right).focus }
            if direction == .decrement { focus = self.layout.moved(.left).focus }
        }
    }
}

/// Every shelf's frame times, summarized where Settings' Last game log shows them: the owner can't
/// pair the Apple TV, so a photo of that log is how the shelves' speed on it is measured.
@MainActor enum ShelfFrameLog {
    static let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Nativecade/Logs/shelf-frames.log")
    private static var frames = FrameTimes()

    static func record(_ seconds: TimeInterval) {
        frames.record(seconds)
        if frames.count % 120 == 0 { write() }
    }

    static func write() {
        guard let summary = frames.summary else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data((summary + "\n").utf8).write(to: url, options: .atomic)
    }
}

private struct ShelfKey: Equatable {
    let layout: ShelfLayout
    let games: [String]
    let artwork: [RomMArtwork?]
}

/// Draws a 3D scene's button unchanged: the scene shows focus itself.
struct SceneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// The RealityKit side of one shelf: a camera, lights and a plank, and a row of boxes that slides as
/// the focus moves. Only the boxes in view exist; each is drawn at once and gets RomM's faces when they arrive.
@MainActor final class ShelfScene {
    /// The shelf's width in view, in meters: a little less than the camera below sees across, about 1.4.
    static let viewportWidth: Float = 1.3
    static let curve = AnimationTimingFunction.cubicBezier(controlPoint1: [0.22, 1], controlPoint2: [0.36, 1])
    let root = Entity()
    /// Feeds ShelfFrameLog every frame the scene draws.
    var frameSubscription: EventSubscription?
    private let row = Entity()
    private var boxes = [String: Entity]()
    /// The artwork each box was built from; a box whose game's artwork changes is built again.
    private var builtFrom = [String: RomMArtwork?]()
    /// Each box's art load, with the artwork it's for; one whose box leaves the view gives way to the rest.
    private var loads = [String: (artwork: RomMArtwork?, task: Task<Void, Never>)]()
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
        let current = Dictionary(games.map { ($0.id, $0.artwork) }, uniquingKeysWith: { first, _ in first })
        for (id, box) in boxes where !visible.contains(id) || builtFrom[id] != current[id] {
            box.removeFromParent()
            boxes[id] = nil
        }
        for (id, load) in loads where !visible.contains(id) || load.artwork != current[id] {
            load.task.cancel()
            loads[id] = nil
        }
        for index in layout.visible {
            let rom = games[index]
            if let box = boxes[rom.id] {
                place(box, at: index, duration: first ? 0 : 0.55)
            } else if loads[rom.id] == nil {
                loads[rom.id] = (rom.artwork, Task {
                    await load(rom, library: library)
                    if loads[rom.id]?.artwork == rom.artwork, !Task.isCancelled { loads[rom.id] = nil }
                })
            }
        }
    }

    /// A drawn box first, which needs no network, so the shelf never sits empty while RomM answers;
    /// then RomM's faces replace it.
    private func load(_ rom: ImportedROM, library: LibraryModel) async {
        let loader = library.boxArt
        if let ready = loader.cached(for: rom) { return await build(rom, art: ready) }
        await build(rom, art: loader.drawn(for: rom))
        guard BoxFaces(rom.artwork).hasRemote else { return }
        let art = await loader.art(for: rom, library: library)
        guard !Task.isCancelled else { return }
        await build(rom, art: art)
    }

    /// Builds the box and puts it where the shelf is now, which may have moved while the art loaded.
    private func build(_ rom: ImportedROM, art: BoxArt) async {
        guard let box = try? await BoxEntities.box(art), !Task.isCancelled,
              let index = games.firstIndex(where: { $0.id == rom.id }), games[index].artwork == rom.artwork,
              layout?.visible.contains(index) == true else { return }
        boxes[rom.id]?.removeFromParent()
        boxes[rom.id] = box
        builtFrom[rom.id] = rom.artwork
        row.addChild(box)
        place(box, at: index, duration: 0)
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
