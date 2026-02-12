# Metal Volumetric Light / Fog Text Effect

**Comprehensive Implementation Blueprint**\
Generated: 2026-02-12T14:33:18.516494 UTC

------------------------------------------------------------------------

# 1. Codex Task Tags

## TAGS

-   #metal
-   #mtkview
-   #render-pipeline
-   #volumetric-light
-   #screen-space
-   #shader-development
-   #multi-pass
-   #optimization
-   #debug-visualization

------------------------------------------------------------------------

# 2. AGENTS.md Style Architecture Specification

## System Overview

This project implements screen-space volumetric light scattering (god
rays) using text as an occlusion mask in Metal. It is intended to mimic as closely as possible the famous title card from the movie "The Thing" (1982).

See ![the_thing_1982_4k_01](/Users/jchilders/work/jchilders/ThingLight/assets/the_thing_1982_4k_01.png)

### Core Principle

Light scattering is approximated via radial sampling from a light source
in screen space. Text acts as an occlusion mask that blocks accumulated
light.

------------------------------------------------------------------------

## Components

### Renderer

Responsible for: - Frame lifecycle - Command buffer submission -
Resource management - Resize handling

### Render Targets

-   textMaskTexture
-   occlusionTexture
-   scatteringTexture
-   finalColorTexture

### Pipelines

-   TextMaskPipeline
-   OcclusionPipeline
-   ScatteringPipeline
-   CompositePipeline

### Uniform Buffers

``` swift
struct ScatteringUniforms {
    simd_float2 lightPosition;
    float exposure;
    float decay;
    float density;
    int sampleCount;
    float time;
}
```

------------------------------------------------------------------------

# 3. Implementation Tickets

## M1 -- Metal Scaffold

-   [ ] Create MTKView
-   [ ] Implement MTKViewDelegate
-   [ ] Setup command queue
-   [ ] Setup render loop

## M2 -- Text to Texture

-   [ ] Render text using CoreGraphics
-   [ ] Convert to CGImage
-   [ ] Load into MTLTexture
-   [ ] Validate alpha fidelity

## M3 -- Offscreen Infrastructure

-   [ ] Create MTLTextureDescriptor helpers
-   [ ] Allocate intermediate textures
-   [ ] Handle drawable resizing

## M4 -- Occlusion Pass

-   [ ] Render text mask to texture
-   [ ] Invert or threshold if necessary
-   [ ] Add debug preview mode

## M5 -- Scattering Shader

-   [ ] Implement radial sampling loop
-   [ ] Tune decay & exposure
-   [ ] Add performance scaling

## M6 -- Composite Pass

-   [ ] Blend scattering + background
-   [ ] Apply tint
-   [ ] Add gradient depth fade

## M7 -- Animation

-   [ ] Add time uniform
-   [ ] Animate light position
-   [ ] Add noise modulation

## M8 -- Optimization

-   [ ] Downsample scattering buffer
-   [ ] Early exit sampling
-   [ ] Reduce sample count adaptively

------------------------------------------------------------------------

# 4. Metal API Skeleton

## Renderer Setup

``` swift
class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    init(view: MTKView) {
        self.device = view.device!
        self.commandQueue = device.makeCommandQueue()!
        super.init()
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }

        let commandBuffer = commandQueue.makeCommandBuffer()!

        // PASS A: Occlusion
        // PASS B: Scattering
        // PASS C: Composite

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
```

------------------------------------------------------------------------

# 5. Shader Math Deep Dive

## Radial Sampling Formula

For fragment at UV:

    delta = lightPos - uv
    step = delta / sampleCount

Loop:

    accum += (1 - occlusionSample) * decay

Final:

    color = exposure * accum

### Parameters

-   exposure → brightness multiplier
-   decay → attenuation per step
-   density → ray thickness scaling
-   sampleCount → quality/performance tradeoff

------------------------------------------------------------------------

# 6. Debug Instrumentation Plan

## Debug Modes

1.  Show Text Mask
2.  Show Occlusion Texture
3.  Show Raw Scattering
4.  Show Composite Output

## Visualization Toggle Example

``` swift
enum DebugMode {
    case final
    case mask
    case scattering
}
```

------------------------------------------------------------------------

# 7. Performance Strategy

## Techniques

-   Downsample scattering pass to 50%
-   Bilateral blur post-pass
-   Adaptive sample count based on FPS
-   Avoid unnecessary texture format conversions

------------------------------------------------------------------------

# 8. Risk Matrix

  Risk            Mitigation
--------------- ------------------------------
  Banding         Add dithering or blur
  Edge Aliasing   Use SDF or higher resolution
  GPU Cost        Downsample pass
  Flicker         Stabilize sampling

------------------------------------------------------------------------

# 9. Definition of Done

-   Clean text occlusion
-   Visible radial shafts
-   Smooth animation
-   60 FPS at target resolution
-   No GPU validation errors

------------------------------------------------------------------------

END OF DOCUMENT
