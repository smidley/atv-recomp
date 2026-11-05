/// Where one face of a game's 3D box comes from: RomM's art, or drawn by the app.
public enum BoxFaceSource: Equatable, Sendable {
    case remote(String)
    case drawn
}

/// A game's box faces and cartridge label. The front falls back to the cover; anything RomM
/// doesn't have is drawn, so every game still appears as a whole box.
public struct BoxFaces: Equatable, Sendable {
    public let front, back, spine, label: BoxFaceSource

    init(front: BoxFaceSource, back: BoxFaceSource, spine: BoxFaceSource, label: BoxFaceSource) {
        self.front = front; self.back = back; self.spine = spine; self.label = label
    }

    /// Whether any face comes from RomM; a game without one never waits on the network.
    public var hasRemote: Bool {
        [front, back, spine, label].contains { if case .remote = $0 { true } else { false } }
    }

    public init(_ artwork: RomMArtwork?) {
        func source(_ path: String?) -> BoxFaceSource { path.map(BoxFaceSource.remote) ?? .drawn }
        self.init(front: source(artwork?.boxFront ?? artwork?.coverLarge ?? artwork?.coverSmall),
                  back: source(artwork?.boxBack), spine: source(artwork?.boxSpine), label: source(artwork?.media))
    }
}
