# Pelican Bike GLES3 Scene Module

This directory documents the self-contained C++17/GLES3 scene implementation in:

`D:\workspace\My\harmony\harmony-PelicanBike\native-staging\scene`

The module is an integrable approximation of the source `sky.js`, `ocean.js`, `world.js`, `bicycle.js`, `pelican.js`, `fish.js`, `effects.js`, `textures.js`, and `util.js`. It does not own a native window, `EGLDisplay`, `EGLContext`, `EGLSurface`, buffer swap, VSync callback, or render thread.

## Integration contract

The outer application is expected to use `OH_NativeVSync_Create_ForAssociatedWindow` (or another platform scheduler) and call these methods on the thread where its EGL context is current:

```cpp
pelican::scene::RenderScene scene;
scene.initialize(surfaceWidth, surfaceHeight, pelican::scene::Quality::Medium);

// Per external VSync:
pelican::scene::RenderState state;
state.timeSeconds = monotonicSeconds;
state.deltaSeconds = deltaSeconds;
state.totalDistance = accumulatedDistance; // double
scene.update(state);
scene.render();
eglSwapBuffers(display, surface);           // outer layer owns this

// Before replacing/destroying the current EGL context:
scene.destroy();
// Make the replacement context current, then initialize again.
```

There is no internal `sleep`, busy loop, worker render thread, static/global GL object, EGL call, or implicit swap. All GL names are instance-owned RAII resources. Call `destroy()` while the old context is current; after surface/context recreation, call `initialize()` again to rebuild every resource.

`resize(width, height)` recreates post-process targets and updates projection state. `screenshotPixels()` waits for requested readback, checks GL errors, and returns top-left-origin RGBA8 pixels from the current default framebuffer.

### Camera gestures and picking

When `RenderState::useExternalCamera == false`, the built-in orbit camera is active:

- `orbitDrag(dxNorm, dyNorm)` changes yaw/pitch. Pitch is clamped to approximately ±89 degrees.
- `orbitZoom(scaleDelta)` changes distance, clamped to 1.1–28 metres.
- If `autoRotateOrbit` is enabled, auto-rotation begins after seven seconds without orbit input.
- Setting `useExternalCamera == true` returns control to `cameraPosition`/`cameraTarget`; the outer gesture layer can switch modes when a drag is not consumed by UI/orbit handling.
- `pick(nx, ny)` accepts normalized surface coordinates and returns `Bell`, `Pelican`, `Bicycle`, `Sea`, or `None`. It intentionally uses analytic ray/sphere tests and a sea-plane intersection, not a full triangle raycast.

### PEL_PERF statistics

`RenderScene::stats()` returns the current `RenderStats` snapshot: `drawCalls`, `triangles`, `textures`, `buffers`, `framebuffers`, `renderbuffers`, `programs`, `vaos`, `glErrors`, `cpuUpdateMs`, `cpuRenderMs`, and reserved `gpuRenderMs`. The scene does not write hilog; the outer layer can serialize this snapshot once per second as its `PEL_PERF` JSON. Resource totals are derived from currently owned RAII objects, so `destroy()`/surface rebuild does not accumulate counts.

## Files

| File | Purpose |
|---|---|
| `RenderScene.h/.cpp` | Public lifecycle, external-VSync render entry points, camera gestures/picking, scene orchestration, quality fallback, screenshot readback. |
| `SceneMath.h` | Replaceable minimal vector/matrix math, inverse/unproject, deterministic random/hash, color sanitization. |
| `Geometry.h/.cpp` | CPU mesh generation for ocean, looping terrain/road props, trees, rocks, lamps, lighthouse, boats, birds, bicycle, pelican and fish. |
| `Simulation.h/.cpp` | Sky palette, double-precision wave phases/heights, 7-chunk placement, character animation, particles and 16-segment Verlet scarf. |
| `GlResources.h/.cpp` | Move-only RAII `ShaderProgram`, `Mesh`, `DynamicBuffer`, `InstancedBuffer`, `Texture2D`, and `Framebuffer`. |
| `Shaders.h/.cpp` | GLSL ES 3.00 sky, five-wave ocean, lit/instanced, particles, bloom, ACES/final and direct-copy shaders. |
| `SceneGles.h` | Selects the platform GLES3 header or host mock header. |
| `CMakeLists.txt` | `PELICAN_SCENE_SOURCES`/headers for the Harmony target and an optional standalone host-test target. |
| `host/MockGles3.h` | Header-only mock GLES API for compiling and exercising lifecycle code without a Harmony sysroot. |
| `host/CoreTests.cpp` | Geometry, long-distance wave/chunk, scarf finite-guard, mock resource rebuild and screenshot tests. |

## Harmony CMake use

Include the scene list from the existing native target rather than replacing the root project configuration:

```cmake
include(${CMAKE_CURRENT_SOURCE_DIR}/path/to/native-staging/scene/CMakeLists.txt)
target_sources(your_native_target PRIVATE ${PELICAN_SCENE_SOURCES} ${PELICAN_SCENE_HEADERS})
target_include_directories(your_native_target PRIVATE ${PELICAN_SCENE_DIR})
target_compile_features(your_native_target PRIVATE cxx_std_17)
target_link_libraries(your_native_target PRIVATE GLESv3 EGL)
```

The module only includes GLES3 and the C++ standard library. EGL is listed for the outer target because the application owns context/surface setup; scene sources themselves do not call EGL.

## GL requirements and fallbacks

Baseline:

- OpenGL ES 3.0 or later; tested for ES 3.2 / GLSL ES 3.10 environments while shaders use portable `#version 300 es`.
- 32-bit element indices, VAOs, instanced drawing, floating-point shader math and `gl_VertexID` fullscreen triangle.
- Default framebuffer supplied and made current by the caller.

Post-processing behavior:

- **Low quality:** always renders directly to the default framebuffer. It allocates no scene HDR/bloom FBO and therefore remains the hard fallback path.
- **Medium/High:** attempts an offscreen scene target. `GL_EXT_color_buffer_half_float` / `GL_EXT_color_buffer_float` are checked as hints and `RGBA16F` is probed, but actual framebuffer completeness is authoritative.
- Every `Framebuffer::create` calls `glCheckFramebufferStatus`.
- If `RGBA16F` is incomplete, the scene retries with `RGBA8` and uses reduced LDR bloom strength/threshold.
- If the main offscreen target is still incomplete, post-processing is disabled and rendering falls back to the default framebuffer rather than displaying black.
- If either bloom target is incomplete, bloom alone is disabled and the main target is copied/tone-mapped.
- Shader compile/link failure returns a detailed stage/program log via `lastError()` and makes initialization fail explicitly.

## Numerical and finite-value protections

Long-running sessions are handled deliberately:

- `RenderState::totalDistance` and CPU ocean/world arithmetic use `double`; float animation/shader time is derived with `remainder` before use to avoid long-session precision loss.
- The world is exactly seven recyclable chunks of 72 metres. Chunk indices/origins remain `int64_t`/`double`; procedural terrain samples wrap only their bounded noise coordinate, and only each chunk's nearby local `float` offset is sent to the GPU.
- The GPU ocean never receives total distance as a large float. The CPU computes all five Gerstner phases in `double`, wraps each with `fmod`/remainder modulo `TAU`, then uploads five bounded floats.
- `waveHeight(absoluteX, ...)` keeps absolute X, time and wave arithmetic in `double`; boats and CPU fish placement use it.
- The 16-segment scarf clamps input `dt` to `1/30`, runs two substeps and four constraint iterations, resets if the tail or any point is non-finite, and replaces degenerate/non-finite normals with `(0,1,0)`.
- Every HDR-producing fragment shader has a per-channel `isnan`/`isinf` sanitizer and clamps radiance to `[0,48]` before bloom/final output. CPU-provided colors are sanitized to the same limit. This prevents non-finite samples from propagating as bloom black blocks.

## Approximate rendering budget

Budgets vary by quality, view and active effects; the target is a mobile-friendly approximation rather than Three.js parity.

### Typical visible draw calls

| Pass | Low | Medium | High |
|---|---:|---:|---:|
| Sky + ocean | 2 | 2 | 2 |
| 7 terrain/road/guard chunks | 21 | 21 | 21 |
| Chunk vegetation/rocks, instanced | up to 28 | up to 28 | up to 28 |
| Lamps, lighthouse, boats, birds | 20–38 | 20–38 | 20–38 |
| Bicycle/pelican/fish/scarf/effects | 12–18 | 12–18 | 12–18 |
| Post-process | 0 | 1 copy or 4 bloom/final | 1 copy or 4 bloom/final |
| **Typical total** | **55–85** | **59–89** | **59–89** |

No per-tree or per-rock draw calls are used; each asset type is instanced per recycled chunk. A future integration can reduce calls further by batching all seven chunk instance lists into one buffer per asset type.

### Geometry ranges

| Item | Approximate vertices/indices |
|---|---:|
| Ocean | Low ~5.3k / 31k; Medium ~13.7k / 80k; High ~26.5k / 157k |
| One terrain chunk | Low ~304 / 1.5k; Medium ~638 / 3.5k; High ~1.1k / 6.0k |
| Bicycle merged base | ~2–4k vertices depending on generator tessellation |
| Rider pelican parts | ~2–3k total across body/head/beak/wings |
| Trees/palms/rocks | low-poly source meshes instanced; typical visible instances 150–450 across seven chunks |
| Scarf | 32 dynamic vertices / 90 indices |
| Particles | up to 320 dynamic points; speed lines up to 96 vertices |

Recommended first-pass targets are 60 FPS at Low/Medium and 30–60 FPS at High depending on resolution/GPU. Use Low or lower the outer EGL render resolution before removing numerical safety or FBO checks.

## Differences from the web version

- Replaces Three.js materials, PMREM, shadows, browser canvas textures, DOM/audio/UI and raycaster with direct GLES3 shaders, deterministic procedural colors/textures and lightweight analytic picking.
- Sky keeps the original-style palette interpolation, sun/moon disks and glow, stars, Milky Way band, procedural clouds and night transition, but omits PMREM environment prefiltering.
- Ocean keeps five Gerstner waves, near-shore attenuation, detail normals, Fresnel sky reflection, sun/moon highlights, crest/shore foam, lamp streaks and distance fog. There is no planar reflection/refraction texture.
- World keeps seven 72 m looping chunks, non-uniform shore/mountain terrain, road/guardrail, lamps, round trees, pines, palms, rocks, lighthouse, sailboats and bird groups. Prop geometry and vegetation placement are reduced for mobile budgets.
- Bicycle, rider pelican and fish are generated low-poly meshes with separate animated transforms for wheel/crank/steering-facing parts, rider body/head/beak/wings/legs and fish. Fine details such as every chain link, feather panel, woven strand, decal text and full IK skinning are approximated.
- Effects retain point particles, speed lines and the required 16-segment Verlet scarf; confetti/fireflies are represented by the common particle path rather than separate Three.js material systems.
- High/Medium post-processing uses one downsample level and separable bloom before ACES, vignette, grain and chromatic aberration. It is intentionally smaller than a desktop composer chain and has explicit half-float/LDR/direct fallbacks.

## Host validation

Without Harmony headers, configure the local mock build:

```sh
cmake -S native-staging/scene -B native-staging/scene/host/build \
  -DPELICAN_SCENE_BUILD_HOST_TESTS=ON
cmake --build native-staging/scene/host/build
native-staging/scene/host/build/pelican_scene_core_tests
```

The tests compile all scene sources with `PELICAN_SCENE_MOCK_GLES`, validate `1e12` distance wave phase wrapping/wave heights, palette/day-night continuity, seven unique 72 m chunks, index-valid finite geometry and triangle budgets, a ten-minute fixed-step scarf run plus injected-NaN reset/normal fallback, fixed particle capacity, finite character animation, stable dynamic scratch capacities, orbit clamps/pick math, stats, and complete initialize/update/render/destroy/reinitialize resource accounting.

Validation completed for this delivery:

- Fresh host CMake/Ninja/Clang build: passed.
- `pelican_scene_core_tests`: passed.
- All 14 extracted GLSL ES 3.00 stages validated with `glslangValidator`: passed.
- Harmony SDK Clang (`--target=aarch64-linux-ohos`, SDK 23 sysroot) syntax-check of all scene `.cpp` files: passed with `-Wall -Wextra -Wpedantic`.
