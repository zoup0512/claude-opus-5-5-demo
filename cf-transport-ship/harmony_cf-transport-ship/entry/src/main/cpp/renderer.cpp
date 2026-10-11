/**
 * 运输船渲染器实现： EGL 上下文管理 + GLES3 前向渲染管线
 * 管线：天空 → 静态不透明网格 → 蒙皮士兵（含第三人称枪） → 海洋 → 透明四边形/粒子 → 第一人称武器层
 * 约定：网格 id >= 9000 为动态网格（9000/9001 士兵、>=9100 枪械、>=9900 武器层），不会在静态批次中绘制。
 */
#include "renderer.h"
#include <hilog/log.h>
#include <cmath>
#include <cstring>

#define LOG_TAG "CfShip"
#define LOG_I(...) hilog_info(LOG_APP, LOG_TAG, __VA_ARGS__)
#define LOG_W(...) hilog_warn(LOG_APP, LOG_TAG, __VA_ARGS__)

// 与 ArkTS FrameBuf 一致的帧布局常量
static const int OFF_FLAGS = 0;
static const int OFF_WORLDVP = 1;
static const int OFF_CAMPOS = 17;
static const int OFF_VMACTIVE = 20;
static const int OFF_VMVP = 21;
static const int OFF_SUNDIR = 37;
static const int OFF_SUNCOL = 40;
static const int OFF_HEMISKY = 43;
static const int OFF_HEMIGND = 46;
static const int OFF_FOGCOL = 49;
static const int OFF_FOGDEN = 52;
static const int OFF_TIME = 53;
static const int OFF_NSOLDIER = 54;
static const int OFF_NQUAD = 55;
static const int OFF_NPART = 56;
static const int OFF_OCEAN = 57;
static const int OFF_VMMESH = 58;
static const int OFF_VMMODEL = 59;
static const int OFF_NDYN = 75;

static const int OFF_SOLDIERS = 80;
static const int SOLDIER_STRIDE = 322;
static const int OFF_DYN = OFF_SOLDIERS + 16 * SOLDIER_STRIDE; // 5232
static const int DYN_STRIDE = 17;                              // meshId + mat4
static const int OFF_QUADS = OFF_DYN + 12 * DYN_STRIDE;        // 5436
static const int QUAD_STRIDE = 24;
static const int OFF_PARTS = OFF_QUADS + 320 * QUAD_STRIDE; // 13116
static const int PART_STRIDE = 9;

static const int MAX_BONES = 24;
static const float IDENT_MAT[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};

// ---------------- 着色器 ----------------
static const char *COMMON_NOISE = R"(
float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float vnoise(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f*f*(3.0-2.0*f);
  return mix(mix(hash12(i), hash12(i+vec2(1,0)), u.x), mix(hash12(i+vec2(0,1)), hash12(i+vec2(1,1)), u.x), u.y); }
float fbm4(vec2 p){ float s=0.0; float a=0.5; for(int i=0;i<4;i++){ s+=a*vnoise(p); p=p*2.03+vec2(17.1,9.2); a*=0.5;} return s; }
float fbm6(vec2 p){ float s=0.0; float a=0.5; for(int i=0;i<6;i++){ s+=a*vnoise(p); p=p*2.03+vec2(17.1,9.2); a*=0.5;} return s; }
)";

static const char *VS_STATIC = R"(#version 300 es
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNrm;
layout(location=2) in vec2 aUV;
layout(location=3) in vec3 aCol;
uniform mat4 uVP;
uniform mat4 uModel;
out vec3 vN; out vec2 vUV; out vec3 vCol; out vec3 vW;
void main(){
  vec4 w = uModel * vec4(aPos, 1.0);
  vW = w.xyz;
  vN = mat3(uModel) * aNrm;
  vUV = aUV; vCol = aCol;
  gl_Position = uVP * w;
})";

static const char *FS_STATIC = R"(#version 300 es
precision mediump float;
in vec3 vN; in vec2 vUV; in vec3 vCol; in vec3 vW;
uniform sampler2D uTex;
uniform vec3 uColor;
uniform vec3 uRME;
uniform vec3 uSunDir;
uniform vec3 uSunColor;
uniform vec3 uHemiSky;
uniform vec3 uHemiGround;
uniform vec3 uFogColor;
uniform vec3 uCamPos;
uniform float uFogDensity;
uniform float uAlphaTest;
out vec4 fragColor;
void main(){
  vec4 t = texture(uTex, vUV);
  if (uAlphaTest > 0.5 && t.a < 0.5) discard;
  vec3 albedo = (t.rgb * t.rgb) * vCol * uColor;
  vec3 n = normalize(vN);
  float ndl = max(dot(n, uSunDir), 0.0);
  vec3 amb = mix(uHemiGround, uHemiSky, n.y * 0.5 + 0.5) * 0.6;
  vec3 v = normalize(uCamPos - vW);
  vec3 h = normalize(uSunDir + v);
  float rough = clamp(uRME.x, 0.05, 1.0);
  float shin = mix(96.0, 8.0, rough);
  float spec = pow(max(dot(n, h), 0.0), shin) * uRME.y;
  vec3 col = albedo * (uSunColor * ndl + amb) + uSunColor * spec * ndl * 0.5;
  col = mix(col, albedo * 1.6, clamp(uRME.z, 0.0, 1.0));
  float d = length(uCamPos - vW);
  float f = 1.0 - exp(-uFogDensity * uFogDensity * d * d);
  col = mix(col, uFogColor, clamp(f, 0.0, 1.0));
  col = 1.0 - exp(-col * 1.35);
  fragColor = vec4(sqrt(max(col, vec3(0.0))), t.a);
})";

static const char *VS_SKIN = R"(#version 300 es
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNrm;
layout(location=2) in vec2 aUV;
layout(location=3) in vec3 aCol;
layout(location=4) in float aBone;
uniform mat4 uVP;
uniform mat4 uBones[24];
out vec3 vN; out vec2 vUV; out vec3 vCol; out vec3 vW;
void main(){
  mat4 b = uBones[int(aBone + 0.5)];
  vec4 w = b * vec4(aPos, 1.0);
  vW = w.xyz;
  vN = mat3(b) * aNrm;
  vUV = aUV; vCol = aCol;
  gl_Position = uVP * w;
})";

static const char *VS_OCEAN = R"(#version 300 es
layout(location=0) in vec3 aPos;
uniform mat4 uVP;
uniform float uTime;
uniform float uShip;
uniform vec4 uWaves[6];
out vec3 vW; out vec3 vN; out float vH;
void main(){
  vec3 p = aPos;
  vec2 xz = p.xz + vec2(uShip, 0.0);
  float dist = length(p.xz);
  float fade = smoothstep(1400.0, 250.0, dist);
  vec3 disp = vec3(0.0);
  vec3 T = vec3(1.0, 0.0, 0.0);
  vec3 B = vec3(0.0, 0.0, 1.0);
  for (int i = 0; i < 6; i++) {
    vec4 w = uWaves[i];
    float k = 6.2831853 / w.w;
    float c = sqrt(9.8 / k);
    vec2 d = w.xy;
    float st = w.z * fade;
    float f = k * (dot(d, xz) - c * uTime);
    float a = st / k;
    float sf = sin(f);
    float cf = cos(f);
    disp += vec3(d.x * a * cf, a * sf, d.y * a * cf);
    T += vec3(-d.x * d.x * st * sf, d.x * st * cf, -d.x * d.y * st * sf);
    B += vec3(-d.x * d.y * st * sf, d.y * st * cf, -d.y * d.y * st * sf);
  }
  float hullD = max(abs(p.z) - 12.5, 0.0) + max(-66.0 - p.x, 0.0) + max(p.x - 80.0, 0.0);
  float calm = smoothstep(0.0, 18.0, hullD) * 0.75 + 0.25;
  disp *= calm;
  p += disp;
  p.y += -7.5;
  vH = disp.y;
  vN = normalize(cross(B, T));
  vW = p;
  gl_Position = uVP * vec4(p, 1.0);
})";

static const char *FS_OCEAN = R"(#version 300 es
precision mediump float;
in vec3 vW; in vec3 vN; in float vH;
uniform vec3 uCamPos;
uniform vec3 uSunDir;
uniform vec3 uSunColor;
uniform vec3 uDeep;
uniform vec3 uShallow;
uniform vec3 uZen;
uniform vec3 uHor;
uniform vec3 uFogColor;
uniform float uFogDensity;
uniform float uTime;
out vec4 fragColor;
)"+ COMMON_NOISE + R"(
void main(){
  vec3 V = normalize(uCamPos - vW);
  float dist = length(uCamPos - vW);
  vec2 p = vW.xz;
  vec2 g = vec2(0.0);
  for (int i = 0; i < 8; i++) {
    float fi = float(i);
    float ang = fi * 2.399 + 0.3;
    vec2 d = vec2(cos(ang), sin(ang));
    float fr = 0.9 + fi * 0.55;
    float amp = 0.08 / (1.0 + fi * 0.6);
    float ph = dot(d, p * 1.3) * fr + uTime * (1.2 + fi * 0.37);
    g += d * cos(ph) * fr * amp;
  }
  g *= smoothstep(400.0, 30.0, dist);
  vec3 N = normalize(vN + vec3(-g.x, 0.0, -g.y) * 0.9);
  float nv = max(dot(N, V), 0.0);
  float F = 0.02 + 0.98 * pow(1.0 - nv, 5.0);
  vec3 R = reflect(-V, N); R.y = abs(R.y);
  vec3 sky = mix(uHor, uZen, pow(clamp(R.y, 0.0, 1.0), 0.45));
  float sd = max(dot(R, uSunDir), 0.0);
  float spec = pow(sd, 900.0) * 60.0 + pow(sd, 60.0) * 0.6;
  float sss = pow(max(dot(V, -uSunDir) * 0.5 + 0.5, 0.0), 3.0) * clamp(vH * 0.6 + 0.3, 0.0, 1.0);
  vec3 body = mix(uDeep, uShallow, clamp(vH * 0.35 + 0.25, 0.0, 1.0) * 0.6 + sss * 0.5);
  body *= (0.55 + 0.45 * max(uSunDir.y, 0.1));
  vec3 col = mix(body, sky, F) + uSunColor * spec;
  float ax = abs(vW.z);
  float bowT = clamp((vW.x - 58.0) / 28.0, 0.0, 1.0);
  float hullW = vW.x > 58.0 ? 12.25 * cos(bowT * 1.5707) : 12.25;
  float dh = ax - hullW;
  float n1 = fbm4(p * 0.35 + vec2(0.0, uTime * 0.3));
  float n2 = fbm4(p * 1.4 - vec2(uTime * 0.5, 0.0));
  float hullFoam = smoothstep(2.2, 0.0, dh) * step(-66.0, vW.x) * step(vW.x, 88.0) * (0.35 + 0.65 * smoothstep(-40.0, 60.0, vW.x));
  float behind = -66.0 - vW.x;
  float wakeW = 9.0 + behind * 0.18;
  float wake = step(0.0, behind) * smoothstep(wakeW, wakeW * 0.1, ax) * exp(-behind / 300.0);
  float kel = -vW.x + 60.0;
  float kz = ax - 12.0 - kel * 0.354;
  float kelvin = step(0.0, kel) * exp(-abs(kz) * 0.9) * exp(-kel / 200.0) * 0.35;
  float foam = clamp(hullFoam * 0.8 + wake * 0.9 + kelvin, 0.0, 1.5);
  foam *= smoothstep(0.45, 0.85, n1 * 0.6 + n2 * 0.55 + foam * 0.2);
  float crest = smoothstep(0.9, 1.6, vH) * smoothstep(0.55, 0.8, n2) * 0.5;
  foam = clamp(foam + crest, 0.0, 1.0);
  vec3 foamCol = vec3(0.92, 0.95, 0.97) * (0.6 + 0.4 * max(uSunDir.y, 0.2)) * (uSunColor * 0.4 + 0.6);
  col = mix(col, foamCol, foam * 0.9);
  float f = 1.0 - exp(-uFogDensity * uFogDensity * dist * dist);
  col = mix(col, uFogColor, clamp(f, 0.0, 1.0));
  col = 1.0 - exp(-col * 1.35);
  fragColor = vec4(sqrt(max(col, vec3(0.0))), 1.0);
})";

static const char *VS_SKY = R"(#version 300 es
layout(location=0) in vec2 aPos;
out vec2 vNdc;
void main(){ vNdc = aPos; gl_Position = vec4(aPos, 0.99999, 1.0); })";

static const char *FS_SKY = R"(#version 300 es
precision mediump float;
in vec2 vNdc;
uniform mat4 uInvVP;
uniform vec3 uCamPos;
uniform vec3 uSunDir;
uniform vec3 uZen;
uniform vec3 uHor;
uniform vec3 uFogColor;
uniform float uTime;
out vec4 fragColor;
)"+ COMMON_NOISE + R"(
void main(){
  vec4 far = uInvVP * vec4(vNdc, 1.0, 1.0);
  vec3 dir = normalize(far.xyz / far.w - uCamPos);
  vec3 col;
  if (dir.y < 0.0) {
    col = mix(uHor, uHor * 0.9, clamp(-dir.y * 4.0, 0.0, 1.0));
  } else {
    col = mix(uHor, uZen, pow(clamp(dir.y, 0.0, 1.0), 0.42));
  }
  float sd = max(dot(dir, uSunDir), 0.0);
  col += uFogColor * pow(sd, 8.0) * 0.35;
  col += vec3(1.3, 1.05, 0.8) * smoothstep(0.9992, 0.9997, sd) * 3.0;
  if (dir.y > 0.02) {
    vec2 cuv = dir.xz / max(dir.y, 0.05) * 0.55 + vec2(uTime * 0.008, 0.0);
    float n = fbm6(cuv);
    float d = smoothstep(0.47, 0.75, n);
    float lit = clamp(0.55 + (n - fbm4(cuv * 1.8 + vec2(3.1, 1.7))) * 1.6, 0.0, 1.0);
    vec3 cloud = mix(uHor * 0.72, vec3(1.0, 0.99, 0.97), lit);
    col = mix(col, cloud, d * 0.7 * smoothstep(0.02, 0.2, dir.y));
  }
  col = 1.0 - exp(-col * 1.35);
  fragColor = vec4(sqrt(max(col, vec3(0.0))), 1.0);
})";

static const char *VS_QUAD = R"(#version 300 es
layout(location=0) in vec3 aPos;
layout(location=1) in vec2 aUV;
layout(location=2) in vec4 aCol;
uniform mat4 uVP;
out vec2 vUV; out vec4 vCol;
void main(){ vUV = aUV; vCol = aCol; gl_Position = uVP * vec4(aPos, 1.0); })";

static const char *FS_QUAD = R"(#version 300 es
precision mediump float;
in vec2 vUV; in vec4 vCol;
uniform sampler2D uTex;
out vec4 fragColor;
void main(){
  vec4 t = texture(uTex, vUV);
  vec3 c = (t.rgb * t.rgb) * vCol.rgb;
  fragColor = vec4(c, t.a * vCol.a);
})";

// ---------------- 矩阵求逆（列主序，gl-matrix 实现） ----------------
static bool MatInvert(const float *a, float *out)
{
    float a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3];
    float a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7];
    float a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11];
    float a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];

    float b00 = a00 * a11 - a01 * a10;
    float b01 = a00 * a12 - a02 * a10;
    float b02 = a00 * a13 - a03 * a10;
    float b03 = a01 * a12 - a02 * a11;
    float b04 = a01 * a13 - a03 * a11;
    float b05 = a02 * a13 - a03 * a12;
    float b06 = a20 * a31 - a21 * a30;
    float b07 = a20 * a32 - a22 * a30;
    float b08 = a20 * a33 - a23 * a30;
    float b09 = a21 * a32 - a22 * a31;
    float b10 = a21 * a33 - a23 * a31;
    float b11 = a22 * a33 - a23 * a32;

    float det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
    if (fabsf(det) < 1e-12f) {
        return false;
    }
    float id = 1.0f / det;
    out[0] = (a11 * b11 - a12 * b10 + a13 * b09) * id;
    out[1] = (a02 * b10 - a01 * b11 - a03 * b09) * id;
    out[2] = (a31 * b05 - a32 * b04 + a33 * b03) * id;
    out[3] = (a22 * b04 - a21 * b05 - a23 * b03) * id;
    out[4] = (a12 * b08 - a10 * b11 - a13 * b07) * id;
    out[5] = (a00 * b11 - a02 * b08 + a03 * b07) * id;
    out[6] = (a32 * b02 - a30 * b05 - a33 * b01) * id;
    out[7] = (a20 * b05 - a22 * b02 + a23 * b01) * id;
    out[8] = (a10 * b10 - a11 * b08 + a13 * b06) * id;
    out[9] = (a01 * b08 - a00 * b10 - a03 * b06) * id;
    out[10] = (a30 * b04 - a31 * b02 + a33 * b00) * id;
    out[11] = (a21 * b02 - a20 * b04 - a23 * b00) * id;
    out[12] = (a11 * b07 - a10 * b09 - a12 * b06) * id;
    out[13] = (a00 * b09 - a01 * b07 + a02 * b06) * id;
    out[14] = (a31 * b01 - a30 * b03 - a32 * b00) * id;
    out[15] = (a20 * b03 - a21 * b01 + a22 * b00) * id;
    return true;
}

// ---------------- 工具 ----------------
Renderer &Renderer::Instance()
{
    static Renderer inst;
    return inst;
}

GLuint Renderer::CompileShader(GLenum type, const char *src)
{
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, nullptr);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024] = {0};
        GLsizei len = 0;
        glGetShaderInfoLog(s, sizeof(log) - 1, &len, log);
        LOG_W("shader compile failed: %{public}s", log);
        glDeleteShader(s);
        return 0;
    }
    return s;
}

GLuint Renderer::LinkProgram(const char *vs, const char *fs)
{
    GLuint v = CompileShader(GL_VERTEX_SHADER, vs);
    GLuint f = CompileShader(GL_FRAGMENT_SHADER, fs);
    if (v == 0 || f == 0) {
        if (v) glDeleteShader(v);
        if (f) glDeleteShader(f);
        return 0;
    }
    GLuint p = glCreateProgram();
    glAttachShader(p, v);
    glAttachShader(p, f);
    glLinkProgram(p);
    glDeleteShader(v);
    glDeleteShader(f);
    GLint ok = 0;
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[1024] = {0};
        GLsizei len = 0;
        glGetProgramInfoLog(p, sizeof(log) - 1, &len, log);
        LOG_W("program link failed: %{public}s", log);
        glDeleteProgram(p);
        return 0;
    }
    return p;
}

// ---------------- 生命周期 ----------------
bool Renderer::EnsureContext(void *window)
{
    if (display_ == EGL_NO_DISPLAY) {
        display_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (display_ == EGL_NO_DISPLAY) {
            return false;
        }
        if (!eglInitialize(display_, nullptr, nullptr)) {
            display_ = EGL_NO_DISPLAY;
            return false;
        }
    }
    if (config_ == nullptr) {
        const EGLint attribs[] = {
            EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
            EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
            EGL_DEPTH_SIZE, 24, EGL_STENCIL_SIZE, 0,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
            EGL_NONE
        };
        EGLint num = 0;
        if (!eglChooseConfig(display_, attribs, &config_, 1, &num) || num < 1) {
            const EGLint attribs2[] = {
                EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
                EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
                EGL_DEPTH_SIZE, 24,
                EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                EGL_NONE
            };
            config_ = nullptr;
            if (!eglChooseConfig(display_, attribs2, &config_, 1, &num) || num < 1) {
                return false;
            }
        }
    }
    if (context_ == EGL_NO_CONTEXT) {
        const EGLint ctxAttribs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
        context_ = eglCreateContext(display_, config_, EGL_NO_CONTEXT, ctxAttribs);
        if (context_ == EGL_NO_CONTEXT) {
            const EGLint ctx2[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
            context_ = eglCreateContext(display_, config_, EGL_NO_CONTEXT, ctx2);
            if (context_ == EGL_NO_CONTEXT) {
                return false;
            }
        }
    }
    if (surface_ == EGL_NO_SURFACE) {
        surface_ = eglCreateWindowSurface(display_, config_, (EGLNativeWindowType)window, nullptr);
        if (surface_ == EGL_NO_SURFACE) {
            return false;
        }
    }
    if (!eglMakeCurrent(display_, surface_, surface_, context_)) {
        return false;
    }
    if (!glReady_) {
        InitGLState();
    }
    return true;
}

void Renderer::InitGLState()
{
    glReady_ = true;
    progStatic_ = LinkProgram(VS_STATIC, FS_STATIC);
    progSkin_ = LinkProgram(VS_SKIN, FS_STATIC);
    progOcean_ = LinkProgram(VS_OCEAN, FS_OCEAN);
    progSky_ = LinkProgram(VS_SKY, FS_SKY);
    progQuad_ = LinkProgram(VS_QUAD, FS_QUAD);

    if (progStatic_) {
        stUVP_ = glGetUniformLocation(progStatic_, "uVP");
        stUModel_ = glGetUniformLocation(progStatic_, "uModel");
        stUTex_ = glGetUniformLocation(progStatic_, "uTex");
        stUColor_ = glGetUniformLocation(progStatic_, "uColor");
        stURME_ = glGetUniformLocation(progStatic_, "uRME");
        stUSunDir_ = glGetUniformLocation(progStatic_, "uSunDir");
        stUSunCol_ = glGetUniformLocation(progStatic_, "uSunColor");
        stUHemiSky_ = glGetUniformLocation(progStatic_, "uHemiSky");
        stUHemiGnd_ = glGetUniformLocation(progStatic_, "uHemiGround");
        stUFogCol_ = glGetUniformLocation(progStatic_, "uFogColor");
        stUCamPos_ = glGetUniformLocation(progStatic_, "uCamPos");
        stUFogDen_ = glGetUniformLocation(progStatic_, "uFogDensity");
        stUAlphaTest_ = glGetUniformLocation(progStatic_, "uAlphaTest");
    }
    if (progSkin_) {
        skUVP_ = glGetUniformLocation(progSkin_, "uVP");
        skUBones_ = glGetUniformLocation(progSkin_, "uBones");
        skUTex_ = glGetUniformLocation(progSkin_, "uTex");
        skUColor_ = glGetUniformLocation(progSkin_, "uColor");
        skURME_ = glGetUniformLocation(progSkin_, "uRME");
        skUSunDir_ = glGetUniformLocation(progSkin_, "uSunDir");
        skUSunCol_ = glGetUniformLocation(progSkin_, "uSunColor");
        skUHemiSky_ = glGetUniformLocation(progSkin_, "uHemiSky");
        skUHemiGnd_ = glGetUniformLocation(progSkin_, "uHemiGround");
        skUFogCol_ = glGetUniformLocation(progSkin_, "uFogColor");
        skUCamPos_ = glGetUniformLocation(progSkin_, "uCamPos");
        skUFogDen_ = glGetUniformLocation(progSkin_, "uFogDensity");
        skUAlphaTest_ = glGetUniformLocation(progSkin_, "uAlphaTest");
    }
    if (progOcean_) {
        ocUVP_ = glGetUniformLocation(progOcean_, "uVP");
        ocUTime_ = glGetUniformLocation(progOcean_, "uTime");
        ocUShip_ = glGetUniformLocation(progOcean_, "uShip");
        ocUWaves_ = glGetUniformLocation(progOcean_, "uWaves");
        ocUCamPos_ = glGetUniformLocation(progOcean_, "uCamPos");
        ocUSunDir_ = glGetUniformLocation(progOcean_, "uSunDir");
        ocUSunCol_ = glGetUniformLocation(progOcean_, "uSunColor");
        ocUDeep_ = glGetUniformLocation(progOcean_, "uDeep");
        ocUShallow_ = glGetUniformLocation(progOcean_, "uShallow");
        ocUZen_ = glGetUniformLocation(progOcean_, "uZen");
        ocUHor_ = glGetUniformLocation(progOcean_, "uHor");
        ocUFogCol_ = glGetUniformLocation(progOcean_, "uFogColor");
        ocUFogDen_ = glGetUniformLocation(progOcean_, "uFogDensity");
    }
    if (progSky_) {
        sk2UInvVP_ = glGetUniformLocation(progSky_, "uInvVP");
        sk2UCamPos_ = glGetUniformLocation(progSky_, "uCamPos");
        sk2USunDir_ = glGetUniformLocation(progSky_, "uSunDir");
        sk2UZen_ = glGetUniformLocation(progSky_, "uZen");
        sk2UHor_ = glGetUniformLocation(progSky_, "uHor");
        sk2UFogCol_ = glGetUniformLocation(progSky_, "uFogColor");
        sk2UTime_ = glGetUniformLocation(progSky_, "uTime");
    }
    if (progQuad_) {
        qdUVP_ = glGetUniformLocation(progQuad_, "uVP");
        qdUTex_ = glGetUniformLocation(progQuad_, "uTex");
    }

    // 海洋极坐标网格：中心密、远处疏
    {
        const int rings = 100;
        const int segs = 128;
        std::vector<float> pos;
        pos.reserve((size_t)(rings + 1) * segs * 3);
        std::vector<uint32_t> idx;
        idx.reserve((size_t)rings * segs * 6);
        for (int r = 0; r <= rings; r++) {
            float rad = r == 0 ? 0.0f : 6.0f * powf(1.058f, (float)r) - 5.0f;
            for (int s = 0; s < segs; s++) {
                float a = ((float)s / segs) * 6.2831853f;
                pos.push_back(cosf(a) * rad);
                pos.push_back(0.0f);
                pos.push_back(sinf(a) * rad);
            }
        }
        for (int r = 0; r < rings; r++) {
            for (int s = 0; s < segs; s++) {
                uint32_t a = (uint32_t)(r * segs + s);
                uint32_t b = (uint32_t)(r * segs + (s + 1) % segs);
                uint32_t c = a + segs;
                uint32_t d = b + segs;
                idx.push_back(a); idx.push_back(b); idx.push_back(c);
                idx.push_back(b); idx.push_back(d); idx.push_back(c);
            }
        }
        oceanIndexCount_ = (uint32_t)idx.size();
        glGenVertexArrays(1, &oceanVao_);
        glBindVertexArray(oceanVao_);
        glGenBuffers(1, &oceanVbo_);
        glBindBuffer(GL_ARRAY_BUFFER, oceanVbo_);
        glBufferData(GL_ARRAY_BUFFER, pos.size() * sizeof(float), pos.data(), GL_STATIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 12, (void *)0);
        glGenBuffers(1, &oceanIbo_);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, oceanIbo_);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx.size() * sizeof(uint32_t), idx.data(), GL_STATIC_DRAW);
        glBindVertexArray(0);
    }

    // 天空全屏三角形
    {
        const float tri[] = {-1, -1, 3, -1, -1, 3};
        glGenVertexArrays(1, &skyVao_);
        glBindVertexArray(skyVao_);
        glGenBuffers(1, &skyVbo_);
        glBindBuffer(GL_ARRAY_BUFFER, skyVbo_);
        glBufferData(GL_ARRAY_BUFFER, sizeof(tri), tri, GL_STATIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 8, (void *)0);
        glBindVertexArray(0);
    }

    // 动态四边形缓冲（pos3 uv2 col4 = 9 浮点/顶点）
    {
        glGenVertexArrays(1, &quadVao_);
        glBindVertexArray(quadVao_);
        glGenBuffers(1, &quadVbo_);
        glBindBuffer(GL_ARRAY_BUFFER, quadVbo_);
        glBufferData(GL_ARRAY_BUFFER, (size_t)(320 + 1200) * 6 * 9 * sizeof(float), nullptr, GL_DYNAMIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 36, (void *)0);
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 36, (void *)12);
        glEnableVertexAttribArray(2);
        glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, 36, (void *)20);
        glBindVertexArray(0);
    }

    vmAlphaVerts_.reserve(16 * 54);
    vmAddVerts_.reserve(16 * 54);

    LOG_I("GL init done, version: %{public}s", (const char *)glGetString(GL_VERSION));
}

void Renderer::OnSurfaceCreated(void *window, int w, int h)
{
    if (EnsureContext(window)) {
        width_ = w;
        height_ = h;
        ready_ = true;
    } else {
        ready_ = false;
        LOG_W("EnsureContext failed");
    }
}

void Renderer::OnSurfaceChanged(int w, int h)
{
    width_ = w;
    height_ = h;
}

void Renderer::ReleaseSurface()
{
    if (display_ != EGL_NO_DISPLAY) {
        eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    if (surface_ != EGL_NO_SURFACE) {
        eglDestroySurface(display_, surface_);
        surface_ = EGL_NO_SURFACE;
    }
    ready_ = false;
}

void Renderer::OnSurfaceDestroyed()
{
    ReleaseSurface();
}

// ---------------- 资源上传 ----------------
void Renderer::CreateTexture(int id, int w, int h, const uint8_t *rgba)
{
    if (!glReady_) {
        return;
    }
    auto it = textures_.find(id);
    if (it != textures_.end()) {
        glDeleteTextures(1, &it->second);
    }
    GLuint tex = 0;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
    glGenerateMipmap(GL_TEXTURE_2D);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    textures_[id] = tex;
}

void Renderer::UploadMesh(int id, int texId, uint32_t flags, const float matParams[8], const float *vdata,
                          size_t vfloats, const uint32_t *idata, size_t icount)
{
    if (!glReady_) {
        return;
    }
    auto it = meshes_.find(id);
    if (it != meshes_.end()) {
        if (it->second.vao) glDeleteVertexArrays(1, &it->second.vao);
        if (it->second.vbo) glDeleteBuffers(1, &it->second.vbo);
        if (it->second.ibo) glDeleteBuffers(1, &it->second.ibo);
        meshes_.erase(it);
    }
    Mesh m;
    m.texId = texId;
    m.color[0] = matParams[0];
    m.color[1] = matParams[1];
    m.color[2] = matParams[2];
    m.rme[0] = matParams[3];
    m.rme[1] = matParams[4];
    m.rme[2] = matParams[5];
    m.flags = flags;
    m.indexCount = (uint32_t)icount;

    bool skin = (flags & 8) != 0;
    int stride = skin ? 12 : 11;
    glGenVertexArrays(1, &m.vao);
    glBindVertexArray(m.vao);
    glGenBuffers(1, &m.vbo);
    glBindBuffer(GL_ARRAY_BUFFER, m.vbo);
    glBufferData(GL_ARRAY_BUFFER, vfloats * sizeof(float), vdata, GL_STATIC_DRAW);
    size_t f4 = sizeof(float) * 4;
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride * f4, (void *)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, stride * f4, (void *)(3 * f4));
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, stride * f4, (void *)(6 * f4));
    glEnableVertexAttribArray(3);
    glVertexAttribPointer(3, 3, GL_FLOAT, GL_FALSE, stride * f4, (void *)(8 * f4));
    if (skin) {
        glEnableVertexAttribArray(4);
        glVertexAttribPointer(4, 1, GL_FLOAT, GL_FALSE, stride * f4, (void *)(11 * f4));
    }
    glGenBuffers(1, &m.ibo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m.ibo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, icount * sizeof(uint32_t), idata, GL_STATIC_DRAW);
    glBindVertexArray(0);

    meshes_[id] = m;
}

// ---------------- 每帧绘制 ----------------
void Renderer::DrawDynMeshes(const float *f)
{
    int n = (int)f[OFF_NDYN];
    if (n > 12) {
        n = 12;
    }
    if (n <= 0 || !progStatic_) {
        return;
    }
    glUseProgram(progStatic_);
    glUniformMatrix4fv(stUVP_, 1, GL_FALSE, f + OFF_WORLDVP);
    glUniform1i(stUTex_, 0);
    glUniform3f(stUSunDir_, f[OFF_SUNDIR], f[OFF_SUNDIR + 1], f[OFF_SUNDIR + 2]);
    glUniform3f(stUSunCol_, f[OFF_SUNCOL], f[OFF_SUNCOL + 1], f[OFF_SUNCOL + 2]);
    glUniform3f(stUHemiSky_, f[OFF_HEMISKY], f[OFF_HEMISKY + 1], f[OFF_HEMISKY + 2]);
    glUniform3f(stUHemiGnd_, f[OFF_HEMIGND], f[OFF_HEMIGND + 1], f[OFF_HEMIGND + 2]);
    glUniform3f(stUFogCol_, f[OFF_FOGCOL], f[OFF_FOGCOL + 1], f[OFF_FOGCOL + 2]);
    glUniform3f(stUCamPos_, f[OFF_CAMPOS], f[OFF_CAMPOS + 1], f[OFF_CAMPOS + 2]);
    glUniform1f(stUFogDen_, f[OFF_FOGDEN]);
    glActiveTexture(GL_TEXTURE0);
    for (int i = 0; i < n; i++) {
        const float *rec = f + OFF_DYN + i * DYN_STRIDE;
        int meshId = (int)rec[0];
        if (meshId <= 0) {
            continue;
        }
        auto mit = meshes_.find(meshId);
        if (mit == meshes_.end()) {
            continue;
        }
        Mesh &m = mit->second;
        auto tit = textures_.find(m.texId);
        glBindTexture(GL_TEXTURE_2D, tit != textures_.end() ? tit->second : 0);
        glUniform3fv(stUColor_, 1, m.color);
        glUniform3fv(stURME_, 1, m.rme);
        glUniform1f(stUAlphaTest_, (m.flags & 1) ? 1.0f : 0.0f);
        glUniformMatrix4fv(stUModel_, 1, GL_FALSE, rec + 1);
        if (m.flags & 2) {
            glDisable(GL_CULL_FACE);
        }
        glBindVertexArray(m.vao);
        glDrawElements(GL_TRIANGLES, m.indexCount, GL_UNSIGNED_INT, (void *)0);
        glBindVertexArray(0);
        if (m.flags & 2) {
            glDisable(GL_CULL_FACE) /* 双面渲染：规避程序化几何绕向差异 */;
        }
    }
}

void Renderer::DrawSky(const float *f)
{
    if (!progSky_) {
        return;
    }
    if (!MatInvert(f + OFF_WORLDVP, invVP_)) {
        return;
    }
    glDepthMask(GL_FALSE);
    glDisable(GL_DEPTH_TEST);
    glUseProgram(progSky_);
    glUniformMatrix4fv(sk2UInvVP_, 1, GL_FALSE, invVP_);
    glUniform3f(sk2UCamPos_, f[OFF_CAMPOS], f[OFF_CAMPOS + 1], f[OFF_CAMPOS + 2]);
    glUniform3f(sk2USunDir_, f[OFF_SUNDIR], f[OFF_SUNDIR + 1], f[OFF_SUNDIR + 2]);
    glUniform3f(sk2UZen_, f[OFF_HEMISKY] * 0.8f, f[OFF_HEMISKY + 1] * 0.88f, f[OFF_HEMISKY + 2]);
    glUniform3f(sk2UHor_, f[OFF_FOGCOL], f[OFF_FOGCOL + 1], f[OFF_FOGCOL + 2]);
    glUniform3f(sk2UFogCol_, f[OFF_FOGCOL], f[OFF_FOGCOL + 1], f[OFF_FOGCOL + 2]);
    glUniform1f(sk2UTime_, f[OFF_TIME]);
    glBindVertexArray(skyVao_);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glBindVertexArray(0);
    glDepthMask(GL_TRUE);
    glEnable(GL_DEPTH_TEST);
}

void Renderer::DrawStaticMeshes(const float *f)
{
    if (!progStatic_ || meshes_.empty()) {
        return;
    }
    glUseProgram(progStatic_);
    glUniformMatrix4fv(stUVP_, 1, GL_FALSE, f + OFF_WORLDVP);
    glUniformMatrix4fv(stUModel_, 1, GL_FALSE, IDENT_MAT);
    glUniform1i(stUTex_, 0);
    glUniform3f(stUSunDir_, f[OFF_SUNDIR], f[OFF_SUNDIR + 1], f[OFF_SUNDIR + 2]);
    glUniform3f(stUSunCol_, f[OFF_SUNCOL], f[OFF_SUNCOL + 1], f[OFF_SUNCOL + 2]);
    glUniform3f(stUHemiSky_, f[OFF_HEMISKY], f[OFF_HEMISKY + 1], f[OFF_HEMISKY + 2]);
    glUniform3f(stUHemiGnd_, f[OFF_HEMIGND], f[OFF_HEMIGND + 1], f[OFF_HEMIGND + 2]);
    glUniform3f(stUFogCol_, f[OFF_FOGCOL], f[OFF_FOGCOL + 1], f[OFF_FOGCOL + 2]);
    glUniform3f(stUCamPos_, f[OFF_CAMPOS], f[OFF_CAMPOS + 1], f[OFF_CAMPOS + 2]);
    glUniform1f(stUFogDen_, f[OFF_FOGDEN]);
    glActiveTexture(GL_TEXTURE0);
    for (auto &kv : meshes_) {
        if (kv.first >= 9000) {
            continue; // 动态网格（士兵/枪械/武器层）另行绘制
        }
        Mesh &m = kv.second;
        if (m.flags & 8) {
            continue;
        }
        auto t = textures_.find(m.texId);
        glBindTexture(GL_TEXTURE_2D, t != textures_.end() ? t->second : 0);
        glUniform3fv(stUColor_, 1, m.color);
        float rme[3] = {m.rme[0], m.rme[1], (m.flags & 4) ? 1.0f : m.rme[2]};
        glUniform3fv(stURME_, 1, rme);
        glUniform1f(stUAlphaTest_, (m.flags & 1) ? 1.0f : 0.0f);
        if (m.flags & 2) {
            glDisable(GL_CULL_FACE);
        }
        glBindVertexArray(m.vao);
        glDrawElements(GL_TRIANGLES, m.indexCount, GL_UNSIGNED_INT, (void *)0);
        glBindVertexArray(0);
        if (m.flags & 2) {
            glDisable(GL_CULL_FACE) /* 双面渲染：规避程序化几何绕向差异 */;
        }
    }
}

void Renderer::DrawOcean(const float *f)
{
    if (!progOcean_ || oceanIndexCount_ == 0) {
        return;
    }
    const float waves[6][4] = {
        {1.0f, 0.25f, 0.10f, 58}, {0.9f, 0.55f, 0.09f, 33}, {0.75f, -0.45f, 0.08f, 19},
        {0.25f, 1.0f, 0.07f, 11}, {-0.5f, 0.8f, 0.05f, 6.5f}, {0.95f, -0.1f, 0.05f, 4.2f},
    };
    float wn[24];
    for (int i = 0; i < 6; i++) {
        float l = sqrtf(waves[i][0] * waves[i][0] + waves[i][1] * waves[i][1]);
        wn[i * 4 + 0] = waves[i][0] / l;
        wn[i * 4 + 1] = waves[i][1] / l;
        wn[i * 4 + 2] = waves[i][2];
        wn[i * 4 + 3] = waves[i][3];
    }
    glUseProgram(progOcean_);
    glUniformMatrix4fv(ocUVP_, 1, GL_FALSE, f + OFF_WORLDVP);
    glUniform1f(ocUTime_, f[OFF_TIME]);
    glUniform1f(ocUShip_, f[OFF_TIME] * 6.5f);
    glUniform4fv(ocUWaves_, 6, wn);
    glUniform3f(ocUCamPos_, f[OFF_CAMPOS], f[OFF_CAMPOS + 1], f[OFF_CAMPOS + 2]);
    glUniform3f(ocUSunDir_, f[OFF_SUNDIR], f[OFF_SUNDIR + 1], f[OFF_SUNDIR + 2]);
    glUniform3f(ocUSunCol_, f[OFF_SUNCOL], f[OFF_SUNCOL + 1], f[OFF_SUNCOL + 2]);
    glUniform3f(ocUDeep_, f[OFF_FOGCOL] * 0.22f, f[OFF_FOGCOL + 1] * 0.35f, f[OFF_FOGCOL + 2] * 0.55f);
    glUniform3f(ocUShallow_, f[OFF_FOGCOL] * 0.45f, f[OFF_FOGCOL + 1] * 0.6f, f[OFF_FOGCOL + 2] * 0.65f);
    glUniform3f(ocUZen_, f[OFF_HEMISKY] * 0.8f, f[OFF_HEMISKY + 1] * 0.88f, f[OFF_HEMISKY + 2]);
    glUniform3f(ocUHor_, f[OFF_FOGCOL], f[OFF_FOGCOL + 1], f[OFF_FOGCOL + 2]);
    glUniform3f(ocUFogCol_, f[OFF_FOGCOL], f[OFF_FOGCOL + 1], f[OFF_FOGCOL + 2]);
    glUniform1f(ocUFogDen_, f[OFF_FOGDEN]);
    glBindVertexArray(oceanVao_);
    glDrawElements(GL_TRIANGLES, oceanIndexCount_, GL_UNSIGNED_INT, (void *)0);
    glBindVertexArray(0);
}

void Renderer::DrawSoldiers(const float *f)
{
    int n = (int)f[OFF_NSOLDIER];
    if (n > 16) {
        n = 16;
    }
    if (!progSkin_ || n == 0) {
        return;
    }
    glUseProgram(progSkin_);
    glUniformMatrix4fv(skUVP_, 1, GL_FALSE, f + OFF_WORLDVP);
    glUniform1i(skUTex_, 0);
    glUniform3f(skUSunDir_, f[OFF_SUNDIR], f[OFF_SUNDIR + 1], f[OFF_SUNDIR + 2]);
    glUniform3f(skUSunCol_, f[OFF_SUNCOL], f[OFF_SUNCOL + 1], f[OFF_SUNCOL + 2]);
    glUniform3f(skUHemiSky_, f[OFF_HEMISKY], f[OFF_HEMISKY + 1], f[OFF_HEMISKY + 2]);
    glUniform3f(skUHemiGnd_, f[OFF_HEMIGND], f[OFF_HEMIGND + 1], f[OFF_HEMIGND + 2]);
    glUniform3f(skUFogCol_, f[OFF_FOGCOL], f[OFF_FOGCOL + 1], f[OFF_FOGCOL + 2]);
    glUniform3f(skUCamPos_, f[OFF_CAMPOS], f[OFF_CAMPOS + 1], f[OFF_CAMPOS + 2]);
    glUniform1f(skUFogDen_, f[OFF_FOGDEN]);
    glUniform1f(skUAlphaTest_, 0);
    glActiveTexture(GL_TEXTURE0);
    float bones[MAX_BONES * 16];

    // 第三人称枪用静态程序 + uModel
    float gunDraws[16][2]; // [士兵索引, 枪网格 id]
    int gunN = 0;

    for (int i = 0; i < n; i++) {
        const float *rec = f + OFF_SOLDIERS + i * SOLDIER_STRIDE;
        int visible = (int)rec[304];
        if (visible <= 0) {
            continue;
        }
        int teamMeshId = visible == 2 ? 9001 : 9000;
        auto mit = meshes_.find(teamMeshId);
        if (mit == meshes_.end()) {
            continue;
        }
        Mesh &m = mit->second;
        auto tit = textures_.find(m.texId);
        glBindTexture(GL_TEXTURE_2D, tit != textures_.end() ? tit->second : 0);
        glUniform3fv(skUColor_, 1, m.color);
        glUniform3fv(skURME_, 1, m.rme);
        memcpy(bones, rec, 19 * 16 * sizeof(float));
        for (int b = 19; b < MAX_BONES; b++) {
            memcpy(bones + b * 16, IDENT_MAT, sizeof(IDENT_MAT));
        }
        glUniformMatrix4fv(skUBones_, MAX_BONES, GL_FALSE, bones);
        glBindVertexArray(m.vao);
        glDrawElements(GL_TRIANGLES, m.indexCount, GL_UNSIGNED_INT, (void *)0);
        glBindVertexArray(0);

        int gunId = (int)rec[305];
        if (gunId > 0 && gunN < 16) {
            gunDraws[gunN][0] = (float)i;
            gunDraws[gunN][1] = (float)gunId;
            gunN++;
        }
    }

    // 第三人称枪械（静态网格 + 逐枪模型矩阵）
    if (gunN > 0 && progStatic_) {
        glUseProgram(progStatic_);
        glUniformMatrix4fv(stUVP_, 1, GL_FALSE, f + OFF_WORLDVP);
        glUniform1i(stUTex_, 0);
        glUniform3f(stUSunDir_, f[OFF_SUNDIR], f[OFF_SUNDIR + 1], f[OFF_SUNDIR + 2]);
        glUniform3f(stUSunCol_, f[OFF_SUNCOL], f[OFF_SUNCOL + 1], f[OFF_SUNCOL + 2]);
        glUniform3f(stUHemiSky_, f[OFF_HEMISKY], f[OFF_HEMISKY + 1], f[OFF_HEMISKY + 2]);
        glUniform3f(stUHemiGnd_, f[OFF_HEMIGND], f[OFF_HEMIGND + 1], f[OFF_HEMIGND + 2]);
        glUniform3f(stUFogCol_, f[OFF_FOGCOL], f[OFF_FOGCOL + 1], f[OFF_FOGCOL + 2]);
        glUniform3f(stUCamPos_, f[OFF_CAMPOS], f[OFF_CAMPOS + 1], f[OFF_CAMPOS + 2]);
        glUniform1f(stUFogDen_, f[OFF_FOGDEN]);
        glUniform1f(stUAlphaTest_, 0);
        for (int k = 0; k < gunN; k++) {
            int si = (int)gunDraws[k][0];
            int gunId = (int)gunDraws[k][1];
            const float *rec = f + OFF_SOLDIERS + si * SOLDIER_STRIDE;
            auto git = meshes_.find(gunId);
            if (git == meshes_.end()) {
                continue;
            }
            Mesh &gm = git->second;
            auto gt = textures_.find(gm.texId);
            glBindTexture(GL_TEXTURE_2D, gt != textures_.end() ? gt->second : 0);
            glUniform3fv(stUColor_, 1, gm.color);
            glUniform3fv(stURME_, 1, gm.rme);
            glUniformMatrix4fv(stUModel_, 1, GL_FALSE, rec + 306);
            if (gm.flags & 2) {
                glDisable(GL_CULL_FACE);
            }
            glBindVertexArray(gm.vao);
            glDrawElements(GL_TRIANGLES, gm.indexCount, GL_UNSIGNED_INT, (void *)0);
            glBindVertexArray(0);
            if (gm.flags & 2) {
                glDisable(GL_CULL_FACE) /* 双面渲染：规避程序化几何绕向差异 */;
            }
        }
    }
}

static void PushQuad(std::vector<float> &out, const float *rx, const float *ux, const float *center, float hl, float hw,
                     float r, float g, float b, float a, float u0, float v0, float u1, float v1)
{
    const float corners[6][2] = {{-1, -1}, {1, -1}, {1, 1}, {-1, -1}, {1, 1}, {-1, 1}};
    const float uvs[6][2] = {{0, 0}, {1, 0}, {1, 1}, {0, 0}, {1, 1}, {0, 1}};
    for (int i = 0; i < 6; i++) {
        float sx = corners[i][0] * hl;
        float sy = corners[i][1] * hw;
        out.push_back(center[0] + rx[0] * sx + ux[0] * sy);
        out.push_back(center[1] + rx[1] * sx + ux[1] * sy);
        out.push_back(center[2] + rx[2] * sx + ux[2] * sy);
        out.push_back(uvs[i][0] ? u1 : u0);
        out.push_back(uvs[i][1] ? v1 : v0);
        out.push_back(r);
        out.push_back(g);
        out.push_back(b);
        out.push_back(a);
    }
}

void Renderer::DrawQuads(const float *f)
{
    if (!progQuad_) {
        return;
    }
    int nq = (int)f[OFF_NQUAD];
    if (nq > 320) {
        nq = 320;
    }
    int np = (int)f[OFF_NPART];
    if (np > 1200) {
        np = 1200;
    }
    if (nq == 0 && np == 0) {
        return;
    }
    float inv[16];
    if (!MatInvert(f + OFF_WORLDVP, inv)) {
        return;
    }
    float camR[3] = {inv[0], inv[1], inv[2]};
    float camU[3] = {inv[4], inv[5], inv[6]};
    float camPos[3] = {f[OFF_CAMPOS], f[OFF_CAMPOS + 1], f[OFF_CAMPOS + 2]};
    float rl = sqrtf(camR[0] * camR[0] + camR[1] * camR[1] + camR[2] * camR[2]);
    float ul = sqrtf(camU[0] * camU[0] + camU[1] * camU[1] + camU[2] * camU[2]);
    if (rl > 1e-6f) { camR[0] /= rl; camR[1] /= rl; camR[2] /= rl; }
    if (ul > 1e-6f) { camU[0] /= ul; camU[1] /= ul; camU[2] /= ul; }

    for (auto &kv : quadBuckets_) {
        kv.second.alpha.clear();
        kv.second.add.clear();
        kv.second.noDepth.clear();
    }
    vmAlphaVerts_.clear();
    vmAddVerts_.clear();

    for (int i = 0; i < nq; i++) {
        const float *q = f + OFF_QUADS + i * QUAD_STRIDE;
        int mode = (int)q[16];
        uint32_t qflags = (uint32_t)q[17];
        int texId = (int)q[18];
        float rx[3], ux[3];
        if (mode == 3) { // 武器层四边形在 vm 空间，坐标轴固定
            rx[0] = 1; rx[1] = 0; rx[2] = 0;
            ux[0] = 0; ux[1] = 1; ux[2] = 0;
        } else if (mode == 1) { // 沿法线贴片（弹孔/血迹贴花）
            float dir[3] = {q[3], q[4], q[5]};
            float dl = sqrtf(dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2]);
            if (dl < 1e-6f) { dir[0] = 0; dir[1] = 1; dir[2] = 0; dl = 1; }
            dir[0] /= dl; dir[1] /= dl; dir[2] /= dl;
            float ref[3] = {0, 1, 0};
            if (fabsf(dir[1]) > 0.9f) {
                ref[0] = 1; ref[1] = 0; ref[2] = 0;
            }
            float t0 = ref[1] * dir[2] - ref[2] * dir[1];
            float t1 = ref[2] * dir[0] - ref[0] * dir[2];
            float t2 = ref[0] * dir[1] - ref[1] * dir[0];
            float tl = sqrtf(t0 * t0 + t1 * t1 + t2 * t2);
            if (tl < 1e-6f) { t0 = 1; t1 = 0; t2 = 0; tl = 1; }
            t0 /= tl; t1 /= tl; t2 /= tl;
            rx[0] = t0; rx[1] = t1; rx[2] = t2;
            ux[0] = dir[1] * t2 - dir[2] * t1;
            ux[1] = dir[2] * t0 - dir[0] * t2;
            ux[2] = dir[0] * t1 - dir[1] * t0;
        } else if (mode == 2) { // 直立、绕 Y 朝向相机（名牌）
            float rr[3] = {camR[0], 0, camR[2]};
            float rrl = sqrtf(rr[0] * rr[0] + rr[2] * rr[2]);
            if (rrl < 1e-6f) { rr[0] = 1; rr[2] = 0; rrl = 1; }
            rx[0] = rr[0] / rrl; rx[1] = 0; rx[2] = rr[2] / rrl;
            ux[0] = 0; ux[1] = 1; ux[2] = 0;
        } else if (mode == 4) { // 沿方向条带（曳光）
            float dir[3] = {q[3], q[4], q[5]};
            float dl = sqrtf(dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2]);
            if (dl < 1e-6f) { dir[0] = 0; dir[1] = 0; dir[2] = -1; dl = 1; }
            dir[0] /= dl; dir[1] /= dl; dir[2] /= dl;
            float toCam[3] = {camPos[0] - q[0], camPos[1] - q[1], camPos[2] - q[2]};
            float u0 = toCam[1] * dir[2] - toCam[2] * dir[1];
            float u1 = toCam[2] * dir[0] - toCam[0] * dir[2];
            float u2 = toCam[0] * dir[1] - toCam[1] * dir[0];
            float ul2 = sqrtf(u0 * u0 + u1 * u1 + u2 * u2);
            if (ul2 < 1e-6f) { u0 = camU[0]; u1 = camU[1]; u2 = camU[2]; ul2 = 1; }
            u0 /= ul2; u1 /= ul2; u2 /= ul2;
            ux[0] = u0; ux[1] = u1; ux[2] = u2;
            rx[0] = dir[0]; rx[1] = dir[1]; rx[2] = dir[2];
        } else { // mode 0：相机朝向公告板
            rx[0] = camR[0]; rx[1] = camR[1]; rx[2] = camR[2];
            ux[0] = camU[0]; ux[1] = camU[1]; ux[2] = camU[2];
        }
        if (mode == 3) {
            std::vector<float> &target = (qflags & 1) ? vmAddVerts_ : vmAlphaVerts_;
            PushQuad(target, rx, ux, q, q[6] * 0.5f, q[7] * 0.5f, q[8], q[9], q[10], q[11],
                     q[12], q[13], q[14], q[15]);
            continue;
        }
        QuadBucket &bucket = quadBuckets_[texId];
        if (bucket.alpha.capacity() == 0) {
            bucket.alpha.reserve(120 * 54);
            bucket.add.reserve(400 * 54);
            bucket.noDepth.reserve(32 * 54);
        }
        std::vector<float> *target;
        if (qflags & 2) {
            target = &bucket.noDepth;
        } else {
            target = (qflags & 1) ? &bucket.add : &bucket.alpha;
        }
        PushQuad(*target, rx, ux, q, q[6] * 0.5f, q[7] * 0.5f, q[8], q[9], q[10], q[11],
                 q[12], q[13], q[14], q[15]);
    }

    // 粒子展开为相机朝向四边形
    for (int i = 0; i < np; i++) {
        const float *p = f + OFF_PARTS + i * PART_STRIDE;
        float h = p[3] * 0.5f;
        // 粒子纹理约定：偶数 id 为加色（发光），奇数 id 为普通混合（烟雾）
        QuadBucket &bucket = quadBuckets_[(int)p[8]];
        if (bucket.alpha.capacity() == 0) {
            bucket.alpha.reserve(120 * 54);
            bucket.add.reserve(400 * 54);
            bucket.noDepth.reserve(32 * 54);
        }
        std::vector<float> &target = ((int)p[8] % 2 == 0) ? bucket.add : bucket.alpha;
        PushQuad(target, camR, camU, p, h, h, p[4], p[5], p[6], p[7], 0, 0, 1, 1);
    }

    if (quadBuckets_.empty()) {
        return;
    }
    glUseProgram(progQuad_);
    glUniformMatrix4fv(qdUVP_, 1, GL_FALSE, f + OFF_WORLDVP);
    glUniform1i(qdUTex_, 0);
    glActiveTexture(GL_TEXTURE0);
    glBindVertexArray(quadVao_);
    glBindBuffer(GL_ARRAY_BUFFER, quadVbo_);
    glDepthMask(GL_FALSE);
    glDisable(GL_CULL_FACE);

    auto drawVerts = [&](std::vector<float> &verts, bool additive, bool depthTest) {
        if (verts.empty()) {
            return;
        }
        if (depthTest) {
            glEnable(GL_DEPTH_TEST);
        } else {
            glDisable(GL_DEPTH_TEST);
        }
        glEnable(GL_BLEND);
        if (additive) {
            glBlendFunc(GL_SRC_ALPHA, GL_ONE);
        } else {
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        }
        glBufferSubData(GL_ARRAY_BUFFER, 0, verts.size() * sizeof(float), verts.data());
        glDrawArrays(GL_TRIANGLES, 0, (GLsizei)(verts.size() / 9));
        verts.clear();
    };
    // 普通混合（贴花、烟雾），再画加色（曳光、火花），最后关深度测试的（名牌）
    bool any = false;
    for (auto &kv : quadBuckets_) {
        if (kv.second.alpha.empty()) {
            continue;
        }
        auto t = textures_.find(kv.first);
        glBindTexture(GL_TEXTURE_2D, t != textures_.end() ? t->second : 0);
        drawVerts(kv.second.alpha, false, true);
        any = true;
    }
    for (auto &kv : quadBuckets_) {
        if (kv.second.add.empty()) {
            continue;
        }
        auto t = textures_.find(kv.first);
        glBindTexture(GL_TEXTURE_2D, t != textures_.end() ? t->second : 0);
        drawVerts(kv.second.add, true, true);
        any = true;
    }
    for (auto &kv : quadBuckets_) {
        if (kv.second.noDepth.empty()) {
            continue;
        }
        auto t = textures_.find(kv.first);
        glBindTexture(GL_TEXTURE_2D, t != textures_.end() ? t->second : 0);
        drawVerts(kv.second.noDepth, false, false);
        any = true;
    }

    if (any) {
        glBindVertexArray(0);
        glDisable(GL_BLEND);
        glDepthMask(GL_TRUE);
        glEnable(GL_DEPTH_TEST);
        glDisable(GL_CULL_FACE) /* 双面渲染：规避程序化几何绕向差异 */;
    } else {
        glBindVertexArray(0);
        glDepthMask(GL_TRUE);
        glEnable(GL_DEPTH_TEST);
        glDisable(GL_CULL_FACE) /* 双面渲染：规避程序化几何绕向差异 */;
    }
}

void Renderer::DrawVM(const float *f)
{
    if (f[OFF_VMACTIVE] < 0.5f) {
        return;
    }
    int meshId = (int)f[OFF_VMMESH];
    if (!progStatic_ || meshId <= 0) {
        return;
    }
    auto mit = meshes_.find(meshId);
    if (mit == meshes_.end()) {
        return;
    }
    Mesh &m = mit->second;
    glUseProgram(progStatic_);
    glUniformMatrix4fv(stUVP_, 1, GL_FALSE, f + OFF_VMVP);
    glUniformMatrix4fv(stUModel_, 1, GL_FALSE, f + OFF_VMMODEL);
    glUniform1i(stUTex_, 0);
    glUniform3f(stUSunDir_, 0.4f, 0.8f, 0.45f);
    glUniform3f(stUSunCol_, 2.2f, 2.1f, 2.0f);
    glUniform3f(stUHemiSky_, 0.55f, 0.6f, 0.66f);
    glUniform3f(stUHemiGnd_, 0.22f, 0.22f, 0.24f);
    glUniform3f(stUFogCol_, 0, 0, 0);
    glUniform3f(stUCamPos_, 0, 0, 0);
    glUniform1f(stUFogDen_, 0.0f);
    glUniform1f(stUAlphaTest_, (m.flags & 1) ? 1.0f : 0.0f);
    glUniform3fv(stUColor_, 1, m.color);
    glUniform3fv(stURME_, 1, m.rme);
    glActiveTexture(GL_TEXTURE0);
    auto tit = textures_.find(m.texId);
    glBindTexture(GL_TEXTURE_2D, tit != textures_.end() ? tit->second : 0);
    glDisable(GL_CULL_FACE); // 武器层双面，避免法线问题
    glBindVertexArray(m.vao);
    glDrawElements(GL_TRIANGLES, m.indexCount, GL_UNSIGNED_INT, (void *)0);
    glBindVertexArray(0);
    glDisable(GL_CULL_FACE) /* 双面渲染：规避程序化几何绕向差异 */;

    // 武器层公告板（枪口火焰）
    if (!vmAlphaVerts_.empty() || !vmAddVerts_.empty()) {
        glUseProgram(progQuad_);
        glUniformMatrix4fv(qdUVP_, 1, GL_FALSE, f + OFF_VMVP);
        glUniform1i(qdUTex_, 0);
        glBindVertexArray(quadVao_);
        glBindBuffer(GL_ARRAY_BUFFER, quadVbo_);
        glDepthMask(GL_FALSE);
        glDisable(GL_CULL_FACE);
        glEnable(GL_BLEND);
        glDisable(GL_DEPTH_TEST);
        if (!vmAlphaVerts_.empty()) {
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            glBufferSubData(GL_ARRAY_BUFFER, 0, vmAlphaVerts_.size() * sizeof(float), vmAlphaVerts_.data());
            glDrawArrays(GL_TRIANGLES, 0, (GLsizei)(vmAlphaVerts_.size() / 9));
        }
        if (!vmAddVerts_.empty()) {
            glBlendFunc(GL_SRC_ALPHA, GL_ONE);
            glBufferSubData(GL_ARRAY_BUFFER, 0, vmAddVerts_.size() * sizeof(float), vmAddVerts_.data());
            glDrawArrays(GL_TRIANGLES, 0, (GLsizei)(vmAddVerts_.size() / 9));
        }
        glDisable(GL_BLEND);
        glEnable(GL_DEPTH_TEST);
        glDepthMask(GL_TRUE);
        glDisable(GL_CULL_FACE) /* 双面渲染：规避程序化几何绕向差异 */;
        glBindVertexArray(0);
    }
}

void Renderer::RenderFrame(const float *f)
{
    if (!ready_ || surface_ == EGL_NO_SURFACE) {
        return;
    }
    glViewport(0, 0, width_, height_);
    if (f[OFF_FLAGS] < 0.5f) {
        glDisable(GL_BLEND);
        glClearColor(0.04f, 0.06f, 0.09f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        eglSwapBuffers(display_, surface_);
        return;
    }
    glDisable(GL_BLEND);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    glDepthMask(GL_TRUE);
    glDisable(GL_CULL_FACE) /* 双面渲染：规避程序化几何绕向差异 */;
    glCullFace(GL_BACK);
    glFrontFace(GL_CCW);
    glClearColor(f[OFF_FOGCOL], f[OFF_FOGCOL + 1], f[OFF_FOGCOL + 2], 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    DrawSky(f);
    DrawStaticMeshes(f);
    DrawSoldiers(f);
    DrawDynMeshes(f);
    if (f[OFF_OCEAN] > 0.5f) {
        DrawOcean(f);
    }
    DrawQuads(f);

    // 第一人称武器层：清空深度后重画
    if (f[OFF_VMACTIVE] > 0.5f) {
        glClear(GL_DEPTH_BUFFER_BIT);
        DrawVM(f);
    }
    eglSwapBuffers(display_, surface_);
}
