import SwiftUI
import MetalKit

struct VolumetricMetalView: NSViewRepresentable {
    @Binding var debugMode: DebugMode
    @Binding var settings: VolumetricSettings
    @Binding var renderText: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is required to run this app.")
        }

        let view = MTKView(frame: .zero, device: device)
        view.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60

        let renderer = VolumetricRenderer(view: view)
        renderer.debugMode = debugMode
        renderer.updateSettings(settings)
        renderer.updateRenderText(renderText)
        context.coordinator.renderer = renderer
        view.delegate = renderer

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.debugMode = debugMode
        context.coordinator.renderer?.updateSettings(settings)
        context.coordinator.renderer?.updateRenderText(renderText)
    }

    final class Coordinator {
        var renderer: VolumetricRenderer?
    }
}
