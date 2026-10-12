#pragma once

#include "GlResources.h"
#include "Simulation.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <limits>
#include <string>
#include <vector>

namespace pelican::scene {

enum class Quality : int {
    Low = 0,
    Medium = 1,
    High = 2,
};

enum class PickTarget : int {
    None = 0,
    Bell,
    Pelican,
    Bicycle,
    Sea,
};

struct OrbitCameraState {
    float yaw = 0.0f;
    float pitch = 0.0f;
    float distance = 0.0f;
};

// One catchable fish from the ride simulation's pool, in rider-relative coordinates.
struct FishPose {
    Vec3 localPosition{};  // +x ahead of the rider, y above the road, z lane
    float phase = 0.0f;
    float scale = 1.0f;
    bool golden = false;
};

constexpr uint32_t kMaxRenderFish = 12;

struct RenderStats {
    uint64_t drawCalls = 0;
    uint64_t triangles = 0;
    uint32_t textures = 0;
    uint32_t buffers = 0;
    uint32_t framebuffers = 0;
    uint32_t renderbuffers = 0;
    uint32_t programs = 0;
    uint32_t vaos = 0;
    uint32_t glErrors = 0;
    double cpuUpdateMs = 0.0;
    double cpuRenderMs = 0.0;
    double gpuRenderMs = 0.0; // Reserved; zero unless an outer integration adds timer queries.
};

struct RenderState {
    // Absolute travelled distance remains double for days-long sessions.
    double totalDistance = 0.0;
    double timeSeconds = 0.0;
    float deltaSeconds = 1.0f / 60.0f;
    float speedMetersPerSecond = 6.0f;
    float steering = 0.0f;
    float pedal = 1.0f;
    float airborne = 0.0f;
    float trick = 0.0f;
    float mouthOpen = 0.0f;
    // Pose channels forwarded from the ride simulation so the character rig matches gameplay.
    float crankAngle = 0.0f;
    float wheelAngle = 0.0f;
    float lean = 0.0f;
    float wheelie = 0.0f;
    float verticalPosition = 0.0f;
    float lane = 0.0f;
    float laneVelocity = 0.0f;
    // Catchable fish currently in play; the pelican eats these, so they drive the fish HUD.
    std::array<FishPose, kMaxRenderFish> fish{};
    uint32_t fishCount = 0;
    float hour = 16.5f;
    float cloudCover = 0.45f;
    float waveAmplitude = 1.0f;
    float cameraFovDegrees = 62.0f;
    Vec3 cameraPosition{-2.9f, 1.75f, 3.4f};
    Vec3 cameraTarget{4.2f, 0.75f, -1.0f};
    bool helmet = true;
    bool glasses = true;
    bool scarf = true;
    bool bloom = true;
    // Retained for API stability with the integration layer; the scene reads the
    // multipliers once the post-process hooks consume them.
    float fogMultiplier = 1.0f;
    float exposureMultiplier = 1.0f;
    float bloomBoost = 1.0f;
    bool enableSpeedLines = true;
    // When false, the scene's orbit camera is used and can be controlled by the gesture methods.
    bool useExternalCamera = true;
    bool autoRotateOrbit = true;
};

class RenderScene {
public:
    RenderScene();
    ~RenderScene();
    RenderScene(const RenderScene&) = delete;
    RenderScene& operator=(const RenderScene&) = delete;

    // The caller owns EGLDisplay/EGLContext/EGLSurface and must call every method on that context's thread.
    // No worker, sleep, busy loop, swap, or VSync object is created here.
    bool initialize(int width, int height, Quality quality);
    bool initialize(int width, int height, int quality) {
        return initialize(width, height, static_cast<Quality>(std::clamp(quality, 0, 2)));
    }
    void resize(int width, int height);
    void update(const RenderState& state);
    void render();
    void destroy();

    void orbitDrag(float dxNormalized, float dyNormalized);
    void orbitZoom(float scaleDelta);
    PickTarget pick(float normalizedX, float normalizedY) const;

    // Returns top-left-origin RGBA8 pixels from the current default framebuffer.
    std::vector<uint8_t> screenshotPixels() const;

    bool initialized() const { return initialized_; }
    const std::string& lastError() const { return lastError_; }
    RenderStats stats() const;
    OrbitCameraState orbitCameraState() const { return {orbitYaw_, orbitPitch_, orbitDistance_}; }

private:
    struct ChunkGpu {
        int64_t index = std::numeric_limits<int64_t>::min();
        Mesh terrain;
        InstancedBuffer roundTrees;
        InstancedBuffer pines;
        InstancedBuffer palms;
        InstancedBuffer rocks;
    };

    bool createPrograms();
    bool createMeshes();
    bool createTextures();
    bool createFramebuffers();
    void updateChunk(ChunkGpu& chunk, int64_t index);
    void updateDynamicMeshes();
    void updateParticles(float localScroll);
    void drawSceneGeometry();
    void drawSky();
    void drawOcean();
    void drawWorld();
    void drawCharacters();
    void drawEffects();
    void drawBird(const Mat4& bodyModel, float flap, bool pelican, bool mirrored = false);
    void postProcess();
    void drawLit(const Mesh& mesh, const Mat4& model, const Vec3& tint, float roughness,
                 const Vec3& emission = {0, 0, 0}, float sway = 0.0f,
                 const Texture2D* texture = nullptr);
    void drawInstanced(const Mesh& mesh, const InstancedBuffer& instances, const Mat4& model,
                       const Vec3& tint, float roughness, float sway = 0.0f);
    void setCommonLitUniforms(ShaderProgram& program, const Mat4& model, const Vec3& tint,
                              float roughness, const Vec3& emission, float sway,
                              const Texture2D* texture);
    void recordDraw(const Mesh& mesh, GLsizei instanceCount = 1, GLenum primitive = GL_TRIANGLES);
    void drainGlErrors();
    void fail(const std::string& message);

    bool initialized_ = false;
    bool postProcessEnabled_ = false;
    bool bloomEnabled_ = false;
    bool hdrHalfFloat_ = false;
    int width_ = 0;
    int height_ = 0;
    Quality quality_ = Quality::Medium;
    std::string lastError_;
    RenderState state_{};
    SkyPalette palette_{};
    Vec3 sunDir_{0, 1, 0};
    Vec3 moonDir_{0, -1, 0};
    float solarElevationDegrees_ = 30.0f;
    float night_ = 0.0f;
    float localTime_ = 0.0f;
    Mat4 view_{};
    Mat4 projection_{};
    Vec3 activeCameraPosition_{};
    Vec3 activeCameraTarget_{};
    float orbitYaw_ = -0.35f;
    float orbitPitch_ = 0.22f;
    float orbitDistance_ = 7.2f;
    double lastOrbitInputTime_ = -1000.0;
    std::array<float, kWaveCount> wavePhases_{};
    std::array<ChunkPlacement, kWorldChunkCount> chunkPlacements_{};

    ShaderProgram skyProgram_;
    ShaderProgram litProgram_;
    ShaderProgram instancedProgram_;
    ShaderProgram oceanProgram_;
    ShaderProgram particleProgram_;
    ShaderProgram bloomDownProgram_;
    ShaderProgram bloomBlurProgram_;
    ShaderProgram finalProgram_;
    ShaderProgram copyProgram_;

    Mesh skyMesh_;
    Mesh oceanMesh_;
    Mesh roadMesh_;
    Mesh guardrailMesh_;
    Mesh treeMesh_;
    Mesh pineMesh_;
    Mesh palmMesh_;
    Mesh rockMesh_;
    Mesh lampMesh_;
    Mesh lighthouseMesh_;
    Mesh boatMesh_;
    Mesh birdBodyMesh_;
    Mesh birdWingMesh_;
    Mesh flockPelicanBodyMesh_;
    Mesh flockPelicanWingMesh_;
    Mesh bicycleMesh_;
    Mesh frontWheelMesh_;
    Mesh rearWheelMesh_;
    Mesh crankMesh_;
    Mesh steeringMesh_;
    Mesh limbMesh_;
    Mesh shinMesh_;
    Mesh jointMesh_;
    Mesh footMesh_;
    Mesh pelicanBodyMesh_;
    Mesh pelicanNeckMesh_;
    Mesh pelicanHeadMesh_;
    Mesh pelicanBeakMesh_;
    Mesh pelicanWingMesh_;
    Mesh fishMesh_;
    Mesh scarfMesh_;
    Mesh particleMesh_;
    Mesh speedLineMesh_;

    std::array<ChunkGpu, kWorldChunkCount> chunks_{};

    Texture2D noiseTexture_;
    Texture2D roadTexture_;
    Framebuffer hdrFramebuffer_;
    Framebuffer bloomA_;
    Framebuffer bloomB_;
    GLuint fullscreenVao_ = 0;

    CharacterAnimator animator_;
    ScarfSimulation scarf_;
    ParticleSystem particles_;
    CpuMesh scratchScarf_;
    CpuMesh scratchNeck_;
    CpuMesh scratchParticles_;
    CpuMesh scratchSpeedLines_;
    Random effectsRandom_{0x514f3a29U};
    mutable RenderStats stats_{};
};

}  // namespace pelican::scene
