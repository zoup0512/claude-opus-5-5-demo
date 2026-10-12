#pragma once

#include "Geometry.h"

#include <array>
#include <cstdint>
#include <vector>

namespace pelican::scene {

constexpr double kSeaLevel = -1.6;
constexpr double kShoreZ = -14.6;
constexpr int kWaveCount = 5;
constexpr int kWorldChunkCount = 7;
constexpr double kWorldChunkLength = 72.0;

struct WaveDefinition {
    double directionX;
    double directionZ;
    double steepness;
    double wavelength;
    double speedMultiplier;
};

extern const std::array<WaveDefinition, kWaveCount> kWaves;

std::array<float, kWaveCount> computeWavePhases(double absoluteDistance, double timeSeconds);
double waveHeight(double absoluteX, double z, double timeSeconds, double amplitude = 1.0);

struct SkyPalette {
    Vec3 zenith{};
    Vec3 horizon{};
    Vec3 ground{};
    Vec3 sunColor{};
    Vec3 fogColor{};
    Vec3 cloudTint{};
    Vec3 cloudShade{};
    float sunIntensity = 1.0f;
    float horizonIntensity = 0.5f;
    float exposure = 1.0f;
    float bloom = 0.4f;
};

SkyPalette sampleSkyPalette(float solarElevationDegrees);
Vec3 sunDirection(float hour);
Vec3 moonDirection(float hour);
float nightFactor(float solarElevationDegrees);

struct ScarfCollider {
    Vec3 center{};
    float radius = 0.0f;
};

class ScarfSimulation {
public:
    static constexpr int kSegments = 16;
    static constexpr int kColumns = 2;
    static constexpr int kPointCount = kSegments * kColumns;

    ScarfSimulation(float width = 0.075f, float segmentLength = 0.045f);

    void reset(const Vec3& rootA, const Vec3& rootB);
    void update(float dt, const Vec3& rootA, const Vec3& rootB, const Vec3& wind,
                float timeSeconds, const ScarfCollider* collider);

    const std::array<Vec3, kPointCount>& positions() const { return positions_; }
    void injectNonFiniteForTest();
    void fillMesh(CpuMesh& mesh) const;
    CpuMesh buildMesh() const;
    bool finite() const;

private:
    void constrain(int i, int j, float restLength, bool pinI);

    float width_;
    float segmentLength_;
    bool initialized_ = false;
    std::array<Vec3, kPointCount> positions_{};
    std::array<Vec3, kPointCount> previous_{};
};

struct Particle {
    Vec3 position{};
    Vec3 velocity{};
    Vec3 color{1, 1, 1};
    float size = 0.05f;
    float life = 0.0f;
    float maxLife = 0.0f;
    float drag = 0.5f;
    float gravity = 0.0f;
    bool groundLocked = false;
};

class ParticleSystem {
public:
    explicit ParticleSystem(size_t capacity = 256);

    void emit(const Particle& particle);
    void update(float dt, float localScroll);
    const std::vector<Particle>& particles() const { return particles_; }
    size_t aliveCount() const;

private:
    std::vector<Particle> particles_;
    size_t cursor_ = 0;
};

struct AnimatedNodes {
    Mat4 bicycle{};
    Mat4 frontWheel{};
    Mat4 rearWheel{};
    Mat4 crank{};
    Mat4 handlebar{};
    Mat4 pelicanBody{};
    Mat4 pelicanHead{};
    Mat4 pelicanBeak{};
    Mat4 leftWing{};
    Mat4 rightWing{};
    // Two-bone leg rig: thigh/shin span a joint pair, knee/ankle are joint spheres,
    // foot carries the pedal contact.
    Mat4 thighLeft{};
    Mat4 shinLeft{};
    Mat4 kneeLeft{};
    Mat4 ankleLeft{};
    Mat4 footLeft{};
    Mat4 thighRight{};
    Mat4 shinRight{};
    Mat4 kneeRight{};
    Mat4 ankleRight{};
    Mat4 footRight{};
};

struct AnimationInputs {
    float time = 0.0f;
    float deltaTime = 0.0f;
    float speed = 0.0f;
    float steering = 0.0f;
    float pedal = 1.0f;
    float airborne = 0.0f;
    float trick = 0.0f;
    float mouthOpen = 0.0f;
    float waveAmplitude = 1.0f;
    // Pose channels owned by the ride simulation; the rig composes them instead of
    // integrating its own copy, so the character always matches gameplay state.
    float crankAngle = 0.0f;
    float wheelAngle = 0.0f;
    float lean = 0.0f;
    float wheelie = 0.0f;
    float verticalPosition = 0.0f;
    float lane = 0.0f;
    float laneVelocity = 0.0f;
};

class CharacterAnimator {
public:
    void update(const AnimationInputs& inputs);
    const AnimatedNodes& nodes() const { return nodes_; }
    float wheelAngle() const { return wheelAngle_; }
    float crankAngle() const { return crankAngle_; }

private:
    AnimatedNodes nodes_{};
    float wheelAngle_ = 0.0f;
    float crankAngle_ = 0.0f;
    float jaw_ = 0.0f;
    float wingSpread_ = 0.0f;
};

struct ChunkPlacement {
    int64_t index = 0;
    float localX = 0.0f;
};

std::array<ChunkPlacement, kWorldChunkCount> computeChunkPlacements(double totalDistance);

}  // namespace pelican::scene
