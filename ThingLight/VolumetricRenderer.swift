import AppKit
import Metal
import MetalKit
import QuartzCore
import simd

enum DebugMode: Int, CaseIterable, Identifiable {
    case composite = 0
    case textMask = 1
    case occlusion = 2
    case scattering = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .composite:
            return "Final"
        case .textMask:
            return "Mask"
        case .occlusion:
            return "Occlusion"
        case .scattering:
            return "Scattering"
        }
    }
}

struct VolumetricSettings: Equatable {
    var exposure: Double = 0.56
    var decay: Double = 0.955
    var density: Double = 0.76
    var weight: Double = 0.26

    var noiseAmount: Double = 0.025
    var textIntensity: Double = 0.94
    var haloIntensity: Double = 0.52
    var backgroundLift: Double = 0.56

    var vignetteInner: Double = 0.18
    var vignetteOuter: Double = 1.04

    var lightBaseX: Double = 0.54
    var lightBaseY: Double = 0.71
    var lightDriftX: Double = 0.06
    var lightDriftY: Double = 0.04
    var lightDriftSpeedX: Double = 0.22
    var lightDriftSpeedY: Double = 0.28

    var animationSpeed: Double = 1.6
    var animationAmount: Double = 0.65

    var baseSampleCount: Int = 78
    var adaptiveSampling: Bool = true
    var downsampleScale: Double = 0.42
    var compactModeEnabled: Bool = true
    var compactShortEdgeThreshold: Double = 180.0

    static let cinematic = VolumetricSettings()
    static let `default` = VolumetricSettings.cinematic

    var sanitized: VolumetricSettings {
        var v = self

        v.exposure = v.exposure.clamped(to: 0.2...2.0)
        v.decay = v.decay.clamped(to: 0.85...0.998)
        v.density = v.density.clamped(to: 0.2...1.6)
        v.weight = v.weight.clamped(to: 0.05...1.2)

        v.noiseAmount = v.noiseAmount.clamped(to: 0.0...0.30)
        v.textIntensity = v.textIntensity.clamped(to: 0.4...2.4)
        v.haloIntensity = v.haloIntensity.clamped(to: 0.0...3.0)
        v.backgroundLift = v.backgroundLift.clamped(to: 0.2...2.0)

        v.vignetteInner = v.vignetteInner.clamped(to: 0.0...0.9)
        v.vignetteOuter = v.vignetteOuter.clamped(to: 0.2...1.4)
        if v.vignetteOuter <= v.vignetteInner + 0.05 {
            v.vignetteOuter = v.vignetteInner + 0.05
        }

        v.lightBaseX = v.lightBaseX.clamped(to: 0.0...1.0)
        v.lightBaseY = v.lightBaseY.clamped(to: 0.0...1.0)
        v.lightDriftX = v.lightDriftX.clamped(to: 0.0...0.2)
        v.lightDriftY = v.lightDriftY.clamped(to: 0.0...0.2)
        v.lightDriftSpeedX = v.lightDriftSpeedX.clamped(to: 0.0...2.0)
        v.lightDriftSpeedY = v.lightDriftSpeedY.clamped(to: 0.0...2.0)
        v.animationSpeed = v.animationSpeed.clamped(to: 0.0...4.0)
        v.animationAmount = v.animationAmount.clamped(to: 0.0...1.0)

        v.baseSampleCount = v.baseSampleCount.clamped(to: 24...220)
        v.downsampleScale = v.downsampleScale.clamped(to: 0.25...1.0)
        v.compactShortEdgeThreshold = v.compactShortEdgeThreshold.clamped(to: 96.0...480.0)

        return v
    }
}

private struct ScatteringUniformsGPU {
    var lightPosition: SIMD2<Float>
    var resolution: SIMD2<Float>

    var exposure: Float
    var decay: Float
    var density: Float
    var weight: Float

    var sampleCount: UInt32
    var debugMode: UInt32
    var time: Float
    var noiseAmount: Float

    var textIntensity: Float
    var haloIntensity: Float
    var backgroundLift: Float
    var vignetteInner: Float

    var vignetteOuter: Float
    var padding: SIMD3<Float> = .zero
}

private struct BlurUniformsGPU {
    var texelOffset: SIMD2<Float>
    var padding: SIMD2<Float> = .zero
}

final class VolumetricRenderer: NSObject, MTKViewDelegate {
    var debugMode: DebugMode = .composite

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let linearSampler: MTLSamplerState
    private let occlusionPipeline: MTLRenderPipelineState
    private let scatteringPipeline: MTLRenderPipelineState
    private let blurPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState

    private var textMaskTexture: MTLTexture?
    private var occlusionTexture: MTLTexture?
    private var scatteringTexture: MTLTexture?
    private var blurTexture: MTLTexture?

    private var settings = VolumetricSettings.default
    private var needsScatteringResize = false
    private var activeDownsampleScale = VolumetricSettings.default.downsampleScale
    private var renderText = "THE\nTHING"
    private var needsTextMaskRefresh = false

    private var viewportSize = CGSize(width: 1, height: 1)
    private let startTime = CACurrentMediaTime()
    private var lastFrameTimestamp = CACurrentMediaTime()
    private var smoothedFrameTime: Float = 1.0 / 60.0

    init(view: MTKView) {
        guard let device = view.device else {
            fatalError("MTKView missing Metal device.")
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            fatalError("Unable to create Metal command queue.")
        }
        commandQueue = queue

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Unable to load default Metal library.")
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            fatalError("Unable to create sampler state.")
        }
        linearSampler = sampler

        occlusionPipeline = VolumetricRenderer.makePipeline(
            device: device,
            library: library,
            vertexFunction: "fullscreenVertex",
            fragmentFunction: "occlusionFragment",
            pixelFormat: .rgba16Float
        )

        scatteringPipeline = VolumetricRenderer.makePipeline(
            device: device,
            library: library,
            vertexFunction: "fullscreenVertex",
            fragmentFunction: "scatteringFragment",
            pixelFormat: .rgba16Float
        )

        blurPipeline = VolumetricRenderer.makePipeline(
            device: device,
            library: library,
            vertexFunction: "fullscreenVertex",
            fragmentFunction: "gaussianBlurFragment",
            pixelFormat: .rgba16Float
        )

        compositePipeline = VolumetricRenderer.makePipeline(
            device: device,
            library: library,
            vertexFunction: "fullscreenVertex",
            fragmentFunction: "compositeFragment",
            pixelFormat: view.colorPixelFormat
        )

        super.init()

        mtkView(view, drawableSizeWillChange: view.drawableSize)
    }

    func updateSettings(_ newSettings: VolumetricSettings) {
        let sanitized = newSettings.sanitized
        if abs(sanitized.downsampleScale - settings.downsampleScale) > 0.0001 {
            needsScatteringResize = true
        }
        settings = sanitized
    }

    func updateRenderText(_ newValue: String) {
        let normalized = Self.normalizeRenderText(newValue)
        guard normalized != renderText else {
            return
        }
        renderText = normalized
        needsTextMaskRefresh = true
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        viewportSize = CGSize(width: width, height: height)

        textMaskTexture = makeTextMaskTexture(size: CGSize(width: width, height: height))
        occlusionTexture = makeRenderTexture(width: width, height: height, pixelFormat: .rgba16Float)
        rebuildScatteringTexture(scale: effectiveSettingsForViewport().downsampleScale)
        needsTextMaskRefresh = false
    }

    func draw(in view: MTKView) {
        let effectiveSettings = effectiveSettingsForViewport()

        if needsTextMaskRefresh {
            textMaskTexture = makeTextMaskTexture(size: viewportSize)
            needsTextMaskRefresh = false
        }

        if needsScatteringResize || abs(activeDownsampleScale - effectiveSettings.downsampleScale) > 0.0001 {
            rebuildScatteringTexture(scale: effectiveSettings.downsampleScale)
        }

        guard let drawable = view.currentDrawable,
              let textMaskTexture,
              let occlusionTexture,
              let scatteringTexture,
              let blurTexture,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let now = CACurrentMediaTime()
        let frameDelta = Float(max(now - lastFrameTimestamp, 1.0 / 240.0))
        lastFrameTimestamp = now
        smoothedFrameTime = (smoothedFrameTime * 0.92) + (frameDelta * 0.08)

        let elapsed = Float(now - startTime)
        var uniforms = makeUniforms(time: elapsed, settings: effectiveSettings)

        guard let occlusionPass = makeOffscreenPass(texture: occlusionTexture, clearColor: 0.0) else {
            return
        }
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: occlusionPass) {
            encoder.setRenderPipelineState(occlusionPipeline)
            encoder.setFragmentTexture(textMaskTexture, index: 0)
            encoder.setFragmentSamplerState(linearSampler, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ScatteringUniformsGPU>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }

        guard let scatteringPass = makeOffscreenPass(texture: scatteringTexture, clearColor: 0.0) else {
            return
        }
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: scatteringPass) {
            encoder.setRenderPipelineState(scatteringPipeline)
            encoder.setFragmentTexture(occlusionTexture, index: 0)
            encoder.setFragmentSamplerState(linearSampler, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ScatteringUniformsGPU>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }

        var horizontalBlur = BlurUniformsGPU(
            texelOffset: SIMD2<Float>(1.0 / Float(max(scatteringTexture.width, 1)), 0.0)
        )
        if let blurPass = makeOffscreenPass(texture: blurTexture, clearColor: 0.0),
           let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: blurPass) {
            encoder.setRenderPipelineState(blurPipeline)
            encoder.setFragmentTexture(scatteringTexture, index: 0)
            encoder.setFragmentSamplerState(linearSampler, index: 0)
            encoder.setFragmentBytes(&horizontalBlur, length: MemoryLayout<BlurUniformsGPU>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }

        var verticalBlur = BlurUniformsGPU(
            texelOffset: SIMD2<Float>(0.0, 1.0 / Float(max(scatteringTexture.height, 1)))
        )
        if let blurPass = makeOffscreenPass(texture: scatteringTexture, clearColor: 0.0),
           let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: blurPass) {
            encoder.setRenderPipelineState(blurPipeline)
            encoder.setFragmentTexture(blurTexture, index: 0)
            encoder.setFragmentSamplerState(linearSampler, index: 0)
            encoder.setFragmentBytes(&verticalBlur, length: MemoryLayout<BlurUniformsGPU>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }

        if let descriptor = view.currentRenderPassDescriptor,
           let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encoder.setRenderPipelineState(compositePipeline)
            encoder.setFragmentTexture(scatteringTexture, index: 0)
            encoder.setFragmentTexture(occlusionTexture, index: 1)
            encoder.setFragmentTexture(textMaskTexture, index: 2)
            encoder.setFragmentSamplerState(linearSampler, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ScatteringUniformsGPU>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

    private func makeUniforms(time: Float, settings: VolumetricSettings) -> ScatteringUniformsGPU {
        let animatedTime = Double(time) * settings.animationSpeed
        let animationAmount = settings.animationAmount

        let x = (
            settings.lightBaseX
            + sin(animatedTime * settings.lightDriftSpeedX) * settings.lightDriftX
            + sin(animatedTime * 0.70 + 1.2) * settings.lightDriftX * 0.33 * animationAmount
        ).clamped(to: 0.0...1.0)

        let y = (
            settings.lightBaseY
            + cos(animatedTime * settings.lightDriftSpeedY) * settings.lightDriftY
            + cos(animatedTime * 0.52 + 0.7) * settings.lightDriftY * 0.28 * animationAmount
        ).clamped(to: 0.0...1.0)

        let pulseA = sin(animatedTime * 0.90)
        let pulseB = sin(animatedTime * 2.70 + 0.8)
        let pulseBlend = (pulseA * 0.70 + pulseB * 0.30) * animationAmount

        let animatedExposure = settings.exposure * (1.0 + pulseBlend * 0.12)
        let animatedDensity = settings.density * (1.0 + pulseBlend * 0.08)
        let animatedHalo = settings.haloIntensity * (1.0 + pulseBlend * 0.15)
        let animatedNoise = settings.noiseAmount * (1.0 + pulseBlend * 0.24)

        return ScatteringUniformsGPU(
            lightPosition: SIMD2<Float>(Float(x), Float(y)),
            resolution: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)),
            exposure: Float(animatedExposure),
            decay: Float(settings.decay),
            density: Float(animatedDensity),
            weight: Float(settings.weight),
            sampleCount: sampleCountForCurrentFrame(settings: settings),
            debugMode: UInt32(debugMode.rawValue),
            time: Float(animatedTime),
            noiseAmount: Float(animatedNoise),
            textIntensity: Float(settings.textIntensity),
            haloIntensity: Float(animatedHalo),
            backgroundLift: Float(settings.backgroundLift),
            vignetteInner: Float(settings.vignetteInner),
            vignetteOuter: Float(settings.vignetteOuter)
        )
    }

    private func sampleCountForCurrentFrame(settings: VolumetricSettings) -> UInt32 {
        let base = UInt32(settings.baseSampleCount)
        guard settings.adaptiveSampling else {
            return base
        }

        let factor: Float
        if smoothedFrameTime > (1.0 / 48.0) {
            factor = 0.68
        } else if smoothedFrameTime > (1.0 / 56.0) {
            factor = 0.82
        } else if smoothedFrameTime < (1.0 / 78.0) {
            factor = 1.16
        } else {
            factor = 1.0
        }

        let scaled = Int((Float(base) * factor).rounded())
        return UInt32(scaled.clamped(to: 24...220))
    }

    private func effectiveSettingsForViewport() -> VolumetricSettings {
        guard settings.compactModeEnabled else {
            return settings
        }

        let shortEdge = min(viewportSize.width, viewportSize.height)
        guard shortEdge <= settings.compactShortEdgeThreshold else {
            return settings
        }

        var compact = settings
        compact.downsampleScale = 1.0
        compact.haloIntensity *= 0.72
        compact.noiseAmount *= 0.35
        compact.density *= 0.84
        compact.weight *= 0.90
        compact.lightDriftX *= 0.45
        compact.lightDriftY *= 0.45
        compact.animationAmount *= 0.78
        compact.animationSpeed *= 0.90
        compact.baseSampleCount = max(compact.baseSampleCount, 72)
        return compact.sanitized
    }

    private func rebuildScatteringTexture(scale: Double) {
        activeDownsampleScale = scale
        let width = max(Int((viewportSize.width * scale).rounded()), 1)
        let height = max(Int((viewportSize.height * scale).rounded()), 1)
        scatteringTexture = makeRenderTexture(width: width, height: height, pixelFormat: .rgba16Float)
        blurTexture = makeRenderTexture(width: width, height: height, pixelFormat: .rgba16Float)
        needsScatteringResize = false
    }

    private func makeRenderTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private func makeOffscreenPass(texture: MTLTexture, clearColor: Double) -> MTLRenderPassDescriptor? {
        let descriptor = MTLRenderPassDescriptor()
        guard let attachment = descriptor.colorAttachments[0] else {
            return nil
        }
        attachment.texture = texture
        attachment.loadAction = .clear
        attachment.storeAction = .store
        attachment.clearColor = MTLClearColorMake(clearColor, clearColor, clearColor, 1.0)
        return descriptor
    }

    private static func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        vertexFunction: String,
        fragmentFunction: String,
        pixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertexFunction)
        descriptor.fragmentFunction = library.makeFunction(name: fragmentFunction)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Pipeline creation failed for \(fragmentFunction): \(error)")
        }
    }

    private func makeTextMaskTexture(size: CGSize) -> MTLTexture? {
        let width = max(size.width, 1)
        let height = max(size.height, 1)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let lines = Self.textLines(from: renderText)

        if lines.count == 1, let onlyLine = lines.first {
            let singleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Chalkduster", size: height * 0.235) ?? NSFont.systemFont(ofSize: height * 0.235, weight: .black),
                .foregroundColor: NSColor(white: 0.98, alpha: 1.0),
                .paragraphStyle: paragraph
            ]

            let singleRect = NSRect(x: width * 0.10, y: height * 0.30, width: width * 0.80, height: height * 0.34)
            NSAttributedString(string: onlyLine, attributes: singleAttributes).draw(in: singleRect)
        } else {
            let topLine = lines.first ?? "THE"
            let bottomLine = lines.dropFirst().joined(separator: " ")

            let topAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Chalkduster", size: height * 0.095) ?? NSFont.systemFont(ofSize: height * 0.095, weight: .bold),
                .foregroundColor: NSColor(white: 0.92, alpha: 1.0),
                .paragraphStyle: paragraph
            ]

            let bottomAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Chalkduster", size: height * 0.215) ?? NSFont.systemFont(ofSize: height * 0.215, weight: .black),
                .foregroundColor: NSColor(white: 0.98, alpha: 1.0),
                .paragraphStyle: paragraph
            ]

            let topRect = NSRect(x: width * 0.34, y: height * 0.57, width: width * 0.34, height: height * 0.14)
            let bottomRect = NSRect(x: width * 0.14, y: height * 0.25, width: width * 0.72, height: height * 0.34)

            NSAttributedString(string: topLine, attributes: topAttributes).draw(in: topRect)
            NSAttributedString(string: bottomLine, attributes: bottomAttributes).draw(in: bottomRect)
        }

        image.unlockFocus()

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let loader = MTKTextureLoader(device: device)
        let usage = NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
        let storage = NSNumber(value: MTLStorageMode.private.rawValue)

        do {
            return try loader.newTexture(
                cgImage: cgImage,
                options: [
                    MTKTextureLoader.Option.SRGB: false,
                    MTKTextureLoader.Option.textureUsage: usage,
                    MTKTextureLoader.Option.textureStorageMode: storage
                ]
            )
        } catch {
            assertionFailure("Failed to create text mask texture: \(error)")
            return nil
        }
    }
}

private extension VolumetricRenderer {
    static func normalizeRenderText(_ value: String) -> String {
        let escapedExpanded = value.replacingOccurrences(of: "\\n", with: "\n")
        let pipeExpanded = escapedExpanded.replacingOccurrences(of: "|", with: "\n")
        let collapsed = pipeExpanded
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if collapsed.isEmpty {
            return "THING"
        }

        return collapsed.prefix(2).joined(separator: "\n")
    }

    static func textLines(from normalizedValue: String) -> [String] {
        let lines = normalizedValue
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.isEmpty }

        return lines.isEmpty ? ["THING"] : lines
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
