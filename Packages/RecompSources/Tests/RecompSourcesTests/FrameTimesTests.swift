import Testing
@testable import RecompSources

@Test func summarizesWorstAndPercentile() {
    var frames = FrameTimes()
    for _ in 0..<99 { frames.record(1.0 / 60) }
    frames.record(0.040)
    #expect(frames.summary == "[shelf-frames] worst 40.0 ms · 95th percentile 16.7 ms · 100 frames")
}
@Test func noFramesNoSummary() { #expect(FrameTimes().summary == nil) }
