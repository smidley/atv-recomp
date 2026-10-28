@main
enum FrameEvidenceTests {
    static func main() {
        var evidence = FrameEvidence(generation: 1)
        precondition(evidence.status == .waiting)
        evidence.confirmVisibleFrame(for: 1)
        precondition(!evidence.visuallyConfirmed, "Early confirmation must be rejected")
        evidence.recordGPUCompletion(for: 1, error: nil)
        precondition(evidence.status == .needsVisualConfirmation, "GPU completion alone is not display evidence")
        precondition(evidence.canConfirmVisibility)
        evidence.confirmVisibleFrame(for: 1)
        precondition(evidence.status == .passed)
        precondition(!evidence.canConfirmVisibility, "Confirmed attempts need no second confirmation")

        evidence.recordGPUCompletion(for: 1, error: "Late GPU failure")
        precondition(evidence.status == .failed("Late GPU failure"), "Failure overrides a confirmed attempt")

        var failed = FrameEvidence(generation: 3)
        failed.recordGPUCompletion(for: 3, error: "GPU failure")
        failed.recordGPUCompletion(for: 3, error: nil)
        failed.confirmVisibleFrame(for: 3)
        precondition(failed.status == .failed("GPU failure"), "Failure must remain visible")
        precondition(!failed.visuallyConfirmed && !failed.canConfirmVisibility)

        var fresh = FrameEvidence(generation: 4)
        fresh.recordGPUCompletion(for: 3, error: nil)
        fresh.recordGPUCompletion(for: 3, error: "Old failure")
        fresh.confirmVisibleFrame(for: 3)
        precondition(fresh == FrameEvidence(generation: 4), "Old attempts must not affect a new test")
        fresh.recordGPUCompletion(for: 4, error: nil)
        fresh.confirmVisibleFrame(for: 3)
        precondition(fresh.status == .needsVisualConfirmation, "A stale confirmation cannot pass the new attempt")
        fresh.confirmVisibleFrame(for: 4)
        precondition(fresh.status == .passed)
        precondition(FrameEvidence(generation: 5).status == .waiting, "Reruns discard previous confirmation")
        print("PASS: GPU evidence, explicit visual confirmation, failures and stale-generation checks.")
    }
}
