// The living heat field: a slow, soft gradient whose restlessness follows the thermal state.
// One stitchable colour effect, cheap per pixel (two octaves of value noise). Driven by SwiftUI's
// TimelineView; the view stops advancing time at nominal heat, under Reduce Motion and at critical heat.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash21(i), b = hash21(i + float2(1, 0)), c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

[[ stitchable ]] half4 heatField(float2 position, half4 color, float2 size, float time, float intensity,
                                 half4 ground, half4 cool, half4 warm, half4 hot) {
    float2 uv = position / max(size, float2(1));
    // Heat rises: the field is warmest at the bottom.
    float rise = 1.0 - uv.y;
    float speed = 0.15 + intensity * 0.9;
    float2 p = float2(uv.x * 3.0, uv.y * 2.2 + time * speed);
    float n = noise(p) * 0.65 + noise(p * 2.1 + 7.3) * 0.35;
    float heat = clamp(intensity * (0.55 + 0.6 * n) * (0.35 + 0.65 * rise) + 0.12 * n, 0.0, 1.0);
    half4 c = heat < 0.5 ? mix(cool, warm, half(heat * 2.0)) : mix(warm, hot, half((heat - 0.5) * 2.0));
    // Blend into the ground at the top so the field reads as a glow, not a block.
    float fade = smoothstep(0.0, 0.85, rise * (0.5 + 0.5 * intensity) + 0.25);
    return mix(ground, c, half(fade * (0.55 + 0.45 * intensity)));
}
