import Testing
@testable import RecompSources

@Test func turnsTheBoxWithLeftAndRight() {
    var box = BoxInspection()
    _ = box.handle(.right); #expect(box.side == .right)
    _ = box.handle(.right); #expect(box.side == .back)
    for _ in 0..<3 { _ = box.handle(.left) }
    #expect(box.side == .left && box.quarterTurns == -1)
}

@Test func openingTurnsTheBoxBackToItsFront() {
    var box = BoxInspection()
    _ = box.handle(.right); _ = box.handle(.right)
    #expect(box.handle(.select) == nil)
    #expect(box.stage == .open && box.quarterTurns == 4 && box.side == .front)
}

@Test func selectStartsTheGameOnce() {
    var box = BoxInspection()
    _ = box.handle(.select)
    #expect(box.handle(.select) == .play)
    #expect(box.handle(.select) == nil && box.stage == .starting)
}

@Test func ignoresInputWhileStarting() {
    var box = BoxInspection()
    _ = box.handle(.select); _ = box.handle(.select)
    for input in [RemoteInput.back, .left, .right, .select] { #expect(box.handle(input) == nil) }
    #expect(box.stage == .starting)
}

@Test func backStepsOutOneStageAtATime() {
    var box = BoxInspection()
    _ = box.handle(.select)
    #expect(box.handle(.back) == nil && box.stage == .looking)
    #expect(box.handle(.back) == .dismiss)
}

@Test func upAndDownAreLeftToFocus() {
    var box = BoxInspection()
    #expect(box.handle(.up) == nil && box.handle(.down) == nil && box == BoxInspection())
}
