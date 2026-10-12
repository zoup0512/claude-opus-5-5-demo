#pragma once

#include <array>
#include <cstddef>

#include "pelican/math.hpp"

namespace pelican {

inline constexpr double kSeaLevel = -1.6;
inline constexpr double kShoreZ = -14.6;

struct GerstnerWave {
  Vec2 direction{};
  double steepness{0.0};
  double wavelength{1.0};
  double speedMultiplier{1.0};
};

inline constexpr std::size_t kWaveCount = 5;
[[nodiscard]] const std::array<GerstnerWave, kWaveCount>& oceanWaves() noexcept;
// Source-parity phase: equivalent to ocean.js' single expression before `% TAU`.
[[nodiscard]] std::array<double, kWaveCount> gerstnerWavePhasesSourceParity(
    double distance, double timeSeconds) noexcept;
// Stable phase for production long-distance rendering: reduces the distance and
// time terms independently before combining them, all in binary64.
[[nodiscard]] std::array<double, kWaveCount> gerstnerWavePhases(
    double distance, double timeSeconds) noexcept;
[[nodiscard]] double gerstnerWaveHeight(double worldX, double worldZ,
                                        double timeSeconds,
                                        double amplitude = 1.0) noexcept;

class ImprovedNoise {
 public:
  [[nodiscard]] double noise(double x, double y, double z) const noexcept;
};

[[nodiscard]] double terrainHeight(double worldX, double worldZ) noexcept;
[[nodiscard]] Vec3 terrainNormal(double worldX, double worldZ,
                                 double sampleRadius = 0.6) noexcept;

struct TwoBoneSolution {
  Vec3 mid{};
  Vec3 end{};
  bool reachable{false};
};

[[nodiscard]] TwoBoneSolution solveTwoBone(const Vec3& root, const Vec3& target,
                                           double firstLength,
                                           double secondLength,
                                           const Vec3& pole) noexcept;
[[nodiscard]] bool solveTwoBone(const Vec3& root, const Vec3& target,
                                double firstLength, double secondLength,
                                const Vec3& pole, Vec3& outMid,
                                Vec3& outEnd) noexcept;

[[nodiscard]] Vec3 sunDirection(double hour) noexcept;
[[nodiscard]] Vec3 moonDirection(double hour) noexcept;
[[nodiscard]] double sunElevationDegrees(double hour) noexcept;
[[nodiscard]] double nightFactorForHour(double hour) noexcept;

}  // namespace pelican
