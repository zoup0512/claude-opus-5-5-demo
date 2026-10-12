#include "Shaders.h"

namespace pelican::scene::shaders {

const char* kSkyVertex = R"GLSL(#version 300 es
precision highp float;
layout(location=0) in vec3 aPosition;
uniform mat4 uView;
uniform mat4 uProjection;
out vec3 vDir;
void main() {
    vDir = aPosition;
    mat4 viewNoTranslation = mat4(mat3(uView));
    vec4 clip = uProjection * viewNoTranslation * vec4(aPosition, 1.0);
    gl_Position = clip.xyww;
}
)GLSL";

const char* kSkyFragment = R"GLSL(#version 300 es
precision highp float;
in vec3 vDir;
layout(location=0) out vec4 fragColor;
uniform vec3 uSunDir;
uniform vec3 uMoonDir;
uniform vec3 uZenith;
uniform vec3 uHorizon;
uniform vec3 uGround;
uniform vec3 uSunColor;
uniform vec3 uCloudTint;
uniform vec3 uCloudShade;
uniform float uSunGlow;
uniform float uNight;
uniform float uTime;
uniform float uCloudCover;

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
float hash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
               mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; ++i) {
        sum += amp * vnoise(p);
        p = p * 2.03 + vec2(1.7, 9.2);
        amp *= 0.5;
    }
    return sum;
}
float fixf(float x) {
    if (isnan(x) || isinf(x)) return 0.0;
    return clamp(x, 0.0, 48.0);
}
vec3 clean(vec3 c) {
    return vec3(fixf(c.r), fixf(c.g), fixf(c.b));
}
vec3 skyBase(vec3 dir) {
    float y = dir.y;
    float h = pow(1.0 - clamp(y, 0.0, 1.0), 3.5);
    vec3 col = mix(uZenith, uHorizon, h);
    if (y < 0.0) col = mix(uHorizon, uGround, smoothstep(0.0, -0.3, y));
    float sd = max(dot(dir, uSunDir), 0.0);
    float glow = pow(sd, 6.0) * 0.28 + pow(sd, 48.0) * 0.55 + pow(sd, 400.0) * 1.2;
    col += uSunColor * glow * uSunGlow * (0.45 + 0.55 * h);
    float md = max(dot(dir, uMoonDir), 0.0);
    col += vec3(0.35, 0.45, 0.7) * (pow(md, 24.0) * 0.05 + pow(md, 300.0) * 0.2) * uNight;
    return clean(col);
}
void main() {
    vec3 dir = normalize(vDir);
    vec3 col = skyBase(dir);
    if (uNight > 0.01 && dir.y > -0.05) {
        vec3 p = dir * 320.0;
        vec3 cell = floor(p);
        float h = hash13(cell);
        if (h > 0.9955) {
            vec3 center = cell + 0.5 + (vec3(hash13(cell + 1.3), hash13(cell + 7.1), hash13(cell + 3.7)) - 0.5) * 0.7;
            float star = smoothstep(0.42, 0.0, length(p - center));
            float twinkle = 0.55 + 0.45 * sin(uTime * (1.5 + h * 7.0) + h * 91.0);
            vec3 starColor = mix(vec3(1.0, 0.82, 0.7), vec3(0.75, 0.85, 1.0), hash13(cell + 5.0));
            col += starColor * star * twinkle * uNight * 3.0 * smoothstep(-0.02, 0.2, dir.y);
        }
        vec3 axis = normalize(vec3(0.3, 0.55, 0.78));
        float band = exp(-pow(dot(dir, axis) * 5.0, 2.0));
        float milkyWay = fbm(dir.xz * 9.0 + dir.y * 4.0);
        col += vec3(0.28, 0.3, 0.45) * band * milkyWay * milkyWay * 0.35 * uNight * smoothstep(0.0, 0.3, dir.y);
    }
    float sunDot = dot(dir, uSunDir);
    col += uSunColor * smoothstep(0.99955, 0.99975, sunDot) * 18.0 * (1.0 - uNight);
    float moonDot = dot(dir, uMoonDir);
    float moon = smoothstep(0.99925, 0.99945, moonDot);
    if (moon > 0.0) {
        vec3 t1 = normalize(cross(uMoonDir, vec3(0.0, 1.0, 0.001)));
        vec3 t2 = cross(t1, uMoonDir);
        vec2 mp = vec2(dot(dir, t1), dot(dir, t2)) / 0.033;
        float lit = smoothstep(-0.25, 0.35, mp.x + 0.35);
        float craters = 0.82 + 0.18 * vnoise(mp * 6.0);
        col = mix(col, vec3(1.0, 0.97, 0.9) * 2.4 * craters * mix(0.12, 1.0, lit), moon * smoothstep(0.0, 0.5, uNight));
    }
    if (dir.y > 0.0) {
        vec2 uv = dir.xz / (dir.y + 0.1) * 0.55 + vec2(uTime * 0.0025, uTime * 0.001);
        float n = fbm(uv * 0.9);
        float n2 = fbm(uv * 2.3 + 4.0);
        float density = n * 0.75 + n2 * 0.35;
        float cover = smoothstep(1.0 - uCloudCover, 1.0 - uCloudCover + 0.32, density);
        float lightN = fbm(uv * 0.9 - uSunDir.xz * 0.12);
        float lit = clamp(0.55 + (n - lightN) * 3.0, 0.0, 1.0);
        float sunSide = pow(max(dot(dir, uSunDir), 0.0), 3.0);
        vec3 cloud = mix(uCloudShade, uCloudTint, lit) + uSunColor * sunSide * 0.5 * (1.0 - uNight);
        col = mix(col, cloud, cover * smoothstep(0.0, 0.14, dir.y) * 0.92);
    }
    fragColor = vec4(clean(col), 1.0);
}
)GLSL";

const char* kLitVertex = R"GLSL(#version 300 es
precision highp float;
layout(location=0) in vec3 aPosition;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec3 aColor;
layout(location=3) in vec2 aUv;
uniform mat4 uModel;
uniform mat4 uView;
uniform mat4 uProjection;
uniform float uTime;
uniform float uSway;
out vec3 vWorld;
out vec3 vNormal;
out vec3 vColor;
out vec2 vUv;
void main() {
    vec3 p = aPosition;
    float sway = max(p.y - 1.4, 0.0);
    p.x += sin(uTime * 1.3 + p.x * 0.31 + p.z * 0.17) * pow(sway, 1.3) * uSway;
    p.z += cos(uTime * 1.1 + p.x * 0.23) * pow(sway, 1.3) * uSway * 0.6;
    vec4 world = uModel * vec4(p, 1.0);
    vWorld = world.xyz;
    vNormal = normalize(mat3(uModel) * aNormal);
    vColor = aColor;
    vUv = aUv;
    gl_Position = uProjection * uView * world;
}
)GLSL";

const char* kInstancedVertex = R"GLSL(#version 300 es
precision highp float;
layout(location=0) in vec3 aPosition;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec3 aColor;
layout(location=3) in vec2 aUv;
layout(location=4) in vec4 iM0;
layout(location=5) in vec4 iM1;
layout(location=6) in vec4 iM2;
layout(location=7) in vec4 iM3;
layout(location=8) in vec4 iColorParameter;
uniform mat4 uModel;
uniform mat4 uView;
uniform mat4 uProjection;
uniform float uTime;
uniform float uSway;
out vec3 vWorld;
out vec3 vNormal;
out vec3 vColor;
out vec2 vUv;
void main() {
    mat4 instanceMatrix = mat4(iM0, iM1, iM2, iM3);
    vec3 p = aPosition;
    float sway = max(p.y - 1.4, 0.0);
    p.x += sin(uTime * 1.3 + iM3.x * 0.31 + iM3.z * 0.17 + iColorParameter.w) * pow(sway, 1.3) * uSway;
    p.z += cos(uTime * 1.1 + iM3.x * 0.23) * pow(sway, 1.3) * uSway * 0.6;
    mat4 model = uModel * instanceMatrix;
    vec4 world = model * vec4(p, 1.0);
    vWorld = world.xyz;
    vNormal = normalize(mat3(model) * aNormal);
    vColor = aColor * iColorParameter.rgb;
    vUv = aUv;
    gl_Position = uProjection * uView * world;
}
)GLSL";

const char* kLitFragment = R"GLSL(#version 300 es
precision highp float;
in vec3 vWorld;
in vec3 vNormal;
in vec3 vColor;
in vec2 vUv;
layout(location=0) out vec4 fragColor;
uniform vec3 uCamera;
uniform vec3 uSunDir;
uniform vec3 uSunColor;
uniform vec3 uFogColor;
uniform vec3 uTint;
uniform vec3 uEmission;
uniform float uAmbient;
uniform float uRoughness;
uniform float uFogDensity;
uniform float uUseTexture;
uniform sampler2D uTexture;
float fixf(float x) {
    if (isnan(x) || isinf(x)) return 0.0;
    return clamp(x, 0.0, 48.0);
}
vec3 clean(vec3 c) {
    return vec3(fixf(c.r), fixf(c.g), fixf(c.b));
}
void main() {
    vec3 N = normalize(vNormal);
    vec3 V = normalize(uCamera - vWorld);
    vec3 L = normalize(uSunDir);
    float diffuse = max(dot(N, L), 0.0);
    vec3 H = normalize(L + V);
    float specularPower = mix(96.0, 8.0, clamp(uRoughness, 0.0, 1.0));
    float specular = pow(max(dot(N, H), 0.0), specularPower) * (1.0 - uRoughness) * 0.35;
    vec3 tex = mix(vec3(1.0), texture(uTexture, vUv).rgb, step(0.5, uUseTexture));
    vec3 base = vColor * uTint * tex;
    vec3 color = base * (uAmbient + diffuse * uSunColor) + uSunColor * specular + uEmission;
    float distanceToCamera = length(vWorld - uCamera);
    float fog = 1.0 - exp(-pow(distanceToCamera * uFogDensity, 1.35));
    color = mix(color, uFogColor, clamp(fog, 0.0, 1.0));
    fragColor = vec4(clean(color), 1.0);
}
)GLSL";

const char* kOceanVertex = R"GLSL(#version 300 es
precision highp float;
layout(location=0) in vec3 aPosition;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec3 aColor;
layout(location=3) in vec2 aUv;
uniform mat4 uView;
uniform mat4 uProjection;
uniform float uAmplitude;
uniform float uPhase[5];
out vec3 vWorld;
out vec3 vNormal;
out float vHeight;
out vec2 vLocal;
const float SHORE = -14.6;
vec3 gerstner(vec2 p, vec2 direction, float steepness, float wavelength, float phase, float amp,
              inout vec3 tangent, inout vec3 binormal) {
    float k = 6.28318530718 / wavelength;
    vec2 d = normalize(direction);
    float f = k * dot(d, p) + phase;
    float st = steepness * amp;
    float a = st / k;
    float sf = sin(f);
    float cf = cos(f);
    tangent += vec3(-d.x * d.x * st * sf, d.x * st * cf, -d.x * d.y * st * sf);
    binormal += vec3(-d.x * d.y * st * sf, d.y * st * cf, -d.y * d.y * st * sf);
    return vec3(d.x * a * cf, a * sf, d.y * a * cf);
}
void main() {
    vec3 world = aPosition;
    vec2 p = world.xz;
    float offshore = smoothstep(SHORE + 1.0, SHORE - 30.0, world.z);
    float amp = uAmplitude * mix(0.35, 1.0, offshore);
    vec3 tangent = vec3(1.0, 0.0, 0.0);
    vec3 binormal = vec3(0.0, 0.0, 1.0);
    vec3 displacement = vec3(0.0);
    displacement += gerstner(p, vec2(0.18, 1.0), 0.20, 21.0, uPhase[0], amp, tangent, binormal);
    displacement += gerstner(p, vec2(-0.45, 1.0), 0.17, 12.5, uPhase[1], amp, tangent, binormal);
    displacement += gerstner(p, vec2(0.75, 0.62), 0.13, 7.0, uPhase[2], amp, tangent, binormal);
    displacement += gerstner(p, vec2(-0.9, 0.45), 0.10, 4.2, uPhase[3], amp, tangent, binormal);
    displacement += gerstner(p, vec2(0.3, 1.0), 0.07, 2.6, uPhase[4], amp, tangent, binormal);
    world += displacement;
    vWorld = world;
    vNormal = normalize(cross(binormal, tangent));
    vHeight = displacement.y / max(uAmplitude, 0.05);
    vLocal = world.xz;
    gl_Position = uProjection * uView * vec4(world, 1.0);
}
)GLSL";

const char* kOceanFragment = R"GLSL(#version 300 es
precision highp float;
in vec3 vWorld;
in vec3 vNormal;
in float vHeight;
in vec2 vLocal;
layout(location=0) out vec4 fragColor;
uniform vec3 uCamera;
uniform vec3 uSunDir;
uniform vec3 uMoonDir;
uniform vec3 uZenith;
uniform vec3 uHorizon;
uniform vec3 uGround;
uniform vec3 uSunColor;
uniform vec3 uFogColor;
uniform vec3 uDeep;
uniform vec3 uShallow;
uniform vec3 uLampColor;
uniform float uSunGlow;
uniform float uNight;
uniform float uTime;
uniform float uFogDensity;
uniform float uDayLight;
const float SHORE = -14.6;
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
               mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fixf(float x) {
    if (isnan(x) || isinf(x)) return 0.0;
    return clamp(x, 0.0, 48.0);
}
vec3 clean(vec3 c) {
    return vec3(fixf(c.r), fixf(c.g), fixf(c.b));
}
vec3 skyBase(vec3 dir) {
    float h = pow(1.0 - clamp(dir.y, 0.0, 1.0), 3.5);
    vec3 col = mix(uZenith, uHorizon, h);
    if (dir.y < 0.0) col = mix(uHorizon, uGround, smoothstep(0.0, -0.3, dir.y));
    float sd = max(dot(dir, uSunDir), 0.0);
    col += uSunColor * (pow(sd, 6.0) * 0.28 + pow(sd, 48.0) * 0.55 + pow(sd, 400.0) * 1.2) * uSunGlow;
    float md = max(dot(dir, uMoonDir), 0.0);
    col += vec3(0.35, 0.45, 0.7) * (pow(md, 24.0) * 0.05 + pow(md, 300.0) * 0.2) * uNight;
    return clean(col);
}
void main() {
    vec3 N = normalize(vNormal);
    float distanceToCamera = length(vWorld - uCamera);
    vec2 q = vLocal * 0.55;
    float epsilon = 0.35;
    vec2 flow1 = vec2(0.35, 0.6) * uTime;
    vec2 flow2 = vec2(-0.5, 0.25) * uTime;
    float h0 = vnoise(q + flow1) + 0.5 * vnoise(q * 2.7 + flow2);
    float hx = vnoise(q + vec2(epsilon, 0.0) + flow1) + 0.5 * vnoise((q + vec2(epsilon, 0.0)) * 2.7 + flow2);
    float hz = vnoise(q + vec2(0.0, epsilon) + flow1) + 0.5 * vnoise((q + vec2(0.0, epsilon)) * 2.7 + flow2);
    float detail = 0.55 * (1.0 - smoothstep(20.0, 160.0, distanceToCamera));
    N = normalize(N + vec3(h0 - hx, 0.0, h0 - hz) * detail);
    vec3 V = normalize(uCamera - vWorld);
    float fresnel = 0.02 + 0.98 * pow(clamp(1.0 - max(dot(N, V), 0.0), 0.0, 1.0), 5.0);
    vec3 R = reflect(-V, N);
    R.y = abs(R.y) + 0.02;
    R = normalize(R);
    vec3 reflection = skyBase(R);
    float depth = smoothstep(SHORE - 2.0, SHORE - 45.0, vWorld.z);
    vec3 water = mix(uShallow, uDeep, depth) * (0.12 + 0.88 * uDayLight);
    float subsurface = pow(max(dot(V, -uSunDir), 0.0), 3.0) * clamp(vHeight + 0.3, 0.0, 1.5);
    water += uShallow * uSunColor * subsurface * 0.35 * (1.0 - uNight);
    vec3 color = mix(water, reflection, fresnel);
    float sunReflection = max(dot(R, uSunDir), 0.0);
    color += uSunColor * (pow(sunReflection, 420.0) * 30.0 + pow(sunReflection, 60.0) * 0.7) * (1.0 - uNight);
    float moonReflection = max(dot(R, uMoonDir), 0.0);
    color += vec3(0.75, 0.82, 1.0) * (pow(moonReflection, 250.0) * 2.2 + pow(moonReflection, 30.0) * 0.06) * uNight;
    float foamNoise = vnoise(vLocal * 1.3 + uTime * 0.4) * 0.6 + vnoise(vLocal * 4.0 - uTime * 0.3) * 0.4;
    float crest = smoothstep(0.62, 1.05, vHeight + foamNoise * 0.35) * smoothstep(-8.0, -40.0, vWorld.z);
    float shoreline = SHORE + 0.9 * sin(vLocal.x * 0.045) + 0.5 * sin(vLocal.x * 0.13 + 1.7);
    float surge = sin(uTime * 0.7 + vLocal.x * 0.021) * 1.3;
    float signedDistance = vWorld.z - (shoreline + surge * 0.5);
    float shoreFoam = smoothstep(-5.5, 0.5, signedDistance) * (0.55 + 0.45 * foamNoise);
    shoreFoam *= smoothstep(0.35, 0.55, foamNoise + smoothstep(-2.5, 0.8, signedDistance) * 0.5);
    float foam = clamp(max(crest * 0.75, shoreFoam), 0.0, 1.0);
    vec3 foamColor = mix(vec3(0.06, 0.08, 0.12), vec3(0.95, 0.97, 1.0), uDayLight) * (0.6 + 0.4 * uSunGlow);
    color = mix(color, foamColor, foam * 0.85);
    float lampRow = pow(max(0.0, 1.0 - abs(fract((vLocal.x - 12.0) / 36.0 + 0.5) - 0.5) * 7.0), 2.0);
    color += uLampColor * lampRow * smoothstep(-40.0, -14.0, vWorld.z) * uNight * 0.25 * (0.5 + 0.5 * foamNoise);
    float fog = 1.0 - exp(-pow(distanceToCamera * uFogDensity, 1.35));
    color = mix(color, uFogColor, clamp(fog, 0.0, 1.0));
    fragColor = vec4(clean(color), 1.0);
}
)GLSL";

const char* kParticleVertex = R"GLSL(#version 300 es
precision highp float;
layout(location=0) in vec3 aPosition;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec3 aColor;
layout(location=3) in vec2 aUv;
uniform mat4 uView;
uniform mat4 uProjection;
uniform float uPointScale;
out vec3 vColor;
out float vAlpha;
void main() {
    vec4 view = uView * vec4(aPosition, 1.0);
    gl_Position = uProjection * view;
    gl_PointSize = max(1.0, aUv.x * uPointScale / max(-view.z, 0.1));
    vColor = aColor;
    vAlpha = aUv.y;
}
)GLSL";

const char* kParticleFragment = R"GLSL(#version 300 es
precision highp float;
in vec3 vColor;
in float vAlpha;
layout(location=0) out vec4 fragColor;
float fixf(float x) {
    if (isnan(x) || isinf(x)) return 0.0;
    return clamp(x, 0.0, 48.0);
}
vec3 clean(vec3 c) {
    return vec3(fixf(c.r), fixf(c.g), fixf(c.b));
}
void main() {
    float d = length(gl_PointCoord - 0.5);
    float alpha = smoothstep(0.5, 0.05, d) * clamp(vAlpha, 0.0, 1.0);
    if (alpha < 0.003) discard;
    fragColor = vec4(clean(vColor), alpha);
}
)GLSL";

const char* kFullscreenVertex = R"GLSL(#version 300 es
precision highp float;
out vec2 vUv;
void main() {
    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
    vUv = p;
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
)GLSL";

const char* kBloomDownFragment = R"GLSL(#version 300 es
precision highp float;
in vec2 vUv;
layout(location=0) out vec4 fragColor;
uniform sampler2D uScene;
uniform vec2 uTexel;
uniform float uThreshold;
float fixf(float x) {
    if (isnan(x) || isinf(x)) return 0.0;
    return clamp(x, 0.0, 48.0);
}
vec3 clean(vec3 c) {
    return vec3(fixf(c.r), fixf(c.g), fixf(c.b));
}
void main() {
    vec3 c = texture(uScene, vUv).rgb * 0.25;
    c += texture(uScene, vUv + vec2(uTexel.x, 0.0)).rgb * 0.1875;
    c += texture(uScene, vUv - vec2(uTexel.x, 0.0)).rgb * 0.1875;
    c += texture(uScene, vUv + vec2(0.0, uTexel.y)).rgb * 0.1875;
    c += texture(uScene, vUv - vec2(0.0, uTexel.y)).rgb * 0.1875;
    c = clean(c);
    float luminance = max(max(c.r, c.g), c.b);
    c *= smoothstep(uThreshold, uThreshold + 0.75, luminance);
    fragColor = vec4(clean(c), 1.0);
}
)GLSL";

const char* kBloomBlurFragment = R"GLSL(#version 300 es
precision highp float;
in vec2 vUv;
layout(location=0) out vec4 fragColor;
uniform sampler2D uImage;
uniform vec2 uDirection;
float fixf(float x) {
    if (isnan(x) || isinf(x)) return 0.0;
    return clamp(x, 0.0, 48.0);
}
vec3 clean(vec3 c) {
    return vec3(fixf(c.r), fixf(c.g), fixf(c.b));
}
void main() {
    vec3 c = texture(uImage, vUv).rgb * 0.227027;
    c += texture(uImage, vUv + uDirection * 1.384615).rgb * 0.316216;
    c += texture(uImage, vUv - uDirection * 1.384615).rgb * 0.316216;
    c += texture(uImage, vUv + uDirection * 3.230769).rgb * 0.070270;
    c += texture(uImage, vUv - uDirection * 3.230769).rgb * 0.070270;
    fragColor = vec4(clean(c), 1.0);
}
)GLSL";

const char* kFinalFragment = R"GLSL(#version 300 es
precision highp float;
in vec2 vUv;
layout(location=0) out vec4 fragColor;
uniform sampler2D uScene;
uniform sampler2D uBloom;
uniform sampler2D uNoise;
uniform vec2 uResolution;
uniform float uExposure;
uniform float uBloomStrength;
uniform float uTime;
uniform float uAberration;
float fixf(float x) {
    if (isnan(x) || isinf(x)) return 0.0;
    return clamp(x, 0.0, 48.0);
}
vec3 clean(vec3 c) {
    return vec3(fixf(c.r), fixf(c.g), fixf(c.b));
}
vec3 aces(vec3 x) {
    x = clean(x);
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / max(x * (c * x + d) + e, vec3(1e-5)), 0.0, 1.0);
}
void main() {
    vec2 centered = vUv - 0.5;
    vec2 chroma = centered * uAberration / max(uResolution, vec2(1.0));
    float r = texture(uScene, vUv + chroma).r;
    float g = texture(uScene, vUv).g;
    float b = texture(uScene, vUv - chroma).b;
    vec3 color = clean(vec3(r, g, b));
    color = clean(color + texture(uBloom, vUv).rgb * uBloomStrength);
    color = aces(color * max(uExposure, 0.0));
    float vignette = smoothstep(0.9, 0.18, dot(centered, centered));
    color *= mix(0.72, 1.0, vignette);
    float grain = texture(uNoise, vUv * uResolution / 64.0 + vec2(fract(uTime * 0.13), fract(uTime * 0.071))).r - 0.5;
    color += grain * (1.0 / 255.0) * 1.8;
    color = pow(clamp(clean(color), 0.0, 1.0), vec3(1.0 / 2.2));
    fragColor = vec4(color, 1.0);
}
)GLSL";

const char* kCopyFragment = R"GLSL(#version 300 es
precision highp float;
in vec2 vUv;
layout(location=0) out vec4 fragColor;
uniform sampler2D uScene;
uniform float uExposure;
float fixf(float x) {
    if (isnan(x) || isinf(x)) return 0.0;
    return clamp(x, 0.0, 48.0);
}
vec3 clean(vec3 c) {
    return vec3(fixf(c.r), fixf(c.g), fixf(c.b));
}
void main() {
    vec3 c = clean(texture(uScene, vUv).rgb * max(uExposure, 0.0));
    c = c / (vec3(1.0) + c);
    fragColor = vec4(pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0);
}
)GLSL";

}  // namespace pelican::scene::shaders
