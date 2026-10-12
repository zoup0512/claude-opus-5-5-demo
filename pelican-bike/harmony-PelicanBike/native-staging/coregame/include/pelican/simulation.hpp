#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <vector>

#include "pelican/environment.hpp"
#include "pelican/math.hpp"
#include "pelican/random.hpp"

namespace pelican {

inline constexpr double kFixedStepSeconds = 1.0 / 60.0;
inline constexpr std::size_t kFishPoolSize = 12;
inline constexpr std::size_t kFishLaneCount = 4;
inline constexpr std::size_t kAchievementCount = 14;
inline constexpr std::size_t kCameraModeCount = 5;

inline constexpr std::array<double, kFishLaneCount> kFishLanes{
    -1.8, -0.6, 0.6, 1.8};
inline constexpr std::array<std::array<int, 2>, 5> kGears{{
    {{44, 28}}, {{44, 22}}, {{44, 18}}, {{44, 15}}, {{44, 12}},
}};
inline constexpr double kWheelRadius = 0.3;

struct Settings {
  double cruiseSpeed{7.5};
  bool autopilot{true};
  bool autoGear{true};
  double hour{17.35};
  double dayRate{0.025};
  bool timeFlow{true};
  double waveAmplitude{1.0};
};

struct InputState {
  bool accelerate{false};
  bool brake{false};
  bool steerLeft{false};
  bool steerRight{false};

  // Edge-triggered commands. The simulation consumes each true value once.
  bool startPressed{false};
  bool pausePressed{false};
  bool jumpPressed{false};
  bool trickPressed{false};
  bool bellPressed{false};
  bool honkPressed{false};
  bool gearDownPressed{false};
  bool gearUpPressed{false};
  bool nextCameraPressed{false};
};

enum class CameraMode : std::uint8_t {
  Orbit = 0,
  Chase,
  Side,
  Cine,
  Pov,
};

enum class Achievement : std::uint8_t {
  FirstFish = 0,
  GoldenFish,
  TenFish,
  FiftyFish,
  FirstJump,
  FirstTrick,
  ThreeTricks,
  Speed30Kmh,
  Speed45Kmh,
  OneKilometre,
  FiveKilometres,
  NightRide,
  TenBells,
  FirstHonk,
};

[[nodiscard]] constexpr std::size_t toIndex(Achievement value) noexcept {
  return static_cast<std::size_t>(value);
}

[[nodiscard]] std::string_view achievementId(Achievement value) noexcept;
[[nodiscard]] std::string_view cameraModeId(CameraMode value) noexcept;

struct Fish {
  bool active{false};
  bool golden{false};
  double worldX{0.0};
  double y{0.0};
  double lane{0.0};
  double phase{0.0};
  // Negative means uncaught. Non-negative is catch-animation age.
  double caughtSeconds{-1.0};
};

struct CameraState {
  CameraMode mode{CameraMode::Cine};
  Vec3 position{};
  Vec3 lookAt{};
  double verticalFovDegrees{42.0};
  std::uint32_t cinematicShot{0U};
  double cinematicShotTime{0.0};
  bool cinematicPov{false};
};

struct GameState {
  bool started{false};
  bool paused{false};
  std::uint64_t tick{0U};
  double time{0.0};

  double speed{4.5};
  double distance{0.0};
  double lane{0.9};
  double laneVelocity{0.0};
  double laneTarget{0.9};
  double previousLaneVelocity{0.0};
  double lateralAcceleration{0.0};
  double lean{0.0};
  double steer{0.0};
  double crankAngle{0.0};
  double wheelAngle{0.0};
  int gear{2};
  double verticalPosition{0.0};
  double verticalVelocity{0.0};
  bool airborne{false};
  double trickBlend{0.0};
  double trickTimeRemaining{0.0};
  double wheelie{0.0};
  double accelerationVisual{0.0};
  bool pedaling{true};
  double cadenceRpm{0.0};

  int score{0};
  int fishCaught{0};
  int goldenFishCaught{0};
  int jumps{0};
  int tricks{0};
  int bells{0};
  int honks{0};

  double lastSteerTime{-99.0};
  double lastManualGearTime{-99.0};
  double nextFishAt{30.0};

  double hour{17.35};
  double sunElevationDegrees{0.0};
  double nightFactor{0.0};

  CameraState camera{};
  std::array<Fish, kFishPoolSize> fish{};
  std::array<bool, kAchievementCount> achievements{};
};

struct LocalVec3f {
  float x{0.0F};
  float y{0.0F};
  float z{0.0F};
};

struct FishSnapshot {
  std::uint8_t poolIndex{0U};
  bool golden{false};
  bool caught{false};
  // Rider-relative render coordinates intentionally narrow to float.
  LocalVec3f localPosition{};
  float phase{0.0F};
  float scale{1.35F};
};

struct CameraSnapshot {
  CameraMode mode{CameraMode::Cine};
  LocalVec3f localPosition{};
  LocalVec3f localLookAt{};
  float verticalFovDegrees{42.0F};
  std::uint32_t cinematicShot{0U};
  float cinematicShotTime{0.0F};
  bool cinematicPov{false};
};

struct GameSnapshot {
  bool started{false};
  bool paused{false};
  std::uint64_t tick{0U};
  double time{0.0};

  double speed{0.0};
  double speedKmh{0.0};
  double distance{0.0};
  double lane{0.0};
  double laneVelocity{0.0};
  double lean{0.0};
  double steer{0.0};
  double verticalPosition{0.0};
  double verticalVelocity{0.0};
  bool airborne{false};
  double trickBlend{0.0};
  double wheelie{0.0};
  double accelerationVisual{0.0};
  bool pedaling{false};
  int gear{0};
  double cadenceRpm{0.0};
  double crankAngle{0.0};
  double wheelAngle{0.0};

  int score{0};
  int fishCaught{0};
  int goldenFishCaught{0};
  int jumps{0};
  int tricks{0};
  int bells{0};
  int honks{0};
  std::size_t achievementCount{0U};

  double hour{0.0};
  double sunElevationDegrees{0.0};
  double nightFactor{0.0};
  std::array<double, kWaveCount> wavePhases{};
  CameraSnapshot camera{};

  std::array<FishSnapshot, kFishPoolSize> fish{};
  std::size_t activeFishCount{0U};
};

enum class EventType : std::uint8_t {
  Started = 0,
  Paused,
  Resumed,
  GearChanged,
  Jumped,
  Landed,
  TrickStarted,
  BellRung,
  Honked,
  FishSpawned,
  FishCaught,
  AchievementUnlocked,
  CameraChanged,
};

struct GameEvent {
  EventType type{EventType::Started};
  std::uint64_t sequence{0U};
  std::uint64_t tick{0U};
  double time{0.0};
  int value{0};
  int secondaryValue{0};
  bool flag{false};
  Vec3 position{};
  Achievement achievement{Achievement::FirstFish};
  CameraMode cameraMode{CameraMode::Cine};
};

class GameSimulation {
 public:
  explicit GameSimulation(const Settings& settings = Settings{},
                          std::uint32_t gameplaySeed = 2024U,
                          std::uint32_t visualSeed = 0x9E3779B9U);

  void reset(const Settings& settings = Settings{},
             std::uint32_t gameplaySeed = 2024U,
             std::uint32_t visualSeed = 0x9E3779B9U);

  // Host-frame adapter. Internally advances only exact 1/60 s fixed steps.
  // Time is capped per call to prevent an unbounded catch-up spiral.
  [[nodiscard]] std::size_t advance(double realDeltaSeconds,
                                    const InputState& input);
  void step(const InputState& input);

  void start();
  void setPaused(bool paused);
  void setCameraMode(CameraMode mode);
  void setHour(double hour) noexcept;
  void setGameplaySeed(std::uint32_t seed) noexcept;
  void setVisualSeed(std::uint32_t seed) noexcept;

  [[nodiscard]] const Settings& settings() const noexcept { return settings_; }
  [[nodiscard]] Settings& mutableSettings() noexcept { return settings_; }
  [[nodiscard]] const GameState& state() const noexcept { return state_; }
  [[nodiscard]] GameSnapshot snapshot() const;
  [[nodiscard]] std::vector<GameEvent> consumeEvents();
  [[nodiscard]] double interpolationAlpha() const noexcept;

  // Renderer-only randomness. Gameplay never reads this stream.
  [[nodiscard]] std::uint32_t nextVisualU32() noexcept;
  [[nodiscard]] double nextVisualRandom() noexcept;
  [[nodiscard]] std::uint32_t gameplayRandomState() const noexcept;
  [[nodiscard]] std::uint32_t visualRandomState() const noexcept;

 private:
  void applyCommands(const InputState& input);
  void simulateFixedStep(const InputState& input);
  void updateRide(const InputState& input);
  void updateFish();
  void updateAchievements();
  void updateDayNight();
  void updateCamera();

  [[nodiscard]] Fish* nextFish(double range) noexcept;
  [[nodiscard]] const Fish* nextFish(double range) const noexcept;
  void spawnFish(double ahead);
  void unlock(Achievement achievement);
  void emit(EventType type, int value = 0, int secondaryValue = 0,
            bool flag = false, const Vec3& position = Vec3{});
  void emitAchievement(Achievement achievement);
  void emitCameraChanged();
  void shiftGear(int direction, bool automatic);
  [[nodiscard]] Vec3 approximateMouthPosition() const noexcept;

  Settings settings_{};
  GameState state_{};
  Mulberry32 gameplayRandom_{2024U};
  Mulberry32 visualRandom_{0x9E3779B9U};
  double accumulator_{0.0};
  std::uint64_t nextEventSequence_{1U};
  std::vector<GameEvent> events_{};
};

}  // namespace pelican
