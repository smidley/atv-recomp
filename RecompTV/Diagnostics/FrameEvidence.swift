// Value-only state shared by the harness and its host-side Swift tests.
struct FrameEvidence: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case waiting
        case passed
        case failed(String)
    }

    let generation: UInt64
    private(set) var gpuCompleted = false
    private(set) var presentedTime: Double?
    private(set) var failure: String?

    var status: Status {
        if let failure { return .failed(failure) }
        return gpuCompleted && presentedTime != nil ? .passed : .waiting
    }

    mutating func recordGPUCompletion(for generation: UInt64, error: String?) {
        guard generation == self.generation else { return }
        if let error {
            // A later callback must never turn a failed attempt into a pass.
            failure = failure ?? error
        } else {
            gpuCompleted = true
        }
    }

    mutating func recordPresentation(for generation: UInt64, time: Double) {
        guard generation == self.generation, time.isFinite, time > 0 else { return }
        presentedTime = time
    }
}
