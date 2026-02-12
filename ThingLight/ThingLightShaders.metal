#include <metal_stdlib>
using namespace metal;

struct RasterizerData {
    float4 position [[position]];
    float2 uv;
};

struct ScatteringUniformsGPU {
    float2 lightPosition;
    float2 resolution;

    float exposure;
    float decay;
    float density;
    float weight;

    uint sampleCount;
    uint debugMode;
    float time;
    float noiseAmount;

    float textIntensity;
    float haloIntensity;
    float backgroundLift;
    float vignetteInner;

    float vignetteOuter;
    float3 padding;
};

struct BlurUniformsGPU {
    float2 texelOffset;
    float2 padding;
};

vertex RasterizerData fullscreenVertex(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2(1.0, -1.0),
        float2(-1.0, 1.0),
        float2(1.0, 1.0)
    };

    float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    RasterizerData out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

fragment half4 occlusionFragment(
    RasterizerData in [[stage_in]],
    texture2d<float> textMaskTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]],
    constant ScatteringUniformsGPU& uniforms [[buffer(0)]]
) {
    float2 grainUV = in.uv * (uniforms.resolution / 740.0);
    float grain = fract(sin(dot(grainUV, float2(12.9898, 78.233))) * 43758.5453);
    float2 wobble = float2((grain - 0.5) * 0.0022, (0.5 - grain) * 0.0016);

    float maskSample = textMaskTexture.sample(linearSampler, in.uv + wobble).r;
    float edge = smoothstep(0.16, 0.66, maskSample);
    return half4(half(edge), half(edge), half(edge), 1.0h);
}

fragment half4 scatteringFragment(
    RasterizerData in [[stage_in]],
    texture2d<float> occlusionTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]],
    constant ScatteringUniformsGPU& uniforms [[buffer(0)]]
) {
    float2 delta = (uniforms.lightPosition - in.uv) * (uniforms.density / max(float(uniforms.sampleCount), 1.0));
    float2 sampleUV = in.uv;

    float illuminationDecay = 1.0;
    float accumulated = 0.0;

    for (uint i = 0; i < uniforms.sampleCount; ++i) {
        sampleUV += delta;
        float occluder = occlusionTexture.sample(linearSampler, sampleUV).r;
        accumulated += occluder * illuminationDecay * uniforms.weight;
        illuminationDecay *= uniforms.decay;
        if (illuminationDecay < 0.01) {
            break;
        }
    }

    accumulated *= uniforms.exposure;

    float jitterBase = sin((in.uv.x * 13.0 + in.uv.y * 21.0) + uniforms.time * 0.6);
    float jitter = 1.0 + (uniforms.noiseAmount * jitterBase);
    accumulated *= max(jitter, 0.0);

    float3 rayTint = float3(0.34, 0.62, 0.97) * accumulated;
    return half4(half3(rayTint), 1.0h);
}

fragment half4 gaussianBlurFragment(
    RasterizerData in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]],
    constant BlurUniformsGPU& blur [[buffer(1)]]
) {
    constexpr float w0 = 0.227027;
    constexpr float w1 = 0.1945946;
    constexpr float w2 = 0.1216216;
    constexpr float w3 = 0.054054;

    float3 color = sourceTexture.sample(linearSampler, in.uv).rgb * w0;
    color += sourceTexture.sample(linearSampler, in.uv + blur.texelOffset * 1.0).rgb * w1;
    color += sourceTexture.sample(linearSampler, in.uv - blur.texelOffset * 1.0).rgb * w1;
    color += sourceTexture.sample(linearSampler, in.uv + blur.texelOffset * 2.0).rgb * w2;
    color += sourceTexture.sample(linearSampler, in.uv - blur.texelOffset * 2.0).rgb * w2;
    color += sourceTexture.sample(linearSampler, in.uv + blur.texelOffset * 3.0).rgb * w3;
    color += sourceTexture.sample(linearSampler, in.uv - blur.texelOffset * 3.0).rgb * w3;

    return half4(half3(color), 1.0h);
}

fragment half4 compositeFragment(
    RasterizerData in [[stage_in]],
    texture2d<float> scatteringTexture [[texture(0)]],
    texture2d<float> occlusionTexture [[texture(1)]],
    texture2d<float> textMaskTexture [[texture(2)]],
    sampler linearSampler [[sampler(0)]],
    constant ScatteringUniformsGPU& uniforms [[buffer(0)]]
) {
    float2 center = float2(0.5, 0.52);
    float d = distance(in.uv, center);

    float centerGlow = 1.0 - smoothstep(0.0, 1.16, d);
    float horizon = 1.0 - smoothstep(0.22, 0.98, abs(in.uv.y - 0.52));

    float3 deepBlue = float3(0.0, 0.008, 0.075);
    float3 coldBlue = float3(0.08, 0.28, 0.86);
    float backgroundMix = saturate(centerGlow * horizon * uniforms.backgroundLift);
    float3 background = mix(deepBlue, coldBlue, backgroundMix);

    float3 scattering = scatteringTexture.sample(linearSampler, in.uv).rgb;
    float occlusion = occlusionTexture.sample(linearSampler, in.uv).r;

    float rawMask = textMaskTexture.sample(linearSampler, in.uv).r;
    float textMask = smoothstep(0.14, 0.72, rawMask);

    float3 textColor = float3(0.93, 0.95, 1.0) * pow(textMask, 0.86) * uniforms.textIntensity;
    float3 halo = scattering * uniforms.haloIntensity;

    float vignette = 1.0 - smoothstep(uniforms.vignetteInner, uniforms.vignetteOuter, d);
    float3 finalColor = (background + halo + textColor) * vignette;

    if (uniforms.debugMode == 1u) {
        return half4(half3(textMask), 1.0h);
    }
    if (uniforms.debugMode == 2u) {
        return half4(half3(occlusion), 1.0h);
    }
    if (uniforms.debugMode == 3u) {
        return half4(half3(scattering), 1.0h);
    }

    return half4(half3(finalColor), 1.0h);
}
