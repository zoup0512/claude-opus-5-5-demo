#include "pelican/environment.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

namespace pelican {
namespace {

constexpr std::array<GerstnerWave, kWaveCount> kWaves{{
    {{0.18, 1.0}, 0.20, 21.0, 1.0},
    {{-0.45, 1.0}, 0.17, 12.5, 1.0},
    {{0.75, 0.62}, 0.13, 7.0, 1.0},
    {{-0.9, 0.45}, 0.10, 4.2, 1.0},
    {{0.3, 1.0}, 0.07, 2.6, 1.0},
}};

// Binary64 coefficients captured from V8 evaluating ocean.js. They isolate
// source-parity verification from small cross-libm hypot/sqrt differences.
constexpr std::array<double, kWaveCount> kSourceDistancePhaseCoefficients{{
    0x1.b2358e5aa085ep-5, -0x1.a671d251aa783p-3,
    0x1.6235cbfe2a4b9p-1, -0x1.568b18c80d9a2p+0,
    0x1.638967dadd189p-1,
}};
constexpr std::array<double, kWaveCount> kSourceTimePhaseCoefficients{{
    0x1.b65cc5d90f73ep+0, 0x1.1c175f7b6ff49p+1,
    0x1.7ba20a44f4110p+1, 0x1.ea1aa3667d6bfp+1,
    0x1.3774a838c1c88p+2,
}};

constexpr std::array<int, 256> kPermutation{{
    151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225,
    140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148,
    247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32,
    57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68,
    175, 74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111,
    229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244,
    102, 143, 54, 65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187,
    208, 89, 18, 169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100,
    109, 198, 173, 186, 3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38,
    147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227, 47, 16, 58, 17,
    182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44, 154,
    163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19,
    98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97,
    228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81,
    51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106,
    157, 184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138,
    236, 205, 93, 222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66,
    215, 61, 156, 180,
}};

[[nodiscard]] int perm(int index) noexcept {
  return kPermutation[static_cast<std::size_t>(index & 255)];
}

[[nodiscard]] double fade(double t) noexcept {
  return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

[[nodiscard]] double grad(int hash, double x, double y, double z) noexcept {
  const int h = hash & 15;
  const double u = h < 8 ? x : y;
  const double v = h < 4 ? y : (h == 12 || h == 14 ? x : z);
  return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v);
}

[[nodiscard]] double fbm2(double x, double z, int octaves,
                          double seed) noexcept {
  static const ImprovedNoise noise;
  double sum = 0.0;
  double amplitude = 0.5;
  double frequency = 1.0;
  for (int index = 0; index < octaves; ++index) {
    sum += amplitude *
           noise.noise(x * frequency, z * frequency, seed + index * 7.31);
    amplitude *= 0.5;
    frequency *= 2.03;
  }
  return sum;
}

[[nodiscard]] double wrapHour(double hour) noexcept {
  const double wrapped = std::fmod(hour, 24.0);
  return wrapped < 0.0 ? wrapped + 24.0 : wrapped;
}

}  // namespace

const std::array<GerstnerWave, kWaveCount>& oceanWaves() noexcept {
  return kWaves;
}

std::array<double, kWaveCount> gerstnerWavePhasesSourceParity(
    double distance, double timeSeconds) noexcept {
  std::array<double, kWaveCount> result{};
  for (std::size_t index = 0; index < kWaves.size(); ++index) {
    result[index] = std::fmod(
        kSourceDistancePhaseCoefficients[index] * distance -
            kSourceTimePhaseCoefficients[index] * timeSeconds,
        kTau);
  }
  return result;
}

std::array<double, kWaveCount> gerstnerWavePhases(double distance,
                                                  double timeSeconds) noexcept {
  std::array<double, kWaveCount> result{};
  for (std::size_t index = 0; index < kWaves.size(); ++index) {
    const GerstnerWave& wave = kWaves[index];
    const double waveNumber = kTau / wave.wavelength;
    const double speed = std::sqrt(9.8 / waveNumber) * wave.speedMultiplier;
    const Vec2 direction = wave.direction.normalized();
    const double distancePhase =
        std::fmod(waveNumber * direction.x * distance, kTau);
    const double timePhase =
        std::fmod(waveNumber * speed * timeSeconds, kTau);
    result[index] = std::fmod(distancePhase - timePhase, kTau);
  }
  return result;
}

double gerstnerWaveHeight(double worldX, double worldZ, double timeSeconds,
                           double amplitude) noexcept {
  const double shoreOffset = clamp((kShoreZ + 1.0 - worldZ) / 31.0, 0.0, 1.0);
  const double smoothOffset =
      shoreOffset * shoreOffset * (3.0 - 2.0 * shoreOffset);
  const double localAmplitude = amplitude * (0.35 + 0.65 * smoothOffset);

  double height = 0.0;
  for (const GerstnerWave& wave : kWaves) {
    const double waveNumber = kTau / wave.wavelength;
    const double speed = std::sqrt(9.8 / waveNumber) * wave.speedMultiplier;
    const Vec2 direction = wave.direction.normalized();
    const double phase = waveNumber *
                         (direction.x * worldX + direction.y * worldZ -
                          speed * timeSeconds);
    height += (wave.steepness * localAmplitude / waveNumber) * std::sin(phase);
  }
  return kSeaLevel + height;
}

double ImprovedNoise::noise(double x, double y, double z) const noexcept {
  const auto floorX = static_cast<std::int64_t>(std::floor(x));
  const auto floorY = static_cast<std::int64_t>(std::floor(y));
  const auto floorZ = static_cast<std::int64_t>(std::floor(z));

  const int X = static_cast<int>(floorX & 255);
  const int Y = static_cast<int>(floorY & 255);
  const int Z = static_cast<int>(floorZ & 255);

  x -= static_cast<double>(floorX);
  y -= static_cast<double>(floorY);
  z -= static_cast<double>(floorZ);
  const double xMinus1 = x - 1.0;
  const double yMinus1 = y - 1.0;
  const double zMinus1 = z - 1.0;
  const double u = fade(x);
  const double v = fade(y);
  const double w = fade(z);

  const int A = perm(X) + Y;
  const int AA = perm(A) + Z;
  const int AB = perm(A + 1) + Z;
  const int B = perm(X + 1) + Y;
  const int BA = perm(B) + Z;
  const int BB = perm(B + 1) + Z;

  return lerp(
      lerp(lerp(grad(perm(AA), x, y, z),
                grad(perm(BA), xMinus1, y, z), u),
           lerp(grad(perm(AB), x, yMinus1, z),
                grad(perm(BB), xMinus1, yMinus1, z), u),
           v),
      lerp(lerp(grad(perm(AA + 1), x, y, zMinus1),
                grad(perm(BA + 1), xMinus1, y, zMinus1), u),
           lerp(grad(perm(AB + 1), x, yMinus1, zMinus1),
                grad(perm(BB + 1), xMinus1, yMinus1, zMinus1), u),
           v),
      w);
}

double terrainHeight(double worldX, double worldZ) noexcept {
  if (worldZ >= 0.0) {
    const double transition = smoothstep(3.8, 28.0, worldZ);
    const double largeScale = 2.5 + 17.0 * smoothstep(16.0, 115.0, worldZ);
    const double largeNoise =
        fbm2(worldX * 0.013, worldZ * 0.013, 4, 1.3);
    const double smallNoise =
        fbm2(worldX * 0.085, worldZ * 0.085, 2, 5.1);
    return -0.06 + transition *
                       std::max(0.0, largeScale * (0.62 + 1.1 * largeNoise) +
                                         smallNoise * 1.3);
  }

  const double beachDistance = -worldZ;
  const double slope = smoothstep(3.2, 30.0, beachDistance);
  const double dunes =
      fbm2(worldX * 0.07, worldZ * 0.07, 2, 9.7) * 0.5 *
      smoothstep(3.6, 6.5, beachDistance) *
      (1.0 - smoothstep(9.0, 13.5, beachDistance));
  return -0.08 - slope * 3.9 + dunes;
}

Vec3 terrainNormal(double worldX, double worldZ, double sampleRadius) noexcept {
  const double radius = std::max(sampleRadius, 1e-6);
  const double dx = terrainHeight(worldX - radius, worldZ) -
                    terrainHeight(worldX + radius, worldZ);
  const double dz = terrainHeight(worldX, worldZ - radius) -
                    terrainHeight(worldX, worldZ + radius);
  return Vec3{dx, 2.0 * radius, dz}.normalized();
}

TwoBoneSolution solveTwoBone(const Vec3& root, const Vec3& target,
                             double firstLength, double secondLength,
                             const Vec3& pole) noexcept {
  TwoBoneSolution result;
  result.reachable = solveTwoBone(root, target, firstLength, secondLength, pole,
                                  result.mid, result.end);
  return result;
}

bool solveTwoBone(const Vec3& root, const Vec3& target, double firstLength,
                  double secondLength, const Vec3& pole, Vec3& outMid,
                  Vec3& outEnd) noexcept {
  const double first = std::max(0.0, firstLength);
  const double second = std::max(0.0, secondLength);
  Vec3 direction = target - root;
  double distance = direction.length();
  const double reach = first + second;
  const bool reachable = distance <= reach * 0.999;
  distance = clamp(distance, std::abs(first - second) + 1e-4,
                   std::max(reach * 0.999, 1e-4));
  direction = direction.normalized();

  const double denominator = 2.0 * first * distance;
  const double cosine = clamp((first * first + distance * distance -
                               second * second) /
                                  denominator,
                              -1.0, 1.0);
  const double sine = std::sqrt(std::max(0.0, 1.0 - cosine * cosine));
  Vec3 bend = pole - direction * pole.dot(direction);
  if (bend.lengthSquared() < 1e-8) {
    bend = {1.0, 0.0, 0.0};
  }
  bend = bend.normalized();
  outMid = root + direction * (first * cosine) + bend * (first * sine);
  outEnd = root + direction * distance;
  return reachable;
}

Vec3 sunDirection(double hour) noexcept {
  const double wrapped = wrapHour(hour);
  const double dayT = (wrapped - 6.0) / 12.0;
  const double nightT = std::fmod(wrapped - 18.0 + 24.0, 24.0) / 12.0;
  const double elevation =
      wrapped >= 6.0 && wrapped <= 18.0
          ? std::sin(dayT * kPi) * (66.0 * kPi / 180.0)
          : -std::sin(nightT * kPi) * 0.9;
  const double azimuth = (120.0 - dayT * 180.0) * kPi / 180.0;
  return {std::cos(elevation) * std::cos(azimuth), std::sin(elevation),
          std::cos(elevation) * std::sin(azimuth)};
}

Vec3 moonDirection(double hour) noexcept {
  const double wrapped = wrapHour(hour);
  const double nightT = std::fmod(wrapped - 18.0 + 24.0, 24.0) / 12.0;
  const double elevation =
      std::sin(clamp(nightT, 0.0, 1.0) * kPi) * 0.95 - 0.12;
  const double azimuth = (-110.0 + nightT * 150.0) * kPi / 180.0;
  return Vec3{std::cos(elevation) * std::cos(azimuth), std::sin(elevation),
              std::cos(elevation) * std::sin(azimuth)}
      .normalized();
}

double sunElevationDegrees(double hour) noexcept {
  const Vec3 direction = sunDirection(hour);
  return std::asin(clamp(direction.y, -1.0, 1.0)) * 180.0 / kPi;
}

double nightFactorForHour(double hour) noexcept {
  return smoothstep(-1.5, -11.0, sunElevationDegrees(hour));
}

}  // namespace pelican
