import Metal
import Observation
import UIKit

@MainActor
@Observable
final class ProbeSession {
    let nativeAnswer = RTVBridgeAdd(19, 23)
    let device: (any MTLDevice)?
    let commandQueue: (any MTLCommandQueue)?
    let systemVersion = UIDevice.current.systemVersion

    private(set) var colorIndex: UInt32 = 0
    private(set) var isActive = false
    private(set) var evidence = FrameEvidence(generation: 0)
    private(set) var drawableDescription = "Not acquired"

    init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        commandQueue = device?.makeCommandQueue()
        commandQueue?.label = "RecompTV foundation probe"
    }

    var bridgePassed: Bool { nativeAnswer == 42 }

    var colorName: String {
        switch colorIndex {
        case 0: "Blue"
        case 1: "Green"
        default: "Red"
        }
    }

    var environment: String {
        #if targetEnvironment(simulator)
        "tvOS Simulator — device validation still required"
        #else
        "tvOS device build — record the Apple TV model separately"
        #endif
    }

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        // Invalidate callbacks from the preceding scene activation on both
        // suspend and resume. UIKit, rendering requests and UI state are main-actor owned.
        rerun()
    }

    func nextColor() {
        let count = RTVTestColorCount()
        guard count > 0 else { return }
        colorIndex = (colorIndex + 1) % count
        rerun()
    }

    func rerun() {
        evidence = FrameEvidence(generation: evidence.generation &+ 1)
        drawableDescription = "Not acquired"
        if !bridgePassed {
            recordFailure("C++ probe returned an unexpected result.")
        } else if device == nil {
            recordFailure("No Metal device is available in this environment.")
        } else if commandQueue == nil {
            recordFailure("Metal could not create a command queue.")
        }
    }

    func recordDrawable(width: Int, height: Int) {
        drawableDescription = "\(width) × \(height) pixels · BGRA8 sRGB"
    }

    func recordFailure(_ message: String) {
        evidence.recordGPUCompletion(for: evidence.generation, error: message)
    }

    func recordGPUCompletion(for generation: UInt64, error: String?) {
        guard isActive else { return }
        evidence.recordGPUCompletion(for: generation, error: error)
    }

    func confirmVisibleFrame() {
        guard isActive else { return }
        evidence.confirmVisibleFrame(for: evidence.generation)
    }
}
