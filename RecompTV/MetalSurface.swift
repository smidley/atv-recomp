import MetalKit
import SwiftUI

struct MetalSurface: UIViewRepresentable {
    let paletteIndex: UInt32
    @Binding var status: String

    func makeCoordinator() -> Renderer {
        Renderer()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.backgroundColor = .black
        // This spike needs a new frame only after layout or a color change.
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        context.coordinator.report = { status = $0 }
        context.coordinator.configure(device: view.device)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.report = { status = $0 }
        guard context.coordinator.paletteIndex != paletteIndex else { return }
        context.coordinator.paletteIndex = paletteIndex
        let color = RTVGetClearColor(paletteIndex)
        view.clearColor = MTLClearColor(
            red: color.red, green: color.green, blue: color.blue, alpha: color.alpha
        )
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Renderer) {
        view.delegate = nil
        coordinator.report = nil
    }

    @MainActor
    final class Renderer: NSObject, MTKViewDelegate {
        var paletteIndex: UInt32?
        var report: (@MainActor @Sendable (String) -> Void)?
        private var commandQueue: (any MTLCommandQueue)?

        func configure(device: (any MTLDevice)?) {
            guard let device, let queue = device.makeCommandQueue() else {
                // Defer state changes until SwiftUI finishes creating the view.
                Task { @MainActor [weak self] in
                    self?.report?("Metal unavailable: no device or command queue")
                }
                return
            }
            commandQueue = queue
            print("RecompTV: Metal device: \(device.name)")
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            view.setNeedsDisplay()
        }

        func draw(in view: MTKView) {
            // A drawable may be absent while the app is hidden or before layout.
            guard let commandQueue,
                  let paletteIndex,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable else { return }

            guard let buffer = commandQueue.makeCommandBuffer() else {
                report?("Metal error: could not create command buffer")
                return
            }
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                report?("Metal error: could not create render encoder")
                return
            }
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.addCompletedHandler { [weak self] completed in
                let message = completed.status == .completed
                    ? "Metal frame \(paletteIndex + 1) completed"
                    : "Metal error: \(completed.error?.localizedDescription ?? "GPU command failed")"
                Task { @MainActor [weak self] in
                    // An old completion must not overwrite a newer color request.
                    guard self?.paletteIndex == paletteIndex else { return }
                    self?.report?(message)
                    print("RecompTV: \(message)")
                }
            }
            buffer.commit()
        }
    }
}
