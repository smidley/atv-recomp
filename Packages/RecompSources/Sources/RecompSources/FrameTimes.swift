import Foundation

/// A shelf's frame durations, summarized for the game log the owner can photograph: the worst frame
/// and the 95th percentile, by nearest rank. It keeps about the last minute at 60 frames a second.
public struct FrameTimes: Sendable {
    private var durations = [Double]()

    public init() {}

    public mutating func record(_ seconds: Double) {
        // Dropping the older half now and then keeps memory and the summary's sort small.
        if durations.count >= 7200 { durations.removeFirst(3600) }
        durations.append(seconds)
    }

    public var count: Int { durations.count }

    public var summary: String? {
        guard let worst = durations.max() else { return nil }
        let sorted = durations.sorted()
        let percentile = sorted[Int((Double(sorted.count) * 0.95).rounded(.up)) - 1]
        func milliseconds(_ seconds: Double) -> String { String(format: "%.1f ms", seconds * 1000) }
        return "[shelf-frames] worst \(milliseconds(worst)) · 95th percentile \(milliseconds(percentile)) · \(sorted.count) frames"
    }
}
