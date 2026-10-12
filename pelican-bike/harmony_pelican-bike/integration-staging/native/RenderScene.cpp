#include "RenderScene.h"

#include "Shaders.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstring>
#include <sstream>
#include <string>
#include <utility>

namespace pelican::scene {
namespace {

constexpr float kFogDensity = 0.0042f;

float solarElevation(float hour) {
    const float dayT = (hour - 6.0f) / 12.0f;
    float nightT = std::fmod(hour - 18.0f + 24.0f, 24.0f) / 12.0f;
    if (nightT < 0.0f) nightT += 2.0f;
    const float elevation = hour >= 6.0f && hour <= 18.0f
        ? std::sin(dayT * kPi) * radians(66.0f)
        : -std::sin(nightT * kPi) * 0.9f;
    return degrees(elevation);
}

bool extensionAvailable(const char* extensionName) {
    GLint count = 0;
    glGetIntegerv(GL_NUM_EXTENSIONS, &count);
    for (GLint i = 0; i < count; ++i) {
        const char* extension = reinterpret_cast<const char*>(glGetStringi(GL_EXTENSIONS, static_cast<GLuint>(i)));
        if (extension && std::strcmp(extension, extensionName) == 0) {
            return true;
        }
    }
    return false;
}

CpuMesh makeSkyCube() {
    return makeBox({2.0f, 2.0f, 2.0f}, {1, 1, 1});
}

CpuMesh makeRoadChunk() {
    CpuMesh road = makePlane(static_cast<float>(kWorldChunkLength), 5.64f, 6, 1, {1, 1, 1});
    for (Vertex& vertex : road.vertices) {
        vertex.position.x += static_cast<float>(kWorldChunkLength) * 0.5f;
        vertex.position.y = 0.005f;
        vertex.uv.x *= 3.0f;
    }
    return road;
}

void fillParticleCpuMesh(const ParticleSystem& system, CpuMesh& mesh) {
    mesh.clear();
    mesh.vertices.reserve(system.particles().size());
    mesh.indices.reserve(system.particles().size());
    for (const Particle& particle : system.particles()) {
        if (particle.life <= 0.0f || !particle.position.finite()) continue;
        const float life = saturate(particle.life / std::max(particle.maxLife, 1.0e-4f));
        const float alpha = saturate(life * 1.6f) * saturate((1.0f - life) * 8.0f);
        const uint32_t index = static_cast<uint32_t>(mesh.vertices.size());
        mesh.vertices.push_back({particle.position, {0, 1, 0}, sanitizeColor(particle.color, 48.0f),
                                 {std::max(particle.size, 0.001f), alpha}});
        mesh.indices.push_back(index);
    }
}

void fillSpeedLinesCpu(float time, float speed, float intensity, CpuMesh& mesh) {
    mesh.clear();
    mesh.vertices.reserve(96);
    mesh.indices.reserve(96);
    const float strength = saturate((speed - 9.0f) / 5.0f) * intensity;
    if (strength <= 0.01f) return;
    constexpr int count = 48;
    mesh.vertices.reserve(count * 2);
    mesh.indices.reserve(count * 2);
    const float length = 0.4f + speed * 0.08f;
    for (int i = 0; i < count; ++i) {
        const float angle = hash01(static_cast<uint32_t>(i) * 11U + 3U) * kTau;
        const float radius = 0.9f + hash01(static_cast<uint32_t>(i) * 19U + 7U) * 2.4f;
        const float baseZ = -std::fmod(hash01(static_cast<uint32_t>(i) * 31U + 13U) * 14.0f +
                                           time * speed * 2.2f + static_cast<float>(i),
                                       15.0f) - 0.4f;
        const Vec3 p{std::cos(angle) * radius, std::sin(angle) * radius * 0.65f, baseZ};
        const Vec3 color{strength * 2.0f, strength * 2.0f, strength * 2.0f};
        const uint32_t base = static_cast<uint32_t>(mesh.vertices.size());
        mesh.vertices.push_back({p, {0, 1, 0}, color, {1, strength * 0.35f}});
        mesh.vertices.push_back({p + Vec3{0, 0, -length}, {0, 1, 0}, color, {1, 0}});
        mesh.indices.insert(mesh.indices.end(), {base, base + 1});
    }
}

}  // namespace

RenderScene::RenderScene() : scarf_(0.075f, 0.045f), particles_(320) {}
RenderScene::~RenderScene() { destroy(); }

void RenderScene::fail(const std::string& message) {
    lastError_ = message;
}

bool RenderScene::initialize(int width, int height, Quality quality) {
    // This function assumes a current GLES context. It owns no EGL/surface/VSync state.
    destroy();
    width_ = std::max(width, 1);
    height_ = std::max(height, 1);
    quality_ = quality;
    lastError_.clear();
    stats_ = {};

    if (!createPrograms()) {
        destroy();
        return false;
    }
    if (!createMeshes()) {
        fail(lastError_.empty() ? "failed to create scene meshes" : lastError_);
        destroy();
        return false;
    }
    if (!createTextures()) {
        fail(lastError_.empty() ? "failed to create scene textures" : lastError_);
        destroy();
        return false;
    }
    glGenVertexArrays(1, &fullscreenVao_);
    if (!fullscreenVao_ || glGetError() != GL_NO_ERROR) {
        fail("fullscreen VAO creation failed");
        destroy();
        return false;
    }
    // Low tier always renders directly to the caller's default framebuffer.
    postProcessEnabled_ = quality_ != Quality::Low && createFramebuffers();
    if (quality_ != Quality::Low && !postProcessEnabled_) {
        // FBO failure is a capability downgrade, not a fatal scene failure.
        hdrFramebuffer_.destroy();
        bloomA_.destroy();
        bloomB_.destroy();
        bloomEnabled_ = false;
        hdrHalfFloat_ = false;
    }

    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    glFrontFace(GL_CCW);
    initialized_ = true;
    update(state_);
    return true;
}

void RenderScene::resize(int width, int height) {
    width_ = std::max(width, 1);
    height_ = std::max(height, 1);
    projection_ = Mat4::perspective(radians(state_.cameraFovDegrees), static_cast<float>(width_) / height_, 0.05f, 700.0f);
    if (initialized_ && quality_ != Quality::Low) {
        hdrFramebuffer_.destroy();
        bloomA_.destroy();
        bloomB_.destroy();
        postProcessEnabled_ = createFramebuffers();
        if (!postProcessEnabled_) {
            bloomEnabled_ = false;
            hdrHalfFloat_ = false;
        }
    }
}

bool RenderScene::createPrograms() {
    struct ProgramSource {
        ShaderProgram* program;
        const char* name;
        const char* vertex;
        const char* fragment;
    };
    const std::array<ProgramSource, 9> sources = {{
        {&skyProgram_, "sky", shaders::kSkyVertex, shaders::kSkyFragment},
        {&litProgram_, "lit", shaders::kLitVertex, shaders::kLitFragment},
        {&instancedProgram_, "instanced", shaders::kInstancedVertex, shaders::kLitFragment},
        {&oceanProgram_, "ocean", shaders::kOceanVertex, shaders::kOceanFragment},
        {&particleProgram_, "particle", shaders::kParticleVertex, shaders::kParticleFragment},
        {&bloomDownProgram_, "bloom downsample", shaders::kFullscreenVertex, shaders::kBloomDownFragment},
        {&bloomBlurProgram_, "bloom blur", shaders::kFullscreenVertex, shaders::kBloomBlurFragment},
        {&finalProgram_, "final", shaders::kFullscreenVertex, shaders::kFinalFragment},
        {&copyProgram_, "copy", shaders::kFullscreenVertex, shaders::kCopyFragment},
    }};
    for (const ProgramSource& source : sources) {
        std::string log;
        if (!source.program->create(source.vertex, source.fragment, &log)) {
            fail(std::string("shader program '") + source.name + "' failed: " + log);
            return false;
        }
    }
    return true;
}

bool RenderScene::createMeshes() {
    auto createStatic = [this](Mesh& target, CpuMesh mesh, const char* name) {
        if (!target.create(mesh)) {
            fail(std::string("mesh upload failed: ") + name);
            return false;
        }
        return true;
    };
    if (!createStatic(skyMesh_, makeSkyCube(), "sky")) return false;
    if (!createStatic(oceanMesh_, makeOceanGrid(static_cast<int>(quality_)), "ocean")) return false;
    if (!createStatic(roadMesh_, makeRoadChunk(), "road")) return false;
    if (!createStatic(guardrailMesh_, makeGuardrailChunk(), "guardrail")) return false;
    if (!createStatic(treeMesh_, makeTreeMesh(), "tree")) return false;
    if (!createStatic(pineMesh_, makePineMesh(), "pine")) return false;
    if (!createStatic(palmMesh_, makePalmMesh(), "palm")) return false;
    if (!createStatic(rockMesh_, makeRockMesh(), "rock")) return false;
    if (!createStatic(lampMesh_, makeLampMesh(), "lamp")) return false;
    if (!createStatic(lighthouseMesh_, makeLighthouseMesh(), "lighthouse")) return false;
    if (!createStatic(boatMesh_, makeBoatMesh(), "boat")) return false;
    if (!createStatic(birdBodyMesh_, makeBirdBodyMesh(false), "gull body")) return false;
    if (!createStatic(birdWingMesh_, makeBirdWingMesh(false), "gull wing")) return false;
    if (!createStatic(flockPelicanBodyMesh_, makeBirdBodyMesh(true), "flock pelican body")) return false;
    if (!createStatic(flockPelicanWingMesh_, makeBirdWingMesh(true), "flock pelican wing")) return false;
    if (!createStatic(bicycleMesh_, makeBicycleMesh(), "bicycle")) return false;
    if (!createStatic(pelicanBodyMesh_, makePelicanBodyMesh(), "pelican body")) return false;
    if (!createStatic(pelicanHeadMesh_, makePelicanHeadMesh(), "pelican head")) return false;
    if (!createStatic(pelicanBeakMesh_, makePelicanBeakMesh(), "pelican beak")) return false;
    if (!createStatic(pelicanWingMesh_, makePelicanWingMesh(), "pelican wing")) return false;
    if (!createStatic(fishMesh_, makeFishMesh(), "fish")) return false;

    scarf_.reset({0.0f, 1.45f, -0.0375f}, {0.0f, 1.45f, 0.0375f});
    scratchScarf_.vertices.reserve(ScarfSimulation::kPointCount);
    scratchScarf_.indices.reserve((ScarfSimulation::kSegments - 1) * 6);
    scratchParticles_.vertices.reserve(320);
    scratchParticles_.indices.reserve(320);
    scratchSpeedLines_.vertices.reserve(96);
    scratchSpeedLines_.indices.reserve(96);
    scarf_.fillMesh(scratchScarf_);
    if (!scarfMesh_.create(scratchScarf_, true, ScarfSimulation::kPointCount, (ScarfSimulation::kSegments - 1) * 6)) {
        fail("dynamic scarf mesh upload failed");
        return false;
    }
    CpuMesh emptyParticles;
    if (!particleMesh_.create(emptyParticles, true, 320, 320)) {
        fail("dynamic particle mesh upload failed");
        return false;
    }
    CpuMesh lines;
    if (!speedLineMesh_.create(lines, true, 96, 96)) {
        fail("dynamic speed-line mesh upload failed");
        return false;
    }

    for (ChunkGpu& chunk : chunks_) {
        const CpuMesh terrain = makeTerrainChunk(static_cast<int>(quality_));
        if (!chunk.terrain.create(terrain, true, terrain.vertices.size(), terrain.indices.size())) {
            fail("dynamic terrain chunk upload failed");
            return false;
        }
        const size_t treeCapacity = quality_ == Quality::Low ? 12 : (quality_ == Quality::Medium ? 24 : 36);
        const size_t pineCapacity = quality_ == Quality::Low ? 10 : (quality_ == Quality::Medium ? 18 : 26);
        if (!chunk.roundTrees.create(treeMesh_, treeCapacity) || !chunk.pines.create(pineMesh_, pineCapacity) ||
            !chunk.palms.create(palmMesh_, 6) || !chunk.rocks.create(rockMesh_, 10)) {
            fail("instanced world buffer creation failed");
            return false;
        }
    }
    return true;
}

bool RenderScene::createTextures() {
    const std::vector<uint8_t> noise = makeNoiseTextureRgba(64, 64, 7);
    if (!noiseTexture_.create(64, 64, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, noise.data(), true, true)) {
        fail("noise texture creation failed");
        return false;
    }
    const std::vector<uint8_t> road = makeRoadTextureRgba(512, 128, 42);
    if (!roadTexture_.create(512, 128, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, road.data(), true, true)) {
        fail("road texture creation failed");
        return false;
    }
    return true;
}

bool RenderScene::createFramebuffers() {
    hdrFramebuffer_.destroy();
    bloomA_.destroy();
    bloomB_.destroy();
    bloomEnabled_ = false;
    hdrHalfFloat_ = false;
    if (quality_ == Quality::Low) return false;

    const bool halfFloatAdvertised = extensionAvailable("GL_EXT_color_buffer_half_float") ||
                                     extensionAvailable("GL_EXT_color_buffer_float");
    // Completeness is authoritative. Probe even when the extension string is absent because emulator/driver
    // reports vary; the advertised flag is still evaluated as a capability hint for diagnostics/integration.
    const bool shouldProbeHalfFloat = halfFloatAdvertised || quality_ != Quality::Low;
    if (shouldProbeHalfFloat && hdrFramebuffer_.create(width_, height_, GL_RGBA16F, GL_RGBA, GL_HALF_FLOAT, true)) {
        hdrHalfFloat_ = true;
    } else {
        hdrFramebuffer_.destroy();
        if (!hdrFramebuffer_.create(width_, height_, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, true)) {
            return false;
        }
    }

    const int divisor = quality_ == Quality::High ? 2 : 4;
    const int bloomWidth = std::max(width_ / divisor, 1);
    const int bloomHeight = std::max(height_ / divisor, 1);
    const GLenum internal = hdrHalfFloat_ ? GL_RGBA16F : GL_RGBA8;
    const GLenum type = hdrHalfFloat_ ? GL_HALF_FLOAT : GL_UNSIGNED_BYTE;
    if (bloomA_.create(bloomWidth, bloomHeight, internal, GL_RGBA, type, false) &&
        bloomB_.create(bloomWidth, bloomHeight, internal, GL_RGBA, type, false)) {
        bloomEnabled_ = true;
    } else {
        bloomA_.destroy();
        bloomB_.destroy();
        bloomEnabled_ = false;
    }
    return true;
}

void RenderScene::update(const RenderState& state) {
    const auto cpuStart = std::chrono::steady_clock::now();
    state_ = state;
    if (!std::isfinite(state_.totalDistance)) state_.totalDistance = 0.0;
    if (!std::isfinite(state_.timeSeconds)) state_.timeSeconds = 0.0;
    state_.deltaSeconds = clamp(state_.deltaSeconds, 0.0f, 0.1f);
    state_.hour = std::fmod(state_.hour, 24.0f);
    if (state_.hour < 0.0f) state_.hour += 24.0f;
    state_.cloudCover = saturate(state_.cloudCover);
    state_.waveAmplitude = clamp(state_.waveAmplitude, 0.0f, 2.0f);
    state_.fogMultiplier = clamp(state_.fogMultiplier, 0.0f, 3.0f);
    state_.exposureMultiplier = clamp(state_.exposureMultiplier, 0.4f, 2.0f);
    state_.bloomBoost = clamp(state_.bloomBoost, 0.0f, 3.0f);
    state_.cameraFovDegrees = clamp(state_.cameraFovDegrees, 35.0f, 100.0f);
    localTime_ = static_cast<float>(std::remainder(state_.timeSeconds, 10000.0));

    solarElevationDegrees_ = solarElevation(state_.hour);
    palette_ = sampleSkyPalette(solarElevationDegrees_);
    sunDir_ = sunDirection(state_.hour);
    moonDir_ = moonDirection(state_.hour);
    night_ = nightFactor(solarElevationDegrees_);
    if (!state_.useExternalCamera) {
        if (state_.autoRotateOrbit && state_.timeSeconds - lastOrbitInputTime_ > 7.0) {
            orbitYaw_ = std::fmod(orbitYaw_ + state_.deltaSeconds * 0.08f, kTau);
        }
        orbitPitch_ = clamp(orbitPitch_, radians(-89.0f), radians(89.0f));
        orbitDistance_ = clamp(orbitDistance_, 1.1f, 28.0f);
        activeCameraTarget_ = {0.4f, 0.85f, 0.0f};
        const float cp = std::cos(orbitPitch_);
        activeCameraPosition_ = activeCameraTarget_ + Vec3{
            std::cos(orbitYaw_) * cp * orbitDistance_,
            std::sin(orbitPitch_) * orbitDistance_,
            std::sin(orbitYaw_) * cp * orbitDistance_,
        };
    } else {
        activeCameraPosition_ = state_.cameraPosition;
        activeCameraTarget_ = state_.cameraTarget;
    }
    view_ = Mat4::lookAt(activeCameraPosition_, activeCameraTarget_, {0, 1, 0});
    projection_ = Mat4::perspective(radians(state_.cameraFovDegrees), static_cast<float>(width_) / height_, 0.05f, 700.0f);
    wavePhases_ = computeWavePhases(state_.totalDistance, state_.timeSeconds);
    chunkPlacements_ = computeChunkPlacements(state_.totalDistance);

    AnimationInputs animation;
    animation.time = localTime_;
    animation.deltaTime = state_.deltaSeconds;
    animation.speed = state_.speedMetersPerSecond;
    animation.steering = state_.steering;
    animation.pedal = state_.pedal;
    animation.airborne = state_.airborne;
    animation.trick = state_.trick;
    animation.mouthOpen = state_.mouthOpen;
    animation.waveAmplitude = state_.waveAmplitude;
    animator_.update(animation);

    for (size_t slot = 0; slot < chunks_.size(); ++slot) {
        if (chunks_[slot].index != chunkPlacements_[slot].index) {
            updateChunk(chunks_[slot], chunkPlacements_[slot].index);
        }
    }

    const AnimatedNodes& nodes = animator_.nodes();
    const Vec3 knotCenter = transformPoint(nodes.pelicanBody, {0.23f, 0.12f, 0});
    const Vec3 rootA = knotCenter + Vec3{-0.015f, 0.02f, -0.0375f};
    const Vec3 rootB = knotCenter + Vec3{-0.015f, 0.02f, 0.0375f};
    const Vec3 wind{-state_.speedMetersPerSecond * 0.85f, 0.15f, std::sin(localTime_ * 0.4f) * 0.8f};
    const ScarfCollider collider{transformPoint(nodes.pelicanBody, {0, 0, 0}), 0.28f};
    if (state_.scarf) {
        scarf_.update(state_.deltaSeconds, rootA, rootB, wind, localTime_, &collider);
    }

    const float localScroll = state_.speedMetersPerSecond * state_.deltaSeconds;
    if (state_.speedMetersPerSecond > 4.0f && effectsRandom_.next() < state_.deltaSeconds * 18.0f) {
        Particle particle;
        particle.position = {-0.45f, 0.04f, effectsRandom_.range(-0.22f, 0.22f)};
        particle.velocity = {-state_.speedMetersPerSecond * 0.25f, effectsRandom_.range(0.35f, 1.0f), effectsRandom_.range(-0.45f, 0.45f)};
        particle.color = night_ > 0.5f ? Vec3{0.3f, 0.55f, 1.4f} : Vec3{0.55f, 0.46f, 0.34f};
        particle.size = effectsRandom_.range(0.035f, 0.08f);
        particle.life = particle.maxLife = effectsRandom_.range(0.35f, 0.9f);
        particle.drag = 1.2f;
        particle.gravity = 1.5f;
        particles_.emit(particle);
    }
    particles_.update(state_.deltaSeconds, localScroll);
    updateDynamicMeshes();
    stats_.cpuUpdateMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - cpuStart).count();
    drainGlErrors();
}

void RenderScene::updateChunk(ChunkGpu& chunk, int64_t index) {
    chunk.index = index;
    CpuMesh terrain = makeTerrainChunk(static_cast<int>(quality_));
    fillTerrainChunk(terrain, static_cast<double>(index) * kWorldChunkLength);
    chunk.terrain.update(terrain);
    chunk.roundTrees.update(buildTreeInstances(index, static_cast<int>(quality_), false, false));
    chunk.pines.update(buildTreeInstances(index, static_cast<int>(quality_), false, true));
    chunk.palms.update(buildTreeInstances(index, static_cast<int>(quality_), true, false));
    chunk.rocks.update(buildRockInstances(index, static_cast<int>(quality_)));
}

void RenderScene::updateDynamicMeshes() {
    if (state_.scarf) {
        scarf_.fillMesh(scratchScarf_);
        scarfMesh_.update(scratchScarf_);
    }
    fillParticleCpuMesh(particles_, scratchParticles_);
    particleMesh_.update(scratchParticles_);
    fillSpeedLinesCpu(localTime_, state_.speedMetersPerSecond,
                      state_.enableSpeedLines ? 1.0f : 0.0f, scratchSpeedLines_);
    speedLineMesh_.update(scratchSpeedLines_);
}

void RenderScene::setExternalCharacterRenderer(ExternalCharacterRenderer renderer) {
    externalCharacterRenderer_ = std::move(renderer);
}

void RenderScene::clearExternalCharacterRenderer() {
    externalCharacterRenderer_ = {};
}

void RenderScene::render() {
    if (!initialized_) return;
    const auto cpuStart = std::chrono::steady_clock::now();
    stats_.drawCalls = 0;
    stats_.triangles = 0;
    if (postProcessEnabled_) {
        hdrFramebuffer_.bind();
    } else {
        Framebuffer::bindDefault();
    }
    glViewport(0, 0, width_, height_);
    glClearColor(palette_.horizon.x, palette_.horizon.y, palette_.horizon.z, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    drawSceneGeometry();
    if (postProcessEnabled_) {
        postProcess();
    }
    stats_.cpuRenderMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - cpuStart).count();
    drainGlErrors();
}

void RenderScene::drawSceneGeometry() {
    drawSky();
    drawOcean();
    drawWorld();
    drawCharacters();
    drawEffects();
}

void RenderScene::drawSky() {
    glDisable(GL_CULL_FACE);
    glDepthMask(GL_FALSE);
    skyProgram_.use();
    skyProgram_.set("uView", view_);
    skyProgram_.set("uProjection", projection_);
    skyProgram_.set("uSunDir", sunDir_);
    skyProgram_.set("uMoonDir", moonDir_);
    skyProgram_.set("uZenith", sanitizeColor(palette_.zenith, 48.0f));
    skyProgram_.set("uHorizon", sanitizeColor(palette_.horizon, 48.0f));
    skyProgram_.set("uGround", sanitizeColor(palette_.ground, 48.0f));
    skyProgram_.set("uSunColor", sanitizeColor(palette_.sunColor, 48.0f));
    skyProgram_.set("uCloudTint", sanitizeColor(palette_.cloudTint, 48.0f));
    skyProgram_.set("uCloudShade", sanitizeColor(palette_.cloudShade, 48.0f));
    skyProgram_.set("uSunGlow", palette_.sunIntensity);
    skyProgram_.set("uNight", night_);
    skyProgram_.set("uTime", localTime_);
    skyProgram_.set("uCloudCover", state_.cloudCover);
    skyMesh_.draw();
    recordDraw(skyMesh_);
    glDepthMask(GL_TRUE);
    glEnable(GL_CULL_FACE);
}

void RenderScene::drawOcean() {
    oceanProgram_.use();
    oceanProgram_.set("uView", view_);
    oceanProgram_.set("uProjection", projection_);
    oceanProgram_.set("uAmplitude", state_.waveAmplitude);
    oceanProgram_.setFloatArray("uPhase", wavePhases_.data(), kWaveCount);
    oceanProgram_.set("uCamera", activeCameraPosition_);
    oceanProgram_.set("uSunDir", sunDir_);
    oceanProgram_.set("uMoonDir", moonDir_);
    oceanProgram_.set("uZenith", palette_.zenith);
    oceanProgram_.set("uHorizon", palette_.horizon);
    oceanProgram_.set("uGround", palette_.ground);
    oceanProgram_.set("uSunColor", palette_.sunColor);
    oceanProgram_.set("uFogColor", palette_.fogColor);
    oceanProgram_.set("uDeep", Vec3{0.005f, 0.12f, 0.24f});
    oceanProgram_.set("uShallow", Vec3{0.015f, 0.45f, 0.48f});
    oceanProgram_.set("uLampColor", Vec3{3.0f, 1.3f, 0.35f});
    oceanProgram_.set("uSunGlow", palette_.sunIntensity);
    oceanProgram_.set("uNight", night_);
    oceanProgram_.set("uTime", localTime_);
    oceanProgram_.set("uFogDensity", kFogDensity * state_.fogMultiplier);
    oceanProgram_.set("uDayLight", 1.0f - night_ * 0.88f);
    oceanMesh_.draw();
    recordDraw(oceanMesh_);
}

void RenderScene::setCommonLitUniforms(ShaderProgram& program, const Mat4& model, const Vec3& tint,
                                       float roughness, const Vec3& emission, float sway,
                                       const Texture2D* texture) {
    program.use();
    program.set("uModel", model);
    program.set("uView", view_);
    program.set("uProjection", projection_);
    program.set("uCamera", activeCameraPosition_);
    program.set("uSunDir", sunDir_);
    program.set("uSunColor", sanitizeColor(palette_.sunColor * std::max(palette_.sunIntensity, 0.08f), 48.0f));
    program.set("uFogColor", palette_.fogColor);
    program.set("uTint", sanitizeColor(tint, 48.0f));
    program.set("uEmission", sanitizeColor(emission, 48.0f));
    program.set("uAmbient", 0.16f + (1.0f - night_) * 0.17f);
    program.set("uRoughness", clamp(roughness, 0.0f, 1.0f));
    program.set("uFogDensity", kFogDensity * state_.fogMultiplier);
    program.set("uTime", localTime_);
    program.set("uSway", sway);
    program.set("uUseTexture", texture ? 1.0f : 0.0f);
    program.set("uTexture", 0);
    if (texture) texture->bind(0); else noiseTexture_.bind(0);
}

void RenderScene::drawLit(const Mesh& mesh, const Mat4& model, const Vec3& tint, float roughness,
                          const Vec3& emission, float sway, const Texture2D* texture) {
    setCommonLitUniforms(litProgram_, model, tint, roughness, emission, sway, texture);
    mesh.draw();
    recordDraw(mesh);
}

void RenderScene::drawInstanced(const Mesh& mesh, const InstancedBuffer& instances, const Mat4& model,
                                const Vec3& tint, float roughness, float sway) {
    if (instances.count() <= 0) return;
    setCommonLitUniforms(instancedProgram_, model, tint, roughness, {0, 0, 0}, sway, nullptr);
    instances.bind(mesh);
    mesh.drawInstanced(instances.count());
    recordDraw(mesh, instances.count());
}

void RenderScene::drawWorld() {
    for (size_t slot = 0; slot < chunks_.size(); ++slot) {
        const Mat4 chunkModel = Mat4::translation({chunkPlacements_[slot].localX, 0, 0});
        ChunkGpu& chunk = chunks_[slot];
        drawLit(chunk.terrain, chunkModel, {1, 1, 1}, 0.96f);
        drawLit(roadMesh_, chunkModel, {1, 1, 1}, 0.82f, {0, 0, 0}, 0.0f, &roadTexture_);
        drawLit(guardrailMesh_, chunkModel, {1, 1, 1}, 0.52f);
        drawInstanced(treeMesh_, chunk.roundTrees, chunkModel, {1, 1, 1}, 0.92f, 0.018f);
        drawInstanced(pineMesh_, chunk.pines, chunkModel, {1, 1, 1}, 0.94f, 0.014f);
        drawInstanced(palmMesh_, chunk.palms, chunkModel, {1, 1, 1}, 0.82f, 0.03f);
        drawInstanced(rockMesh_, chunk.rocks, chunkModel, {1, 1, 1}, 0.98f);
        for (float lampX : {12.0f, 48.0f}) {
            const Mat4 lampModel = chunkModel * Mat4::translation({lampX, 0.0f, 3.45f});
            drawLit(lampMesh_, lampModel, {1, 1, 1}, 0.38f, Vec3{3.6f, 1.65f, 0.55f} * night_);
        }
    }

    const double lighthousePeriod = 1600.0;
    const double lighthouseLocal = std::fmod(330.0 - state_.totalDistance + 420.0, lighthousePeriod);
    const float lighthouseX = static_cast<float>((lighthouseLocal < 0.0 ? lighthouseLocal + lighthousePeriod : lighthouseLocal) - 420.0);
    drawLit(lighthouseMesh_, Mat4::translation({lighthouseX, static_cast<float>(kSeaLevel - 0.5), -118.0f}),
            {1, 1, 1}, 0.72f, Vec3{5.0f, 2.8f, 0.8f} * night_);

    for (int i = 0; i < 5; ++i) {
        const double base = 60.0 + i * 170.0 + state_.timeSeconds * (0.6 + i * 0.25);
        const double period = 900.0;
        double local = std::fmod(base - state_.totalDistance + 300.0, period);
        if (local < 0.0) local += period;
        const float x = static_cast<float>(local - 300.0);
        const float z = -42.0f - i * 34.0f;
        const double absoluteX = state_.totalDistance + static_cast<double>(x);
        const float baseWave = static_cast<float>(waveHeight(absoluteX, z, state_.timeSeconds, state_.waveAmplitude));
        const float frontWave = static_cast<float>(waveHeight(absoluteX + 2.5, z, state_.timeSeconds, state_.waveAmplitude));
        const float sideWave = static_cast<float>(waveHeight(absoluteX, z + 1.2, state_.timeSeconds, state_.waveAmplitude));
        const float y = baseWave + 0.15f;
        const Vec3 rotation{-std::atan2(sideWave - baseWave, 1.2f) * 0.8f, 0,
                            std::atan2(frontWave - baseWave, 2.5f) * 0.8f};
        drawLit(boatMesh_, compose({x, y, z}, rotation, Vec3{0.72f + i * 0.08f, 0.72f + i * 0.08f, 0.72f + i * 0.08f}),
                {1, 1, 1}, 0.65f);
    }

    const float time = localTime_;
    for (int i = 0; i < 7; ++i) {
        const float angle = time * (0.12f + i * 0.013f) + i * 1.7f;
        const Vec3 position{(i - 3) * 6.0f + std::sin(angle) * (8.0f + i), 7.0f + (i % 3) * 2.2f + std::sin(angle * 2.3f),
                            -12.0f - (i % 4) * 7.0f + std::cos(angle) * (4.0f + (i % 3) * 2.0f)};
        drawBird(compose(position, {0, -angle, 0}, {1, 1, 1}), std::sin(time * (5.5f + i % 3) + i) * 0.5f, false);
    }
    const float flockX = std::fmod(time * 3.2f, 560.0f) - 260.0f;
    for (int i = 0; i < 3; ++i) {
        const float offset = i == 0 ? 0.0f : 2.6f;
        const float side = i == 1 ? -1.0f : 1.0f;
        const Vec3 position{flockX - offset, 5.5f + std::sin(time * 0.6f + i) * 0.35f, -22.0f + (i ? side * 2.4f : 0.0f)};
        drawBird(compose(position, {}, {1, 1, 1}), std::sin(time * 2.4f - i * 0.6f) * 0.38f, true);
    }
}

void RenderScene::drawBird(const Mat4& bodyModel, float flap, bool pelican, bool mirrored) {
    const Mesh& body = pelican ? flockPelicanBodyMesh_ : birdBodyMesh_;
    const Mesh& wing = pelican ? flockPelicanWingMesh_ : birdWingMesh_;
    drawLit(body, bodyModel, {1, 1, 1}, 0.8f);
    drawLit(wing, bodyModel * compose({0, 0.03f, 0.05f}, {flap, 0, 0}), {1, 1, 1}, 0.85f);
    drawLit(wing, bodyModel * compose({0, 0.03f, -0.05f}, {-flap, 0, 0}, {1, 1, -1}), {1, 1, 1}, 0.85f);
    (void)mirrored;
}

void RenderScene::drawCharacters() {
    bool externalDrawn = false;
    if (externalCharacterRenderer_) {
        ExternalCharacterContext context;
        context.view = view_;
        context.projection = projection_;
        context.cameraPosition = activeCameraPosition_;
        context.sunDirection = sunDir_;
        context.sunColor = sanitizeColor(palette_.sunColor * std::max(palette_.sunIntensity, 0.08f), 48.0f);
        context.fogColor = palette_.fogColor;
        context.ambient = 0.16f + (1.0f - night_) * 0.17f;
        context.fogDensity = kFogDensity * state_.fogMultiplier;
        context.timeSeconds = localTime_;
        externalDrawn = externalCharacterRenderer_(context);
    }
    if (!externalDrawn) {
        const AnimatedNodes& nodes = animator_.nodes();
        drawLit(bicycleMesh_, nodes.bicycle, {1, 1, 1}, 0.45f,
                Vec3{0.8f, 0.2f, 0.03f} * night_);
        drawLit(pelicanBodyMesh_, nodes.pelicanBody, {1, 1, 1}, 0.86f);
        drawLit(pelicanHeadMesh_, nodes.pelicanHead, {1, 1, 1}, 0.68f);
        drawLit(pelicanBeakMesh_, nodes.pelicanBeak, {1, 1, 1}, 0.42f);
        drawLit(pelicanWingMesh_, nodes.leftWing, {1, 1, 1}, 0.76f);
        drawLit(pelicanWingMesh_, nodes.rightWing, {1, 1, 1}, 0.76f);
        for (const Mat4& fishTransform : nodes.fish) {
            drawLit(fishMesh_, fishTransform, {1, 1, 1}, 0.32f);
        }
    }
    if (state_.scarf) {
        glDisable(GL_CULL_FACE);
        drawLit(scarfMesh_, Mat4::identity(), {1, 1, 1}, 0.78f);
        glEnable(GL_CULL_FACE);
    }
}

void RenderScene::drawEffects() {
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDepthMask(GL_FALSE);
    particleProgram_.use();
    particleProgram_.set("uView", view_);
    particleProgram_.set("uProjection", projection_);
    particleProgram_.set("uPointScale", static_cast<float>(height_) * 0.55f);
    particleMesh_.draw(GL_POINTS);
    recordDraw(particleMesh_, 1, GL_POINTS);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE);
    litProgram_.use();
    litProgram_.set("uModel", Mat4::identity());
    litProgram_.set("uView", view_);
    litProgram_.set("uProjection", projection_);
    litProgram_.set("uCamera", activeCameraPosition_);
    litProgram_.set("uSunDir", sunDir_);
    litProgram_.set("uSunColor", Vec3{1, 1, 1});
    litProgram_.set("uFogColor", palette_.fogColor);
    litProgram_.set("uTint", Vec3{1, 1, 1});
    litProgram_.set("uEmission", Vec3{1.4f, 1.4f, 1.4f});
    litProgram_.set("uAmbient", 1.0f);
    litProgram_.set("uRoughness", 1.0f);
    litProgram_.set("uFogDensity", 0.0f);
    litProgram_.set("uTime", 0.0f);
    litProgram_.set("uSway", 0.0f);
    litProgram_.set("uUseTexture", 0.0f);
    litProgram_.set("uTexture", 0);
    speedLineMesh_.draw(GL_LINES);
    recordDraw(speedLineMesh_, 1, GL_LINES);
    glDepthMask(GL_TRUE);
    glDisable(GL_BLEND);
}

void RenderScene::postProcess() {
    glDisable(GL_DEPTH_TEST);
    glDepthMask(GL_FALSE);
    glDisable(GL_CULL_FACE);
    glBindVertexArray(fullscreenVao_);
    const bool useBloom = bloomEnabled_ && state_.bloom && state_.bloomBoost > 0.001f;
    if (useBloom) {
        bloomA_.bind();
        glViewport(0, 0, bloomA_.width(), bloomA_.height());
        bloomDownProgram_.use();
        hdrFramebuffer_.color().bind(0);
        bloomDownProgram_.set("uScene", 0);
        bloomDownProgram_.set("uTexel", Vec2{1.0f / width_, 1.0f / height_});
        bloomDownProgram_.set("uThreshold", hdrHalfFloat_ ? 0.82f : 0.68f);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        ++stats_.drawCalls;
        ++stats_.triangles;

        bloomB_.bind();
        glViewport(0, 0, bloomB_.width(), bloomB_.height());
        bloomBlurProgram_.use();
        bloomA_.color().bind(0);
        bloomBlurProgram_.set("uImage", 0);
        bloomBlurProgram_.set("uDirection", Vec2{1.0f / bloomA_.width(), 0.0f});
        glDrawArrays(GL_TRIANGLES, 0, 3);
        ++stats_.drawCalls;
        ++stats_.triangles;

        bloomA_.bind();
        bloomB_.color().bind(0);
        bloomBlurProgram_.set("uDirection", Vec2{0.0f, 1.0f / bloomB_.height()});
        glDrawArrays(GL_TRIANGLES, 0, 3);
        ++stats_.drawCalls;
        ++stats_.triangles;
    }

    Framebuffer::bindDefault();
    glViewport(0, 0, width_, height_);
    if (useBloom) {
        finalProgram_.use();
        hdrFramebuffer_.color().bind(0);
        bloomA_.color().bind(1);
        noiseTexture_.bind(2);
        finalProgram_.set("uScene", 0);
        finalProgram_.set("uBloom", 1);
        finalProgram_.set("uNoise", 2);
        finalProgram_.set("uResolution", Vec2{static_cast<float>(width_), static_cast<float>(height_)});
        finalProgram_.set("uExposure", palette_.exposure * state_.exposureMultiplier);
        finalProgram_.set("uBloomStrength", palette_.bloom * state_.bloomBoost *
                                             (hdrHalfFloat_ ? 1.0f : 0.55f));
        finalProgram_.set("uTime", localTime_);
        finalProgram_.set("uAberration", quality_ == Quality::High ? 1.25f : 0.65f);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        ++stats_.drawCalls;
        ++stats_.triangles;
    } else {
        copyProgram_.use();
        hdrFramebuffer_.color().bind(0);
        copyProgram_.set("uScene", 0);
        copyProgram_.set("uExposure", palette_.exposure * state_.exposureMultiplier);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        ++stats_.drawCalls;
        ++stats_.triangles;
    }
    glBindVertexArray(0);
    glDepthMask(GL_TRUE);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
}

void RenderScene::recordDraw(const Mesh& mesh, GLsizei instanceCount, GLenum primitive) {
    if (!mesh || mesh.indexCount() <= 0 || instanceCount <= 0) return;
    ++stats_.drawCalls;
    if (primitive == GL_TRIANGLES) {
        stats_.triangles += static_cast<uint64_t>(mesh.indexCount() / 3) * static_cast<uint64_t>(instanceCount);
    }
}

void RenderScene::drainGlErrors() {
    for (;;) {
        const GLenum error = glGetError();
        if (error == GL_NO_ERROR) break;
        ++stats_.glErrors;
    }
}

RenderStats RenderScene::stats() const {
    RenderStats result = stats_;
    const std::array<const ShaderProgram*, 9> programs{{&skyProgram_, &litProgram_, &instancedProgram_, &oceanProgram_,
                                                       &particleProgram_, &bloomDownProgram_, &bloomBlurProgram_,
                                                       &finalProgram_, &copyProgram_}};
    for (const ShaderProgram* program : programs) if (*program) ++result.programs;
    const std::array<const Mesh*, 23> meshes{{&skyMesh_, &oceanMesh_, &roadMesh_, &guardrailMesh_, &treeMesh_, &pineMesh_,
                                             &palmMesh_, &rockMesh_, &lampMesh_, &lighthouseMesh_, &boatMesh_, &birdBodyMesh_,
                                             &birdWingMesh_, &flockPelicanBodyMesh_, &flockPelicanWingMesh_, &bicycleMesh_,
                                             &pelicanBodyMesh_, &pelicanHeadMesh_, &pelicanBeakMesh_, &pelicanWingMesh_,
                                             &fishMesh_, &scarfMesh_, &particleMesh_}};
    for (const Mesh* mesh : meshes) {
        if (*mesh) {
            ++result.vaos;
            result.buffers += 2;
        }
    }
    if (speedLineMesh_) {
        ++result.vaos;
        result.buffers += 2;
    }
    for (const ChunkGpu& chunk : chunks_) {
        if (chunk.terrain) {
            ++result.vaos;
            result.buffers += 2;
        }
        for (const InstancedBuffer* buffer : std::array<const InstancedBuffer*, 4>{{&chunk.roundTrees, &chunk.pines, &chunk.palms, &chunk.rocks}}) {
            if (*buffer) ++result.buffers;
        }
    }
    if (fullscreenVao_) ++result.vaos;
    if (noiseTexture_) ++result.textures;
    if (roadTexture_) ++result.textures;
    for (const Framebuffer* framebuffer : std::array<const Framebuffer*, 3>{{&hdrFramebuffer_, &bloomA_, &bloomB_}}) {
        if (*framebuffer) {
            ++result.framebuffers;
            ++result.textures;
            if (framebuffer->hasDepth()) ++result.renderbuffers;
        }
    }
    return result;
}

void RenderScene::orbitDrag(float dxNormalized, float dyNormalized) {
    if (!std::isfinite(dxNormalized) || !std::isfinite(dyNormalized)) return;
    orbitYaw_ = std::fmod(orbitYaw_ - dxNormalized * kTau * 0.75f, kTau);
    orbitPitch_ = clamp(orbitPitch_ + dyNormalized * kPi * 0.85f, radians(-89.0f), radians(89.0f));
    lastOrbitInputTime_ = state_.timeSeconds;
}

void RenderScene::orbitZoom(float scaleDelta) {
    if (!std::isfinite(scaleDelta) || scaleDelta <= 0.0f) return;
    orbitDistance_ = clamp(orbitDistance_ / scaleDelta, 1.1f, 28.0f);
    lastOrbitInputTime_ = state_.timeSeconds;
}

PickTarget RenderScene::pick(float normalizedX, float normalizedY) const {
    if (!initialized_ || !std::isfinite(normalizedX) || !std::isfinite(normalizedY)) return PickTarget::None;
    const float ndcX = clamp(normalizedX, 0.0f, 1.0f) * 2.0f - 1.0f;
    const float ndcY = 1.0f - clamp(normalizedY, 0.0f, 1.0f) * 2.0f;
    Mat4 inverseViewProjection;
    if (!inverse(projection_ * view_, inverseViewProjection)) return PickTarget::None;
    const Vec3 nearPoint = unprojectNdc(inverseViewProjection, {ndcX, ndcY, -1.0f});
    const Vec3 farPoint = unprojectNdc(inverseViewProjection, {ndcX, ndcY, 1.0f});
    const Vec3 direction = (farPoint - nearPoint).normalized({1, 0, 0});
    struct Hit { PickTarget target; float distance; };
    Hit best{PickTarget::None, std::numeric_limits<float>::max()};
    const auto sphereHit = [&](PickTarget target, const Vec3& center, float radius) {
        const Vec3 oc = nearPoint - center;
        const float b = dot(oc, direction);
        const float c = dot(oc, oc) - radius * radius;
        const float discriminant = b * b - c;
        if (discriminant < 0.0f) return;
        const float t = -b - std::sqrt(discriminant);
        if (t >= 0.0f && t < best.distance) best = {target, t};
    };
    sphereHit(PickTarget::Bell, {0.57f, 1.55f, -0.15f}, 0.13f);
    sphereHit(PickTarget::Pelican, {0.0f, 1.65f, 0.0f}, 0.72f);
    sphereHit(PickTarget::Bicycle, {0.0f, 0.65f, 0.0f}, 1.15f);
    if (std::abs(direction.y) > 1.0e-5f) {
        const float t = (static_cast<float>(kSeaLevel) - nearPoint.y) / direction.y;
        if (t >= 0.0f && t < best.distance) {
            const Vec3 point = nearPoint + direction * t;
            if (point.z < static_cast<float>(kShoreZ) + 2.5f) best = {PickTarget::Sea, t};
        }
    }
    return best.target;
}

std::vector<uint8_t> RenderScene::screenshotPixels() const {
    std::vector<uint8_t> pixels(static_cast<size_t>(width_) * height_ * 4);
    if (!initialized_ || width_ <= 0 || height_ <= 0) return {};
    Framebuffer::bindDefault();
    glFinish();
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, width_, height_, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
    if (glGetError() != GL_NO_ERROR) {
        ++stats_.glErrors;
        return {};
    }
    const size_t rowBytes = static_cast<size_t>(width_) * 4;
    std::vector<uint8_t> row(rowBytes);
    for (int y = 0; y < height_ / 2; ++y) {
        uint8_t* top = pixels.data() + static_cast<size_t>(y) * rowBytes;
        uint8_t* bottom = pixels.data() + static_cast<size_t>(height_ - 1 - y) * rowBytes;
        std::memcpy(row.data(), top, rowBytes);
        std::memcpy(top, bottom, rowBytes);
        std::memcpy(bottom, row.data(), rowBytes);
    }
    return pixels;
}

void RenderScene::destroy() {
    // Safe to call before a surface/context rebuild while the old context is still current.
    initialized_ = false;
    postProcessEnabled_ = false;
    bloomEnabled_ = false;
    hdrHalfFloat_ = false;
    hdrFramebuffer_.destroy();
    bloomA_.destroy();
    bloomB_.destroy();
    noiseTexture_.destroy();
    roadTexture_.destroy();
    if (fullscreenVao_) {
        glDeleteVertexArrays(1, &fullscreenVao_);
        fullscreenVao_ = 0;
    }
    for (ChunkGpu& chunk : chunks_) {
        chunk.terrain.destroy();
        chunk.roundTrees.destroy();
        chunk.pines.destroy();
        chunk.palms.destroy();
        chunk.rocks.destroy();
        chunk.index = std::numeric_limits<int64_t>::min();
    }
    skyMesh_.destroy();
    oceanMesh_.destroy();
    roadMesh_.destroy();
    guardrailMesh_.destroy();
    treeMesh_.destroy();
    pineMesh_.destroy();
    palmMesh_.destroy();
    rockMesh_.destroy();
    lampMesh_.destroy();
    lighthouseMesh_.destroy();
    boatMesh_.destroy();
    birdBodyMesh_.destroy();
    birdWingMesh_.destroy();
    flockPelicanBodyMesh_.destroy();
    flockPelicanWingMesh_.destroy();
    bicycleMesh_.destroy();
    pelicanBodyMesh_.destroy();
    pelicanHeadMesh_.destroy();
    pelicanBeakMesh_.destroy();
    pelicanWingMesh_.destroy();
    fishMesh_.destroy();
    scarfMesh_.destroy();
    particleMesh_.destroy();
    speedLineMesh_.destroy();
    skyProgram_.destroy();
    litProgram_.destroy();
    instancedProgram_.destroy();
    oceanProgram_.destroy();
    particleProgram_.destroy();
    bloomDownProgram_.destroy();
    bloomBlurProgram_.destroy();
    finalProgram_.destroy();
    copyProgram_.destroy();
    scratchScarf_.clear();
    scratchParticles_.clear();
    scratchSpeedLines_.clear();
    stats_ = {};
}

}  // namespace pelican::scene
