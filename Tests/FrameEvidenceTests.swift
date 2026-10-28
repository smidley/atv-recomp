@main
enum FrameEvidenceTests {
    static func main() {
        var evidence = FrameEvidence(generation: 1)
        precondition(evidence.status == .waiting)
        evidence.recordGPUCompletion(for: 1, error: nil)
        precondition(evidence.status == .waiting, "GPU completion alone is not presentation")
        for invalidTime in [0.0, -1.0, .infinity, .nan] {
            evidence.recordPresentation(for: 1, time: invalidTime)
            precondition(evidence.status == .waiting, "Dropped/invalid presentation is not evidence")
        }
        evidence.recordPresentation(for: 1, time: 10)
        precondition(evidence.status == .passed)

        var reversed = FrameEvidence(generation: 2)
        reversed.recordPresentation(for: 2, time: 11)
        precondition(reversed.status == .waiting, "Presentation alone is not GPU success")
        reversed.recordGPUCompletion(for: 2, error: nil)
        precondition(reversed.status == .passed, "Callback order must not affect the result")

        var failed = FrameEvidence(generation: 3)
        failed.recordGPUCompletion(for: 3, error: "GPU failure")
        failed.recordPresentation(for: 3, time: 12)
        failed.recordGPUCompletion(for: 3, error: nil)
        precondition(failed.status == .failed("GPU failure"), "Failure must remain visible")

        var fresh = FrameEvidence(generation: 4)
        fresh.recordGPUCompletion(for: 3, error: nil)
        fresh.recordGPUCompletion(for: 3, error: "Old failure")
        fresh.recordPresentation(for: 3, time: 12)
        precondition(fresh == FrameEvidence(generation: 4), "Old attempts must not affect a new test")
        print("PASS: presentation evidence, callback order, failures and stale-generation checks.")
    }
}
