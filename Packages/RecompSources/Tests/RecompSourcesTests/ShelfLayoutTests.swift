import Testing
@testable import RecompSources

@Test func facingBoxesStandAPitchApart() {
    #expect(ShelfLayout(count: 5, style: .facing, focus: 0, viewportWidth: 1).placement(of: 3).x == 3 * ShelfMetrics.facingPitch)
}
@Test func focusedFacingBoxComesForwardWithItsCartridgeUp() {
    let layout = ShelfLayout(count: 5, style: .facing, focus: 2, viewportWidth: 1)
    #expect(layout.placement(of: 2).forward == 0.045 && layout.placement(of: 2).cartridgeRise > 0)
    #expect(layout.placement(of: 1).forward == 0 && layout.placement(of: 1).cartridgeRise == 0)
}
@Test func spinesPartAroundTheFocusedBox() {
    let layout = ShelfLayout(count: 10, style: .spines, focus: 4, viewportWidth: 1)
    #expect(layout.placement(of: 3).x == 3 * ShelfMetrics.spinePitch - ShelfMetrics.spineParting)
    #expect(layout.placement(of: 5).x == 5 * ShelfMetrics.spinePitch + ShelfMetrics.spineParting)
    #expect(abs(layout.placement(of: 4).yaw - 0.314) < 0.001 && layout.placement(of: 3).yaw == .pi / 2)
}
@Test func restingShelfRaisesNothing() {
    let layout = ShelfLayout(count: 10, style: .spines, focus: 4, viewportWidth: 1, raised: false)
    #expect(layout.placement(of: 4).forward == 0 && layout.placement(of: 3).x == 3 * ShelfMetrics.spinePitch)
}
@Test func onlyBoxesOnScreenAreDrawn() {
    let visible = ShelfLayout(count: 50, style: .facing, focus: 25, viewportWidth: 1).visible
    #expect(visible.contains(25) && !visible.contains(0) && !visible.contains(49) && visible.count < 10)
}
@Test func oneBoxShelfIgnoresMoves() {
    let layout = ShelfLayout(count: 1, style: .facing, focus: 0, viewportWidth: 1)
    #expect(layout.moved(.right).focus == 0 && layout.moved(.left).focus == 0 && layout.visible == 0..<1)
}
@Test func movesClampAtTheEnds() {
    #expect(ShelfLayout(count: 3, style: .facing, focus: 2, viewportWidth: 1).moved(.right).focus == 2)
    #expect(ShelfLayout(count: 3, style: .facing, focus: 0, viewportWidth: 1).moved(.left).focus == 0)
}
@Test func emptyShelfDrawsNothing() {
    #expect(ShelfLayout(count: 0, style: .spines, focus: 0, viewportWidth: 1).visible.isEmpty)
}
@Test func wallRowsChunkGames() {
    #expect(ShelfLayout.rows(Array(0..<20), style: .facing).map(\.count) == [8, 8, 4])
}

// The camera sees past the row's start, and boxes slide for 0.55 s after the focus moves.
@Test func keepsBoxesOnScreenThroughASlide() {
    #expect(ShelfLayout(count: 10, style: .facing, focus: 5, viewportWidth: 1.3).visible.contains(1))
}
@Test func spinesNearTheLeftEdgeStayDrawn() {
    #expect(ShelfLayout(count: 24, style: .spines, focus: 11, viewportWidth: 1.3).visible.contains(0))
}
