import MetalKit
import SwiftUI

@MainActor
struct MetalProbeView: UIViewRepresentable {
    let session: ProbeSession

    func makeUIView(context: Context) -> ProbeMetalView {
        ProbeMetalView(session: session)
    }

    func updateUIView(_ view: ProbeMetalView, context: Context) {
        view.requestFrame(generation: session.evidence.generation)
    }

    static func dismantleUIView(_ view: ProbeMetalView, coordinator: ()) {
        view.session = nil
        view.releaseDrawables()
    }
}

// MTKView's UIKit draw override executes on the main actor. No delegate or
// secondary render thread is installed. The probe draws on demand, not at 60 Hz.
@MainActor
final class ProbeMetalView: MTKView {
    weak var session: ProbeSession?
    private var requestedGeneration: UInt64?

    init(session: ProbeSession) {
        self.session = session
        super.init(frame: .zero, device: session.device)
        colorPixelFormat = .bgra8Unorm_srgb
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        framebufferOnly = true
        autoResizeDrawable = true
        isOpaque = true
        isUserInteractionEnabled = false
        isPaused = true
        enableSetNeedsDisplay = true
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    func requestFrame(generation: UInt64) {
        guard requestedGeneration != generation else { return }
        requestedGeneration = generation
        if session?.isActive == true {
            // UIKit schedules draw outside SwiftUI's updateUIView call.
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let session, session.isActive, session.bridgePassed,
              window != nil, drawableSize.width > 0, drawableSize.height > 0,
              let queue = session.commandQueue else { return }

        autoreleasepool {
            let generation = session.evidence.generation
            let color = RTVTestColor(session.colorIndex)
            clearColor = MTLClearColor(
                red: color.red, green: color.green, blue: color.blue, alpha: color.alpha
            )

            guard let commandBuffer = queue.makeCommandBuffer() else {
                session.recordFailure("Metal could not create a command buffer. Rerun the check.")
                return
            }

            // Acquire late; keep both descriptor and drawable local to this draw.
            guard let descriptor = currentRenderPassDescriptor,
                  let drawable = currentDrawable else {
                session.recordFailure("No drawable is available. Keep the app visible and rerun the check.")
                return
            }
            guard let attachment = descriptor.colorAttachments[0] else {
                session.recordFailure("The render pass has no color attachment.")
                return
            }
            attachment.loadAction = .clear
            attachment.storeAction = .store

            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                session.recordFailure("Metal could not create a render encoder.")
                return
            }
            encoder.label = "Clear to the C++ test color"
            encoder.endEncoding()
            session.recordDrawable(width: drawable.texture.width, height: drawable.texture.height)

            // Metal's required SDK callbacks copy only scalar/string evidence
            // into main-actor tasks; GPU objects never cross into UI state.
            commandBuffer.addCompletedHandler { @Sendable [weak session] buffer in
                let error: String? = buffer.status == .completed
                    ? nil
                    : (buffer.error?.localizedDescription ?? "GPU command buffer did not complete.")
                Task { @MainActor [weak session] in
                    session?.recordGPUCompletion(for: generation, error: error)
                }
            }
            drawable.addPresentedHandler { @Sendable [weak session] presentedDrawable in
                let time = presentedDrawable.presentedTime
                Task { @MainActor [weak session] in
                    session?.recordPresentation(for: generation, time: time)
                }
            }

            // Standard MTLCommandQueue path: present before commit. Metal 4
            // waitForDrawable/signalDrawable are not part of this API path.
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
