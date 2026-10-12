#include "Simulation.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>

namespace pelican::scene {

const std::array<WaveDefinition, kWaveCount> kWaves = {{
    {0.18, 1.0, 0.20, 21.0, 1.0},
    {-0.45, 1.0, 0.17, 12.5, 1.0},
    {0.75, 0.62, 0.13, 7.0, 1.0},
    {-0.9, 0.45, 0.10, 4.2, 1.0},
    {0.3, 1.0, 0.07, 2.6, 1.0},
}};

std::array<float, kWaveCount> computeWavePhases(double absoluteDistance, double timeSeconds) {
    std::array<float, kWaveCount> phases{};
    constexpr double tau = 6.283185307179586476925286766559;
    for (size_t i = 0; i < kWaves.size(); ++i) {
        const WaveDefinition& wave = kWaves[i];
        const double k = tau / wave.wavelength;
        const double directionLength = std::hypot(wave.directionX, wave.directionZ);
        const double dx = wave.directionX / std::max(directionLength, 1.0e-12);
        const double c = std::sqrt(9.8 / k) * wave.speedMultiplier;
        // Keep all long-distance arithmetic in double; only the wrapped phase reaches GLES.
        double phase = std::fmod(k * dx * absoluteDistance - k * c * timeSeconds, tau);
        if (phase < -tau) {
            phase += tau;
        } else if (phase > tau) {
            phase -= tau;
        }
        phases[i] = std::isfinite(phase) ? static_cast<float>(phase) : 0.0f;
    }
    return phases;
}

double waveHeight(double absoluteX, double z, double timeSeconds, double amplitude) {
    const double normalized = std::clamp((kShoreZ + 1.0 - z) / 31.0, 0.0, 1.0);
    const double shoreAttenuatedAmplitude = amplitude * (0.35 + 0.65 * normalized * normalized * (3.0 - 2.0 * normalized));
    double y = 0.0;
    constexpr double tau = 6.283185307179586476925286766559;
    for (const WaveDefinition& wave : kWaves) {
        const double k = tau / wave.wavelength;
        const double directionLength = std::hypot(wave.directionX, wave.directionZ);
        const double dx = wave.directionX / std::max(directionLength, 1.0e-12);
        const double dz = wave.directionZ / std::max(directionLength, 1.0e-12);
        const double c = std::sqrt(9.8 / k) * wave.speedMultiplier;
        const double phase = std::remainder(k * (dx * absoluteX + dz * z - c * timeSeconds), tau);
        y += ((wave.steepness * shoreAttenuatedAmplitude) / k) * std::sin(phase);
    }
    const double result = kSeaLevel + y;
    return std::isfinite(result) ? result : kSeaLevel;
}

namespace {

struct PaletteKey {
    float elevation;
    Vec3 zenith;
    Vec3 horizon;
    Vec3 ground;
    Vec3 sun;
    float light;
    float horizonIntensity;
    Vec3 fog;
    float exposure;
    Vec3 cloudTint;
    Vec3 cloudShade;
    float bloom;
};

constexpr std::array<PaletteKey, 7> kPalette = {{
    {-24.0f, {0.001f, 0.0015f, 0.004f}, {0.002f, 0.003f, 0.009f}, {0.001f, 0.0015f, 0.003f}, {0, 0, 0}, 0.0f, 0.42f, {0.004f, 0.006f, 0.013f}, 1.5f, {0.008f, 0.012f, 0.026f}, {0.002f, 0.002f, 0.005f}, 0.95f},
    {-9.0f, {0.003f, 0.008f, 0.030f}, {0.017f, 0.019f, 0.068f}, {0.006f, 0.007f, 0.017f}, {1.0f, 0.10f, 0.035f}, 0.0f, 0.45f, {0.010f, 0.013f, 0.040f}, 1.4f, {0.026f, 0.024f, 0.065f}, {0.005f, 0.005f, 0.014f}, 0.85f},
    {-2.0f, {0.012f, 0.024f, 0.105f}, {0.63f, 0.14f, 0.068f}, {0.10f, 0.038f, 0.045f}, {1.0f, 0.105f, 0.023f}, 0.25f, 0.45f, {0.145f, 0.068f, 0.102f}, 1.18f, {0.75f, 0.19f, 0.10f}, {0.043f, 0.024f, 0.064f}, 0.70f},
    {3.0f, {0.029f, 0.078f, 0.32f}, {1.0f, 0.31f, 0.10f}, {0.10f, 0.043f, 0.025f}, {1.0f, 0.25f, 0.045f}, 1.3f, 0.55f, {0.66f, 0.26f, 0.15f}, 1.0f, {1.0f, 0.46f, 0.24f}, {0.145f, 0.08f, 0.16f}, 0.55f},
    {10.0f, {0.043f, 0.16f, 0.53f}, {1.0f, 0.58f, 0.31f}, {0.16f, 0.10f, 0.065f}, {1.0f, 0.54f, 0.21f}, 2.3f, 0.65f, {0.81f, 0.54f, 0.36f}, 0.95f, {1.0f, 0.87f, 0.72f}, {0.32f, 0.36f, 0.48f}, 0.42f},
    {28.0f, {0.029f, 0.18f, 0.64f}, {0.49f, 0.71f, 0.89f}, {0.19f, 0.16f, 0.10f}, {1.0f, 0.87f, 0.67f}, 3.0f, 0.80f, {0.50f, 0.70f, 0.82f}, 0.90f, {1.0f, 1.0f, 1.0f}, {0.46f, 0.54f, 0.68f}, 0.32f},
    {75.0f, {0.019f, 0.15f, 0.66f}, {0.57f, 0.77f, 0.96f}, {0.20f, 0.17f, 0.11f}, {1.0f, 1.0f, 1.0f}, 3.3f, 0.85f, {0.54f, 0.72f, 0.87f}, 0.88f, {1.0f, 1.0f, 1.0f}, {0.50f, 0.57f, 0.69f}, 0.30f},
}};

}  // namespace

SkyPalette sampleSkyPalette(float solarElevationDegrees) {
    size_t index = 0;
    while (index + 2 < kPalette.size() && solarElevationDegrees > kPalette[index + 1].elevation) {
        ++index;
    }
    const PaletteKey& a = kPalette[index];
    const PaletteKey& b = kPalette[std::min(index + 1, kPalette.size() - 1)];
    const float t = saturate((solarElevationDegrees - a.elevation) / std::max(b.elevation - a.elevation, 1.0e-5f));
    SkyPalette result;
    result.zenith = sanitizeColor(mix(a.zenith, b.zenith, t), 48.0f);
    result.horizon = sanitizeColor(mix(a.horizon, b.horizon, t), 48.0f);
    result.ground = sanitizeColor(mix(a.ground, b.ground, t), 48.0f);
    result.sunColor = sanitizeColor(mix(a.sun, b.sun, t), 48.0f);
    result.fogColor = sanitizeColor(mix(a.fog, b.fog, t), 48.0f);
    result.cloudTint = sanitizeColor(mix(a.cloudTint, b.cloudTint, t), 48.0f);
    result.cloudShade = sanitizeColor(mix(a.cloudShade, b.cloudShade, t), 48.0f);
    result.sunIntensity = lerp(a.light, b.light, t);
    result.horizonIntensity = lerp(a.horizonIntensity, b.horizonIntensity, t);
    result.exposure = lerp(a.exposure, b.exposure, t);
    result.bloom = lerp(a.bloom, b.bloom, t);
    return result;
}

Vec3 sunDirection(float hour) {
    const float dayT = (hour - 6.0f) / 12.0f;
    float nightT = std::fmod(hour - 18.0f + 24.0f, 24.0f) / 12.0f;
    if (nightT < 0.0f) {
        nightT += 2.0f;
    }
    const float elevation = hour >= 6.0f && hour <= 18.0f
        ? std::sin(dayT * kPi) * radians(66.0f)
        : -std::sin(nightT * kPi) * 0.9f;
    const float azimuth = radians(120.0f - dayT * 180.0f);
    return Vec3{std::cos(elevation) * std::cos(azimuth), std::sin(elevation),
                std::cos(elevation) * std::sin(azimuth)}.normalized({0, 1, 0});
}

Vec3 moonDirection(float hour) {
    float nightT = std::fmod(hour - 18.0f + 24.0f, 24.0f) / 12.0f;
    if (nightT < 0.0f) {
        nightT += 2.0f;
    }
    const float elevation = std::sin(saturate(nightT) * kPi) * 0.95f - 0.12f;
    const float azimuth = radians(-110.0f + nightT * 150.0f);
    return Vec3{std::cos(elevation) * std::cos(azimuth), std::sin(elevation),
                std::cos(elevation) * std::sin(azimuth)}.normalized({0, 1, 0});
}

float nightFactor(float solarElevationDegrees) {
    return smoothstep(-1.5f, -11.0f, solarElevationDegrees);
}

ScarfSimulation::ScarfSimulation(float width, float segmentLength)
    : width_(width), segmentLength_(segmentLength) {}

void ScarfSimulation::reset(const Vec3& rootA, const Vec3& rootB) {
    for (int segment = 0; segment < kSegments; ++segment) {
        for (int column = 0; column < kColumns; ++column) {
            const int index = segment * kColumns + column;
            const Vec3 root = column == 0 ? rootA : rootB;
            positions_[index] = root + Vec3{-static_cast<float>(segment) * segmentLength_, 0, 0};
        }
    }
    previous_ = positions_;
    initialized_ = true;
}

void ScarfSimulation::injectNonFiniteForTest() {
    positions_[kPointCount - 1].x = std::numeric_limits<float>::quiet_NaN();
}

bool ScarfSimulation::finite() const {
    for (const Vec3& point : positions_) {
        if (!point.finite()) {
            return false;
        }
    }
    return true;
}

void ScarfSimulation::update(float dt, const Vec3& rootA, const Vec3& rootB, const Vec3& wind,
                             float timeSeconds, const ScarfCollider* collider) {
    // The far end catches divergence first. Check both complete state and tail explicitly.
    if (initialized_ && (!positions_[kPointCount - 1].finite() || !positions_[kPointCount - 2].finite() || !finite())) {
        initialized_ = false;
    }
    if (!initialized_) {
        reset(rootA, rootB);
    }

    constexpr int substeps = 2;
    constexpr int constraintIterations = 4;
    const float stepDt = std::min(std::max(dt, 0.0f), 1.0f / 30.0f) / static_cast<float>(substeps);
    if (!(stepDt > 0.0f) || !std::isfinite(stepDt)) {
        positions_[0] = rootA;
        positions_[1] = rootB;
        previous_[0] = rootA;
        previous_[1] = rootB;
        return;
    }

    for (int step = 0; step < substeps; ++step) {
        for (int segment = 1; segment < kSegments; ++segment) {
            for (int column = 0; column < kColumns; ++column) {
                const int index = segment * kColumns + column;
                const Vec3 position = positions_[index];
                Vec3 velocity = position - previous_[index];
                previous_[index] = position;
                const float f = static_cast<float>(segment) / static_cast<float>(kSegments);
                const float flutter = std::sin(timeSeconds * 17.0f + segment * 0.9f + column * 0.4f) * (0.6f + f * 2.2f);
                const Vec3 inferredVelocity = velocity / stepDt;
                const Vec3 acceleration{
                    (wind.x - inferredVelocity.x) * 2.2f,
                    -9.8f * 0.55f + (wind.y - inferredVelocity.y) * 1.2f +
                        flutter * 1.4f * std::min(1.0f, std::abs(wind.x) / 6.0f),
                    (wind.z - inferredVelocity.z) * 2.2f +
                        std::cos(timeSeconds * 13.0f + segment * 0.7f) * flutter * 0.8f,
                };
                velocity *= 0.985f;
                positions_[index] += velocity + acceleration * (stepDt * stepDt);
            }
        }

        positions_[0] = rootA;
        positions_[1] = rootB;
        for (int iteration = 0; iteration < constraintIterations; ++iteration) {
            for (int segment = 0; segment < kSegments - 1; ++segment) {
                constrain(segment * 2, (segment + 1) * 2, segmentLength_, segment == 0);
                constrain(segment * 2 + 1, (segment + 1) * 2 + 1, segmentLength_, segment == 0);
                constrain((segment + 1) * 2, (segment + 1) * 2 + 1, width_, false);
                const float diagonal = std::hypot(segmentLength_, width_);
                constrain(segment * 2, (segment + 1) * 2 + 1, diagonal, segment == 0);
                constrain(segment * 2 + 1, (segment + 1) * 2, diagonal, segment == 0);
            }
            positions_[0] = rootA;
            positions_[1] = rootB;
            if (collider && collider->radius > 0.0f) {
                for (int index = 2; index < kPointCount; ++index) {
                    Vec3 offset = positions_[index] - collider->center;
                    const float distance = offset.length();
                    if (distance < collider->radius) {
                        positions_[index] = collider->center + offset.normalized({-1, 0, 0}) * collider->radius;
                    }
                }
            }
        }
    }

    if (!finite()) {
        reset(rootA, rootB);
    }
}

void ScarfSimulation::constrain(int i, int j, float restLength, bool pinI) {
    Vec3 delta = positions_[j] - positions_[i];
    const float distance = std::max(delta.length(), 1.0e-6f);
    const float difference = (distance - restLength) / distance;
    if (pinI) {
        positions_[j] -= delta * difference;
    } else {
        const Vec3 correction = delta * (difference * 0.5f);
        positions_[i] += correction;
        positions_[j] -= correction;
    }
}

void ScarfSimulation::fillMesh(CpuMesh& mesh) const {
    mesh.clear();
    mesh.vertices.reserve(kPointCount);
    mesh.indices.reserve((kSegments - 1) * 6);
    const Vec3 scarfRed{0.68f, 0.015f, 0.04f};
    for (int segment = 0; segment < kSegments; ++segment) {
        const float t = static_cast<float>(segment) / static_cast<float>(kSegments - 1);
        // Cloth narrows towards the tail and rounds off at the tip, so the ribbon reads as
        // fabric instead of a constant-width slab.
        const float taper = lerp(1.0f, 0.42f, smoothstep(0.15f, 1.0f, t));
        const Vec3& edgeA = positions_[segment * kColumns];
        const Vec3& edgeB = positions_[segment * kColumns + 1];
        const Vec3 center = (edgeA + edgeB) * 0.5f;
        // Slight darkening along the length keeps the folds readable in flat lighting.
        const Vec3 color = mix(scarfRed, Vec3{0.44f, 0.01f, 0.03f}, 0.35f * t);
        for (int column = 0; column < kColumns; ++column) {
            const Vec3& edge = column == 0 ? edgeA : edgeB;
            mesh.vertices.push_back({mix(center, edge, taper), {0, 1, 0}, color,
                                     {t, static_cast<float>(column)}});
        }
    }
    for (uint32_t segment = 0; segment < kSegments - 1; ++segment) {
        const uint32_t a = segment * 2;
        mesh.indices.insert(mesh.indices.end(), {a, a + 2, a + 1, a + 1, a + 2, a + 3});
    }
    mesh.recomputeNormals();
    // Recompute can produce zero for a perfectly flat/degenerate local patch. Enforce finite fallback.
    for (Vertex& vertex : mesh.vertices) {
        if (!vertex.normal.finite() || vertex.normal.lengthSquared() <= 1.0e-8f) {
            vertex.normal = {0.0f, 1.0f, 0.0f};
        }
    }
}

CpuMesh ScarfSimulation::buildMesh() const {
    CpuMesh mesh;
    fillMesh(mesh);
    return mesh;
}

ParticleSystem::ParticleSystem(size_t capacity) : particles_(capacity) {}

void ParticleSystem::emit(const Particle& particle) {
    if (particles_.empty()) {
        return;
    }
    particles_[cursor_] = particle;
    particles_[cursor_].color = sanitizeColor(particle.color, 48.0f);
    particles_[cursor_].maxLife = std::max(particle.maxLife > 0.0f ? particle.maxLife : particle.life, 1.0e-4f);
    cursor_ = (cursor_ + 1) % particles_.size();
}

void ParticleSystem::update(float dt, float localScroll) {
    dt = clamp(dt, 0.0f, 0.1f);
    for (Particle& particle : particles_) {
        if (particle.life <= 0.0f) {
            continue;
        }
        particle.life -= dt;
        const float drag = std::exp(-particle.drag * dt);
        particle.velocity *= drag;
        particle.velocity.y -= particle.gravity * dt;
        particle.position += particle.velocity * dt;
        if (particle.groundLocked) {
            particle.position.x -= localScroll;
        }
        if (!particle.position.finite() || !particle.velocity.finite()) {
            particle.life = 0.0f;
        }
    }
}

size_t ParticleSystem::aliveCount() const {
    return static_cast<size_t>(std::count_if(particles_.begin(), particles_.end(),
                                             [](const Particle& particle) { return particle.life > 0.0f; }));
}

namespace {

// Rig landmarks shared with Geometry.cpp's bicycle parts (frame local space, metres).
const Vec3 kRearHub{-0.46f, 0.30f, 0.0f};
const Vec3 kFrontHub{0.48f, 0.30f, 0.0f};
const Vec3 kBottomBracket{-0.06f, 0.25f, 0.0f};
const Vec3 kSteeringPivot{0.34f, 0.645f, 0.0f};
constexpr float kCrankRadius = 0.15f;
constexpr float kPedalHalfTrack = 0.078f;

// Pedal contact sits slightly forward of the spindle, matching the H5 rig.
constexpr float kPedalTargetForward = 0.04f;
constexpr float kPedalTargetUp = 0.046f;

// Leg segment lengths sized for this rig's hip-to-pedal reach (0.59 m..0.65 m):
// reach is clamped below thigh+shin so the knee always keeps a visible bend.
constexpr float kThighLength = 0.36f;
constexpr float kShinLength = 0.37f;
constexpr float kThighRadius = 0.055f;
// Bare lower leg is much thinner than the feathered thigh, matching the H5 rig ratio.
constexpr float kShinRadius = 0.022f;
constexpr float kJointRadius = 0.052f;
constexpr float kAnkleRadius = 0.028f;

Vec3 rotateZ(const Vec3& value, float angle) {
    const float c = std::cos(angle);
    const float s = std::sin(angle);
    return {value.x * c - value.y * s, value.x * s + value.y * c, value.z};
}

// Column-major basis whose local +Y spans a -> b, so a unit limb mesh maps onto the segment.
Mat4 segmentMatrix(const Vec3& a, const Vec3& b) {
    const Vec3 delta = b - a;
    const float length = std::max(delta.length(), 1.0e-4f);
    const Vec3 axis = delta / length;
    const Vec3 reference = std::abs(axis.z) < 0.9f ? Vec3{0.0f, 0.0f, 1.0f} : Vec3{1.0f, 0.0f, 0.0f};
    const Vec3 side = cross(reference, axis).normalized({1.0f, 0.0f, 0.0f});
    const Vec3 up = cross(axis, side);
    Mat4 basis;
    basis.m[0] = side.x;
    basis.m[1] = side.y;
    basis.m[2] = side.z;
    basis.m[4] = axis.x;
    basis.m[5] = axis.y;
    basis.m[6] = axis.z;
    basis.m[8] = up.x;
    basis.m[9] = up.y;
    basis.m[10] = up.z;
    return Mat4::translation((a + b) * 0.5f) * basis * Mat4::scale({1.0f, length, 1.0f});
}

// Law-of-cosines two-bone solve; the pole steers the bend direction.
void solveTwoBone(const Vec3& root, const Vec3& target, float upper, float lower,
                  const Vec3& pole, Vec3& joint, Vec3& end) {
    const Vec3 delta = target - root;
    const float distance = std::max(delta.length(), 1.0e-4f);
    const float reach = clamp(distance, std::abs(upper - lower) + 1.0e-4f, (upper + lower) * 0.999f);
    const Vec3 axis = delta / distance;

    Vec3 bend = pole - axis * dot(pole, axis);
    if (bend.lengthSquared() < 1.0e-8f) {
        bend = cross(axis, Vec3{0.0f, 0.0f, 1.0f});
    }
    bend = bend.normalized({1.0f, 0.0f, 0.0f});

    const float cosine = clamp((upper * upper + reach * reach - lower * lower) / (2.0f * upper * reach), -1.0f, 1.0f);
    const float angle = std::acos(cosine);
    joint = root + (axis * std::cos(angle) + bend * std::sin(angle)) * upper;
    end = target;
}

}  // namespace

void CharacterAnimator::update(const AnimationInputs& inputs) {
    const float dt = clamp(inputs.deltaTime, 0.0f, 0.1f);
    // The ride simulation owns these angles (gear-aware crank speed); wrap only for drawing.
    wheelAngle_ = std::fmod(inputs.wheelAngle, kTau);
    crankAngle_ = std::fmod(inputs.crankAngle, kTau);
    if (wheelAngle_ < 0.0f) {
        wheelAngle_ += kTau;
    }
    if (crankAngle_ < 0.0f) {
        crankAngle_ += kTau;
    }
    jaw_ = damp(jaw_, saturate(inputs.mouthOpen), 20.0f, dt);
    wingSpread_ = damp(wingSpread_, saturate(inputs.trick), 5.0f, dt);

    const float bob = -std::abs(std::sin(crankAngle_)) * 0.012f * inputs.pedal;
    const float wingFlap = std::sin(inputs.time * 8.5f) * 0.55f * inputs.airborne +
                           std::sin(inputs.time * 2.6f) * 0.32f * wingSpread_;
    const float steerAngle = inputs.steering * 0.35f;

    // ---- rider root: jump height + lane offset + lean/yaw + wheelie about the rear contact ----
    const float yaw = -std::atan2(inputs.laneVelocity, std::max(inputs.speed, 1.5f));
    const Mat4 riderRoot = Mat4::translation({0.0f, inputs.verticalPosition, inputs.lane}) *
                           Mat4::rotationY(yaw) * Mat4::rotationX(inputs.lean);
    const Mat4 root = riderRoot *
                      Mat4::translation(kRearHub) * Mat4::rotationZ(inputs.wheelie) * Mat4::translation(-kRearHub);

    // ---- rider-local pose (bicycle frame space) ----
    const Mat4 steeringLocal = Mat4::translation(kSteeringPivot) * Mat4::rotationY(steerAngle);
    const Mat4 frontWheelLocal = steeringLocal *
        compose(kFrontHub - kSteeringPivot, {0.0f, 0.0f, -wheelAngle_});
    const Mat4 rearWheelLocal = compose(kRearHub, {0.0f, 0.0f, -wheelAngle_});
    const Mat4 crankLocal = compose(kBottomBracket, {0.0f, 0.0f, -crankAngle_});

    Mat4 bodyLocal = compose({-0.13f, 0.965f + bob + inputs.airborne * 0.025f, 0},
                             {std::sin(crankAngle_) * 0.035f * inputs.pedal, 0, 0.35f + inputs.trick * 0.14f});
    Mat4 headLocal = compose({0.23f, 1.37f - bob * 0.75f, 0},
                             {0, std::sin(inputs.time * 0.35f) * 0.12f, -0.05f});
    Mat4 beakLocal = headLocal * compose({0.078f, -0.016f, 0}, {0, 0, -0.3f - jaw_ * 0.55f});
    // Wings fold by yawing back along the body and rolling the wing surface upright so the
    // folded wing hugs the flank; both relax toward the spread pose as the trick ramps up.
    const float wingYaw = lerp(2.50f, 0.35f, wingSpread_);
    const float wingRoll = lerp(1.30f, 0.0f, wingSpread_);
    Mat4 leftWingLocal = bodyLocal * compose({0.14f, 0.085f, -0.17f},
                                             {wingFlap - wingRoll, -wingYaw, 0}, {1, 1, -1});
    Mat4 rightWingLocal = bodyLocal * compose({0.14f, 0.085f, 0.17f},
                                             {-wingFlap + wingRoll, wingYaw, 0});

    // ---- legs: two-bone IK onto the spinning pedals ----
    struct LegRig {
        float side;
        Mat4* thigh;
        Mat4* shin;
        Mat4* knee;
        Mat4* ankle;
        Mat4* foot;
    };
    const std::array<LegRig, 2> legs{{
        {-1.0f, &nodes_.thighLeft, &nodes_.shinLeft, &nodes_.kneeLeft, &nodes_.ankleLeft, &nodes_.footLeft},
        {1.0f, &nodes_.thighRight, &nodes_.shinRight, &nodes_.kneeRight, &nodes_.ankleRight, &nodes_.footRight},
    }};
    for (const LegRig& leg : legs) {
        const float side = leg.side;
        const Vec3 hip = transformPoint(bodyLocal, {-0.05f, -0.125f, side * 0.09f});
        const float pedalPhase = -crankAngle_ + (side > 0.0f ? 0.0f : kPi);
        const Vec3 pedal = kBottomBracket + rotateZ({kCrankRadius, 0.0f, side * kPedalHalfTrack}, pedalPhase);
        const Vec3 target{pedal.x - kPedalTargetForward, pedal.y + kPedalTargetUp, pedal.z * 0.92f};
        const Vec3 pole{1.0f, 0.15f, side * 0.32f};

        Vec3 knee{};
        Vec3 ankle{};
        solveTwoBone(hip, target, kThighLength, kShinLength, pole, knee, ankle);

        const Mat4 thigh = segmentMatrix(hip, knee) * Mat4::scale({kThighRadius, 1.0f, kThighRadius});
        const Mat4 shin = segmentMatrix(knee, ankle) * Mat4::scale({kShinRadius, 1.0f, kShinRadius});
        const Mat4 kneeJoint = compose(knee, {}, {kJointRadius, kJointRadius, kJointRadius});
        // Ankle sphere closes the gap between the thin bare shin and the foot plate.
        const Mat4 ankleJoint = compose(ankle, {}, {kAnkleRadius, kAnkleRadius, kAnkleRadius});
        const Mat4 foot = compose({ankle.x - 0.012f, ankle.y - 0.04f, ankle.z},
                                  {0, 0, -0.08f + std::sin(-crankAngle_ + (side > 0.0f ? 0.0f : kPi) + 0.6f) * 0.12f});
        *leg.thigh = root * thigh;
        *leg.shin = root * shin;
        *leg.knee = root * kneeJoint;
        *leg.ankle = root * ankleJoint;
        *leg.foot = root * foot;
    }

    nodes_.bicycle = root;
    nodes_.frontWheel = root * frontWheelLocal;
    nodes_.rearWheel = root * rearWheelLocal;
    nodes_.crank = root * crankLocal;
    nodes_.handlebar = root * steeringLocal;
    nodes_.pelicanBody = root * bodyLocal;
    nodes_.pelicanHead = root * headLocal;
    nodes_.pelicanBeak = root * beakLocal;
    nodes_.leftWing = root * leftWingLocal;
    nodes_.rightWing = root * rightWingLocal;

}

std::array<ChunkPlacement, kWorldChunkCount> computeChunkPlacements(double totalDistance) {
    std::array<ChunkPlacement, kWorldChunkCount> result{};
    const int64_t base = static_cast<int64_t>(std::floor(totalDistance / kWorldChunkLength)) - 3;
    for (int slot = 0; slot < kWorldChunkCount; ++slot) {
        const int64_t index = base + slot;
        const double local = static_cast<double>(index) * kWorldChunkLength - totalDistance;
        result[slot] = {index, std::isfinite(local) ? static_cast<float>(local) : 0.0f};
    }
    return result;
}

}  // namespace pelican::scene
