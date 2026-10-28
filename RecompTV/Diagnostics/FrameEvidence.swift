// Value-only state shared by the harness and its host-side Swift tests.
struct FrameEvidence: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case waiting
        case needsVisualConfirmation
        case passed
        case failed(String)
    }

    let generation: UInt64
    private(set) var gpuCompleted = false
    private(set) var visuallyConfirmed = false
    private(set) var failure: String?

    var status: Status {
        if let failure { return .failed(failure) }
        guard gpuCompleted else { return .waiting }
        return visuallyConfirmed ? .passed : .needsVisualConfirmation
    }

    var canConfirmVisibility: Bool { status == .needsVisualConfirmation }

    mutating func recordGPUCompletion(for generation: UInt64, error: String?) {
        guard generation == self.generation else { return }
        if let error {
            // A later callback must never turn a failed attempt into a pass.
            failure = failure ?? error
        } else {
            gpuCompleted = true
        }
    }

    // A user observation, never an inferred display timestamp. tvOS doesn't
    // expose the drawable presentation callback used by other Apple platforms.
    mutating func confirmVisibleFrame(for generation: UInt64) {
        guard generation == self.generation, canConfirmVisibility else { return }
        visuallyConfirmed = true
    }
}
