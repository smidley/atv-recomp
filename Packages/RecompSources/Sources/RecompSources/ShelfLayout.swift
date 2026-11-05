/// How a shelf stands its boxes, chosen in Settings.
public enum ShelfStyle: String, Codable, CaseIterable, Sendable {
    case facing, spines

    public var title: String { self == .facing ? "Facing you" : "Spines out" }
    /// Games per shelf on a platform's page.
    public var wallRowLength: Int { self == .facing ? 8 : 24 }
}

/// Sizes in meters, from the design's mockups (1 cqw there is 0.01 m here).
public enum ShelfMetrics {
    /// A Nintendo 64 box: width, height, depth.
    public static let box = SIMD3<Float>(0.17, 0.124, 0.034)
    public static let cartridge = SIMD3<Float>(0.106, 0.069, 0.015)
    public static let facingPitch: Float = 0.195
    public static let spinePitch: Float = 0.0375
    /// How far the boxes beside a focused spine slide apart.
    public static let spineParting: Float = 0.07
    /// How far left of the row's start the shelf camera still sees: about 0.17 m, plus a box still
    /// sliding out of view for 0.55 s after the focus moves.
    public static let viewMargin: Float = 0.2
}

/// Where one box stands on its shelf.
public struct BoxPlacement: Equatable, Sendable {
    public var x: Float, lift: Float, forward: Float
    /// Radians: 0 faces the viewer, .pi / 2 shows the spine.
    public var yaw: Float
    /// How far the cartridge stands up out of the box.
    public var cartridgeRise: Float
}

/// A shelf's boxes: where each stands, which one is focused, and which are worth drawing.
public struct ShelfLayout: Equatable, Sendable {
    public let count: Int, style: ShelfStyle, focus: Int
    public let viewportWidth: Float
    /// False on a shelf without focus: no box comes forward and nothing parts.
    public let raised: Bool

    public init(count: Int, style: ShelfStyle, focus: Int, viewportWidth: Float, raised: Bool = true) {
        self.count = max(count, 0); self.style = style
        self.focus = min(max(focus, 0), max(count - 1, 0))
        self.viewportWidth = viewportWidth; self.raised = raised
    }

    private var pitch: Float { style == .facing ? ShelfMetrics.facingPitch : ShelfMetrics.spinePitch }
    private static let rise = ShelfMetrics.box.y - 0.32 * ShelfMetrics.cartridge.y - 0.005

    public func placement(of index: Int) -> BoxPlacement {
        let focused = raised && index == focus
        var x = Float(index) * pitch
        switch style {
        case .facing:
            return BoxPlacement(x: x, lift: focused ? 0.012 : 0, forward: focused ? 0.045 : 0, yaw: 0,
                                cartridgeRise: focused ? Self.rise : 0)
        case .spines:
            if raised && !focused { x += index < focus ? -ShelfMetrics.spineParting : ShelfMetrics.spineParting }
            return BoxPlacement(x: x, lift: focused ? 0.012 : 0, forward: focused ? 0.06 : 0, yaw: focused ? 0.314 : .pi / 2,
                                cartridgeRise: focused ? Self.rise : 0)
        }
    }

    /// How far the shelf has slid left, keeping the focused box near the left third of the view.
    public var scroll: Float { max(0, Float(focus) * pitch - 0.3 * viewportWidth) }

    /// The boxes on screen, plus one on each side, and those the camera still sees left of the row's start.
    public var visible: Range<Int> {
        let shown = (0..<count).filter {
            let x = placement(of: $0).x - scroll
            return x >= -(pitch + ShelfMetrics.viewMargin) && x <= viewportWidth + pitch
        }
        guard let first = shown.first, let last = shown.last else { return 0..<0 }
        return first..<(last + 1)
    }

    public func moved(_ input: RemoteInput) -> ShelfLayout {
        let step = input == .left ? -1 : input == .right ? 1 : 0
        guard step != 0 else { return self }
        return ShelfLayout(count: count, style: style, focus: focus + step, viewportWidth: viewportWidth, raised: raised)
    }

    /// A platform's games split into shelves of `style.wallRowLength`.
    public static func rows<T>(_ items: [T], style: ShelfStyle) -> [[T]] {
        stride(from: 0, to: items.count, by: style.wallRowLength).map {
            Array(items[$0..<min($0 + style.wallRowLength, items.count)])
        }
    }
}
