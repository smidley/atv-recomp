/// A Siri Remote press, as the box shelf and the picked box handle it.
public enum RemoteInput: Sendable {
    case left, right, up, down, select, back
}

/// The side of a box facing the viewer.
public enum BoxSide: Sendable {
    case front, right, back, left
}

/// A picked game's box: left and right turn it, Select opens it, and Select again starts the game.
/// Back steps out one stage at a time; up and down are left to the focus engine.
public struct BoxInspection: Equatable, Sendable {
    public enum Stage: Equatable, Sendable { case looking, open, starting }
    public enum Effect: Equatable, Sendable { case play, dismiss }

    public private(set) var stage = Stage.looking
    /// Quarter turns so far, right adding one. Cumulative, so the box keeps turning the same way.
    public private(set) var quarterTurns = 0
    public var side: BoxSide { [BoxSide.front, .right, .back, .left][(quarterTurns % 4 + 4) % 4] }

    public init() {}

    public mutating func handle(_ input: RemoteInput) -> Effect? {
        switch (stage, input) {
        case (.looking, .left): quarterTurns -= 1
        case (.looking, .right): quarterTurns += 1
        case (.looking, .select):
            // It opens facing front: the nearest whole turn, halves away from zero.
            quarterTurns = Int((Double(quarterTurns) / 4).rounded()) * 4
            stage = .open
        case (.looking, .back): return .dismiss
        case (.open, .select): stage = .starting; return .play
        case (.open, .back): stage = .looking
        default: break
        }
        return nil
    }
}
