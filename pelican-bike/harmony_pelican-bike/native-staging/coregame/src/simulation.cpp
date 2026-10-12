#include "pelican/simulation.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

namespace pelican {
namespace {

constexpr std::size_t kMaxCatchUpSteps = 4;
constexpr double kMaxFrameDelta = kFixedStepSeconds * kMaxCatchUpSteps;
constexpr double kTrickDuration = 3.4;
constexpr double kCatchAnimationDuration = 0.16;
constexpr double kLaneMinimum = -2.15;
constexpr double kLaneMaximum = 2.15;
constexpr double kMaximumSpeed = 15.5;

struct CineShot {
  double duration;
  bool pov;
};

constexpr std::array<CineShot, 8> kCineShots{{
    {6.5, false}, {6.0, false}, {5.0, false}, {7.0, false},
    {6.0, false}, {5.0, true},  {6.5, false}, {5.5, false},
}};

[[nodiscard]] double wrap24(double hour) noexcept {
  const double value = std::fmod(hour, 24.0);
  return value < 0.0 ? value + 24.0 : value;
}

[[nodiscard]] float narrowFloat(double value) noexcept {
  if (value > static_cast<double>(std::numeric_limits<float>::max())) {
    return std::numeric_limits<float>::max();
  }
  if (value < -static_cast<double>(std::numeric_limits<float>::max())) {
    return -std::numeric_limits<float>::max();
  }
  return static_cast<float>(value);
}

[[nodiscard]] LocalVec3f toLocalFloat(const Vec3& value) noexcept {
  return {narrowFloat(value.x), narrowFloat(value.y), narrowFloat(value.z)};
}

[[nodiscard]] Vec3 focusFor(const GameState& state) noexcept {
  return {0.05, state.verticalPosition + 0.92, state.lane};
}

[[nodiscard]] Vec3 cinePosition(std::uint32_t shot, double u,
                                const Vec3& focus) noexcept {
  switch (shot % kCineShots.size()) {
    case 0:
      return focus + Vec3{lerp(-2.6, 1.4, u), -0.5, 2.0};
    case 1:
      return focus + Vec3{7.5 - u * 1.2, -0.05, -1.1 + u * 0.5};
    case 2:
      return focus + Vec3{-0.2 + u * 0.3, -0.5, 0.95};
    case 3:
      return focus + Vec3{-4.5 + u * 2.5, 1.4 + u * 5.0, 5.0 - u * 1.8};
    case 4:
      return focus + Vec3{2.2 - u * 3.0, 0.1, -3.4};
    case 6: {
      const double angle = u * 1.6 + 0.4;
      return focus + Vec3{std::cos(angle) * 3.2, 2.6,
                          std::sin(angle) * 3.2};
    }
    case 7:
      return focus + Vec3{1.6, 1.6 - u * 0.4, 0.35};
    default:
      return focus + Vec3{0.07, 0.05, 0.0};
  }
}

[[nodiscard]] Vec3 cineLook(std::uint32_t shot, const Vec3& focus) noexcept {
  switch (shot % kCineShots.size()) {
    case 0:
      return focus + Vec3{0.25, -0.1, 0.0};
    case 1:
      return focus + Vec3{0.05, 0.35, 0.0};
    case 2:
      return focus + Vec3{-0.3, -0.55, 0.05};
    case 3:
      return focus + Vec3{0.3, -0.2, 0.0};
    case 4:
      return focus + Vec3{0.0, 0.25, 0.0};
    case 6:
      return focus + Vec3{0.2, 0.1, 0.0};
    case 7:
      return focus + Vec3{-0.2, 0.35, 0.0};
    default:
      return focus + Vec3{1.2, -0.12, 0.0};
  }
}

[[nodiscard]] double cineFov(std::uint32_t shot) noexcept {
  constexpr std::array<double, 8> values{{38.0, 17.0, 34.0, 40.0,
                                          30.0, 68.0, 36.0, 55.0}};
  return values[shot % values.size()];
}

}  // namespace

std::string_view achievementId(Achievement value) noexcept {
  constexpr std::array<std::string_view, kAchievementCount> ids{{
      "fish1",  "golden", "fish10", "fish50", "jump",   "trick",
      "trick3", "speed30", "speed45", "km1",   "km5",    "night",
      "bell10", "honk",
  }};
  const std::size_t index = toIndex(value);
  return index < ids.size() ? ids[index] : std::string_view{};
}

std::string_view cameraModeId(CameraMode value) noexcept {
  constexpr std::array<std::string_view, kCameraModeCount> ids{{
      "orbit", "chase", "side", "cine", "pov"}};
  const std::size_t index = static_cast<std::size_t>(value);
  return index < ids.size() ? ids[index] : std::string_view{};
}

GameSimulation::GameSimulation(const Settings& settings,
                               std::uint32_t gameplaySeed,
                               std::uint32_t visualSeed) {
  reset(settings, gameplaySeed, visualSeed);
}

void GameSimulation::reset(const Settings& settings,
                           std::uint32_t gameplaySeed,
                           std::uint32_t visualSeed) {
  settings_ = settings;
  state_ = GameState{};
  state_.speed = settings_.cruiseSpeed * 0.6;
  state_.hour = wrap24(settings_.hour);
  state_.camera.mode = CameraMode::Cine;
  gameplayRandom_.seed(gameplaySeed);
  visualRandom_.seed(visualSeed);
  accumulator_ = 0.0;
  nextEventSequence_ = 1U;
  events_.clear();
  updateDayNight();
  updateCamera();
}

std::size_t GameSimulation::advance(double realDeltaSeconds,
                                    const InputState& input) {
  applyCommands(input);
  if (!state_.started || state_.paused) {
    accumulator_ = 0.0;
    return 0U;
  }

  const double acceptedDelta = clamp(realDeltaSeconds, 0.0, kMaxFrameDelta);
  accumulator_ = std::min(accumulator_ + acceptedDelta, kMaxFrameDelta);
  std::size_t stepCount = 0U;
  while (accumulator_ + 1e-12 >= kFixedStepSeconds &&
         stepCount < kMaxCatchUpSteps) {
    simulateFixedStep(input);
    accumulator_ -= kFixedStepSeconds;
    ++stepCount;
  }
  if (stepCount == kMaxCatchUpSteps && accumulator_ >= kFixedStepSeconds) {
    accumulator_ = std::fmod(accumulator_, kFixedStepSeconds);
  }
  return stepCount;
}

void GameSimulation::step(const InputState& input) {
  applyCommands(input);
  if (!state_.started || state_.paused) {
    accumulator_ = 0.0;
    return;
  }
  simulateFixedStep(input);
}

void GameSimulation::start() {
  if (state_.started) {
    return;
  }
  state_.started = true;
  accumulator_ = 0.0;
  emit(EventType::Started);
}

void GameSimulation::setPaused(bool paused) {
  if (state_.paused == paused) {
    return;
  }
  state_.paused = paused;
  accumulator_ = 0.0;
  emit(paused ? EventType::Paused : EventType::Resumed);
}

void GameSimulation::setCameraMode(CameraMode mode) {
  if (state_.camera.mode == mode) {
    return;
  }
  state_.camera.mode = mode;
  if (mode == CameraMode::Cine) {
    state_.camera.cinematicShotTime = 0.0;
  }
  updateCamera();
  emitCameraChanged();
}

void GameSimulation::setHour(double hour) noexcept {
  settings_.hour = wrap24(hour);
  state_.hour = settings_.hour;
  updateDayNight();
}

void GameSimulation::setGameplaySeed(std::uint32_t seed) noexcept {
  gameplayRandom_.seed(seed);
}

void GameSimulation::setVisualSeed(std::uint32_t seed) noexcept {
  visualRandom_.seed(seed);
}

GameSnapshot GameSimulation::snapshot() const {
  GameSnapshot result;
  result.started = state_.started;
  result.paused = state_.paused;
  result.tick = state_.tick;
  result.time = state_.time;
  result.speed = state_.speed;
  result.speedKmh = state_.speed * 3.6;
  result.distance = state_.distance;
  result.lane = state_.lane;
  result.laneVelocity = state_.laneVelocity;
  result.lean = state_.lean;
  result.steer = state_.steer;
  result.verticalPosition = state_.verticalPosition;
  result.verticalVelocity = state_.verticalVelocity;
  result.airborne = state_.airborne;
  result.trickBlend = state_.trickBlend;
  result.wheelie = state_.wheelie;
  result.accelerationVisual = state_.accelerationVisual;
  result.pedaling = state_.pedaling;
  result.gear = state_.gear;
  result.cadenceRpm = state_.cadenceRpm;
  result.crankAngle = state_.crankAngle;
  result.wheelAngle = state_.wheelAngle;
  result.score = state_.score;
  result.fishCaught = state_.fishCaught;
  result.goldenFishCaught = state_.goldenFishCaught;
  result.jumps = state_.jumps;
  result.tricks = state_.tricks;
  result.bells = state_.bells;
  result.honks = state_.honks;
  result.achievementCount = static_cast<std::size_t>(
      std::count(state_.achievements.begin(), state_.achievements.end(), true));
  result.hour = state_.hour;
  result.sunElevationDegrees = state_.sunElevationDegrees;
  result.nightFactor = state_.nightFactor;
  result.wavePhases = gerstnerWavePhases(state_.distance, state_.time);

  result.camera.mode = state_.camera.mode;
  result.camera.localPosition = toLocalFloat(state_.camera.position);
  result.camera.localLookAt = toLocalFloat(state_.camera.lookAt);
  result.camera.verticalFovDegrees = narrowFloat(state_.camera.verticalFovDegrees);
  result.camera.cinematicShot = state_.camera.cinematicShot;
  result.camera.cinematicShotTime = narrowFloat(state_.camera.cinematicShotTime);
  result.camera.cinematicPov = state_.camera.cinematicPov;

  for (std::size_t index = 0; index < state_.fish.size(); ++index) {
    const Fish& fish = state_.fish[index];
    if (!fish.active) {
      continue;
    }
    FishSnapshot& item = result.fish[result.activeFishCount++];
    item.poolIndex = static_cast<std::uint8_t>(index);
    item.golden = fish.golden;
    item.caught = fish.caughtSeconds >= 0.0;
    Vec3 local{fish.worldX - state_.distance,
               fish.y + std::sin(state_.time * 3.0 + fish.phase) * 0.08,
               fish.lane};
    double scale = 1.35;
    if (item.caught) {
      const double u = clamp(fish.caughtSeconds / kCatchAnimationDuration,
                             0.0, 1.0);
      const Vec3 mouth = approximateMouthPosition();
      local = lerp(local, mouth, u);
      scale *= 1.0 - u * 0.9;
    }
    item.localPosition = toLocalFloat(local);
    item.phase = narrowFloat(fish.phase);
    item.scale = narrowFloat(scale);
  }
  return result;
}

std::vector<GameEvent> GameSimulation::consumeEvents() {
  std::vector<GameEvent> result;
  result.swap(events_);
  return result;
}

double GameSimulation::interpolationAlpha() const noexcept {
  return clamp(accumulator_ / kFixedStepSeconds, 0.0, 1.0);
}

std::uint32_t GameSimulation::nextVisualU32() noexcept {
  return visualRandom_.nextU32();
}

double GameSimulation::nextVisualRandom() noexcept {
  return visualRandom_.nextDouble();
}

std::uint32_t GameSimulation::gameplayRandomState() const noexcept {
  return gameplayRandom_.state();
}

std::uint32_t GameSimulation::visualRandomState() const noexcept {
  return visualRandom_.state();
}

void GameSimulation::applyCommands(const InputState& input) {
  if (input.startPressed) {
    start();
  }
  if (input.pausePressed && state_.started) {
    setPaused(!state_.paused);
  }
  if (!state_.started || state_.paused) {
    return;
  }
  if (input.gearDownPressed) {
    shiftGear(-1, false);
  }
  if (input.gearUpPressed) {
    shiftGear(1, false);
  }
  if (input.nextCameraPressed) {
    const auto current = static_cast<std::size_t>(state_.camera.mode);
    setCameraMode(static_cast<CameraMode>((current + 1U) % kCameraModeCount));
  }
  if (input.jumpPressed && !state_.airborne) {
    state_.airborne = true;
    state_.verticalVelocity = 3.6;
    ++state_.jumps;
    emit(EventType::Jumped, state_.jumps);
    unlock(Achievement::FirstJump);
  }
  if (input.trickPressed && state_.trickTimeRemaining <= 0.0) {
    state_.trickTimeRemaining = kTrickDuration;
    ++state_.tricks;
    emit(EventType::TrickStarted, state_.tricks);
    unlock(Achievement::FirstTrick);
    if (state_.tricks >= 3) {
      unlock(Achievement::ThreeTricks);
    }
  }
  if (input.bellPressed) {
    ++state_.bells;
    emit(EventType::BellRung, state_.bells);
    if (state_.bells >= 10) {
      unlock(Achievement::TenBells);
    }
  }
  if (input.honkPressed) {
    ++state_.honks;
    emit(EventType::Honked, state_.honks);
    unlock(Achievement::FirstHonk);
  }
}

void GameSimulation::simulateFixedStep(const InputState& input) {
  ++state_.tick;
  state_.time += kFixedStepSeconds;
  updateRide(input);
  updateFish();
  updateDayNight();
  updateCamera();
  updateAchievements();
}

void GameSimulation::updateRide(const InputState& input) {
  double acceleration;
  if (state_.airborne) {
    acceleration = -0.15;
  } else if (input.brake) {
    acceleration = -6.0;
  } else if (input.accelerate) {
    acceleration = 2.4;
  } else {
    acceleration = (settings_.cruiseSpeed - state_.speed) * 0.7;
  }
  if (state_.trickTimeRemaining > 0.0) {
    acceleration = std::min(acceleration, 0.2);
  }
  state_.accelerationVisual =
      damp(state_.accelerationVisual, acceleration, 6.0, kFixedStepSeconds);
  state_.speed = clamp(state_.speed + acceleration * kFixedStepSeconds, 0.0,
                       kMaximumSpeed);
  state_.pedaling = !state_.airborne && !input.brake && state_.speed > 0.25 &&
                    acceleration > -0.4;
  state_.distance += state_.speed * kFixedStepSeconds;
  state_.wheelAngle +=
      (state_.speed / kWheelRadius) * kFixedStepSeconds;

  const double wheelRpm =
      (state_.speed / kWheelRadius) * 60.0 / kTau;
  if (settings_.autoGear && state_.time - state_.lastManualGearTime > 8.0) {
    int bestGear = state_.gear;
    double bestError = std::numeric_limits<double>::max();
    for (std::size_t index = 0; index < kGears.size(); ++index) {
      const double ratio = static_cast<double>(kGears[index][0]) /
                           static_cast<double>(kGears[index][1]);
      const double cadence = wheelRpm / ratio;
      const double error = std::abs(cadence - 86.0);
      if (error < bestError) {
        bestError = error;
        bestGear = static_cast<int>(index);
      }
    }
    const auto& currentGear = kGears[static_cast<std::size_t>(state_.gear)];
    const double currentRatio = static_cast<double>(currentGear[0]) /
                                static_cast<double>(currentGear[1]);
    const double currentCadence = wheelRpm / currentRatio;
    if (bestGear != state_.gear &&
        (currentCadence > 102.0 || currentCadence < 68.0)) {
      shiftGear(bestGear > state_.gear ? 1 : -1, true);
    }
  }

  const auto& selectedGear = kGears[static_cast<std::size_t>(state_.gear)];
  const double ratio = static_cast<double>(selectedGear[0]) /
                       static_cast<double>(selectedGear[1]);
  const double crankAngularVelocity =
      state_.pedaling ? state_.speed / kWheelRadius / ratio : 0.0;
  state_.crankAngle += crankAngularVelocity * kFixedStepSeconds;
  state_.cadenceRpm = crankAngularVelocity * 60.0 / kTau;

  const int steeringInput = (input.steerRight ? 1 : 0) -
                            (input.steerLeft ? 1 : 0);
  if (steeringInput != 0) {
    state_.lastSteerTime = state_.time;
    state_.laneTarget =
        clamp(state_.laneTarget + steeringInput * 2.4 * kFixedStepSeconds,
              kLaneMinimum, kLaneMaximum);
  } else if (settings_.autopilot &&
             state_.time - state_.lastSteerTime > 4.0) {
    const Fish* target = nextFish(40.0);
    const double desired =
        target != nullptr
            ? target->lane
            : 0.9 + std::sin(state_.time * 0.23) * 0.7;
    state_.laneTarget =
        damp(state_.laneTarget, desired, target != nullptr ? 2.2 : 0.8,
             kFixedStepSeconds);
  }
  constexpr double spring = 10.0;
  state_.laneVelocity +=
      ((state_.laneTarget - state_.lane) * spring -
       state_.laneVelocity * 2.0 * std::sqrt(spring)) *
      kFixedStepSeconds;
  state_.lane += state_.laneVelocity * kFixedStepSeconds;
  state_.lateralAcceleration =
      damp(state_.lateralAcceleration,
           (state_.laneVelocity - state_.previousLaneVelocity) /
               kFixedStepSeconds,
           8.0, kFixedStepSeconds);
  state_.previousLaneVelocity = state_.laneVelocity;
  const double wobble =
      std::sin(state_.time * 1.7) * 0.02 *
      clamp(1.5 - state_.speed * 0.2, 0.2, 1.5);
  state_.lean =
      damp(state_.lean,
           clamp(std::atan(state_.lateralAcceleration / 9.8) * 1.4, -0.4,
                 0.4) +
               wobble * 0.5,
           7.0, kFixedStepSeconds);
  const double steeringTarget =
      state_.trickTimeRemaining > 0.0
          ? 0.0
          : -clamp(state_.lateralAcceleration * 0.05 +
                       state_.laneVelocity * 0.12 /
                           std::max(1.0, state_.speed * 0.3),
                   -0.35, 0.35) +
                wobble;
  state_.steer =
      damp(state_.steer, steeringTarget, 10.0, kFixedStepSeconds);

  if (state_.airborne) {
    state_.verticalVelocity -= 13.0 * kFixedStepSeconds;
    state_.verticalPosition += state_.verticalVelocity * kFixedStepSeconds;
    if (state_.verticalPosition <= 0.0) {
      state_.verticalPosition = 0.0;
      state_.verticalVelocity = 0.0;
      state_.airborne = false;
      emit(EventType::Landed);
    }
  }
  if (state_.trickTimeRemaining > 0.0) {
    state_.trickTimeRemaining =
        std::max(0.0, state_.trickTimeRemaining - kFixedStepSeconds);
  }
  state_.trickBlend =
      damp(state_.trickBlend,
           state_.trickTimeRemaining > 0.0 ? 1.0 : 0.0, 4.0,
           kFixedStepSeconds);
  const double wheelieTarget =
      state_.trickBlend * 0.3 +
      (state_.airborne ? state_.verticalVelocity * 0.025 : 0.0);
  state_.wheelie =
      damp(state_.wheelie, wheelieTarget, 6.0, kFixedStepSeconds);
}

void GameSimulation::updateFish() {
  if (state_.distance > state_.nextFishAt) {
    spawnFish(state_.nextFishAt == 30.0 ? 32.0 : 85.0);
    state_.nextFishAt =
        state_.distance + 16.0 + gameplayRandom_.nextDouble() * 18.0;
  }

  const Vec3 mouth = approximateMouthPosition();
  for (std::size_t index = 0; index < state_.fish.size(); ++index) {
    Fish& fish = state_.fish[index];
    if (!fish.active) {
      continue;
    }
    const double relativeX = fish.worldX - state_.distance;
    if (fish.caughtSeconds >= 0.0) {
      fish.caughtSeconds += kFixedStepSeconds;
      if (fish.caughtSeconds >= kCatchAnimationDuration) {
        fish.active = false;
      }
      continue;
    }
    if (relativeX < -12.0) {
      fish.active = false;
      continue;
    }
    const double animatedY =
        fish.y + std::sin(state_.time * 3.0 + fish.phase) * 0.08;
    const double dx = relativeX - mouth.x;
    const double dy = animatedY - mouth.y;
    const double dz = fish.lane - mouth.z;
    if (std::abs(dx) < 0.45 + state_.speed * kFixedStepSeconds &&
        std::abs(dz) < 0.52 && std::abs(dy) < 0.6) {
      fish.caughtSeconds = 0.0;
      ++state_.fishCaught;
      state_.score += fish.golden ? 5 : 1;
      if (fish.golden) {
        ++state_.goldenFishCaught;
      }
      emit(EventType::FishCaught, state_.score, static_cast<int>(index),
           fish.golden, Vec3{relativeX, animatedY, fish.lane});
      unlock(Achievement::FirstFish);
      if (fish.golden) {
        unlock(Achievement::GoldenFish);
      }
      if (state_.score >= 10) {
        unlock(Achievement::TenFish);
      }
      if (state_.score >= 50) {
        unlock(Achievement::FiftyFish);
      }
    }
  }
}

void GameSimulation::updateAchievements() {
  const double speedKmh = state_.speed * 3.6;
  if (speedKmh >= 30.0) {
    unlock(Achievement::Speed30Kmh);
  }
  if (speedKmh >= 45.0) {
    unlock(Achievement::Speed45Kmh);
  }
  if (state_.distance >= 1000.0) {
    unlock(Achievement::OneKilometre);
  }
  if (state_.distance >= 5000.0) {
    unlock(Achievement::FiveKilometres);
  }
  if (state_.nightFactor > 0.8 && state_.time > 5.0) {
    unlock(Achievement::NightRide);
  }
}

void GameSimulation::updateDayNight() {
  if (settings_.timeFlow && state_.started && !state_.paused) {
    settings_.hour =
        wrap24(settings_.hour + kFixedStepSeconds * settings_.dayRate);
  }
  state_.hour = wrap24(settings_.hour);
  state_.sunElevationDegrees = sunElevationDegrees(state_.hour);
  state_.nightFactor = nightFactorForHour(state_.hour);
}

void GameSimulation::updateCamera() {
  const Vec3 focus = focusFor(state_);
  CameraState& camera = state_.camera;
  const bool advanceSchedule = state_.started && !state_.paused;
  camera.cinematicPov = false;
  switch (camera.mode) {
    case CameraMode::Orbit: {
      const double angle = state_.time * 0.55;
      camera.position =
          focus + Vec3{std::cos(angle) * 4.3, 0.45,
                       std::sin(angle) * 4.3};
      camera.lookAt = focus;
      camera.verticalFovDegrees = 42.0;
      break;
    }
    case CameraMode::Chase:
      camera.position =
          focus + Vec3{-3.5, 0.7, 1.2 - state_.lane * 0.15};
      camera.lookAt = focus + Vec3{1.6, 0.05, 0.0};
      camera.verticalFovDegrees = 46.0;
      break;
    case CameraMode::Side:
      camera.position =
          focus + Vec3{0.35 + std::sin(state_.time * 0.2) * 0.5, -0.1,
                       3.3};
      camera.lookAt = focus + Vec3{0.1, -0.05, 0.0};
      camera.verticalFovDegrees = 36.0;
      break;
    case CameraMode::Pov:
      camera.position = focus + Vec3{0.45, 0.28, 0.0};
      camera.lookAt = camera.position + Vec3{1.2, -0.12, 0.0};
      camera.verticalFovDegrees = 68.0;
      break;
    case CameraMode::Cine: {
      if (advanceSchedule) {
        camera.cinematicShotTime += kFixedStepSeconds;
      }
      const CineShot* shot =
          &kCineShots[camera.cinematicShot % kCineShots.size()];
      if (camera.cinematicShotTime > shot->duration) {
        camera.cinematicShotTime = 0.0;
        camera.cinematicShot = static_cast<std::uint32_t>(
            (camera.cinematicShot + 1U) % kCineShots.size());
        shot = &kCineShots[camera.cinematicShot];
      }
      const double u =
          clamp(camera.cinematicShotTime / shot->duration, 0.0, 1.0);
      camera.cinematicPov = shot->pov;
      if (shot->pov) {
        camera.position = focus + Vec3{0.45, 0.28, 0.0};
        camera.lookAt = camera.position + Vec3{1.2, -0.12, 0.0};
      } else {
        camera.position = cinePosition(camera.cinematicShot, u, focus);
        camera.lookAt = cineLook(camera.cinematicShot, focus);
      }
      camera.verticalFovDegrees = cineFov(camera.cinematicShot);
      break;
    }
  }
}

Fish* GameSimulation::nextFish(double range) noexcept {
  Fish* best = nullptr;
  double bestRelative = range;
  for (Fish& fish : state_.fish) {
    if (!fish.active || fish.caughtSeconds >= 0.0) {
      continue;
    }
    const double relative = fish.worldX - state_.distance;
    if (relative > 0.2 && relative < bestRelative) {
      best = &fish;
      bestRelative = relative;
    }
  }
  return best;
}

const Fish* GameSimulation::nextFish(double range) const noexcept {
  const Fish* best = nullptr;
  double bestRelative = range;
  for (const Fish& fish : state_.fish) {
    if (!fish.active || fish.caughtSeconds >= 0.0) {
      continue;
    }
    const double relative = fish.worldX - state_.distance;
    if (relative > 0.2 && relative < bestRelative) {
      best = &fish;
      bestRelative = relative;
    }
  }
  return best;
}

void GameSimulation::spawnFish(double ahead) {
  auto iterator = std::find_if(state_.fish.begin(), state_.fish.end(),
                               [](const Fish& value) {
                                 return !value.active;
                               });
  if (iterator == state_.fish.end()) {
    return;
  }
  Fish& fish = *iterator;
  fish.active = true;
  fish.caughtSeconds = -1.0;
  fish.worldX = state_.distance + ahead;
  const std::size_t laneIndex = std::min(
      kFishLaneCount - 1,
      static_cast<std::size_t>(gameplayRandom_.nextDouble() *
                               static_cast<double>(kFishLaneCount)));
  fish.lane = kFishLanes[laneIndex];
  fish.y = 1.3 + gameplayRandom_.nextDouble() * 0.25;
  fish.golden = gameplayRandom_.nextDouble() < 0.12;
  fish.phase = gameplayRandom_.nextDouble() * kTau;
  const std::size_t poolIndex =
      static_cast<std::size_t>(std::distance(state_.fish.begin(), iterator));
  emit(EventType::FishSpawned, static_cast<int>(poolIndex), 0, fish.golden,
       Vec3{ahead, fish.y, fish.lane});
}

void GameSimulation::unlock(Achievement achievement) {
  if (!state_.started) {
    return;
  }
  const std::size_t index = toIndex(achievement);
  if (index >= state_.achievements.size() || state_.achievements[index]) {
    return;
  }
  state_.achievements[index] = true;
  emitAchievement(achievement);
}

void GameSimulation::emit(EventType type, int value, int secondaryValue,
                          bool flag, const Vec3& position) {
  GameEvent event;
  event.type = type;
  event.sequence = nextEventSequence_++;
  event.tick = state_.tick;
  event.time = state_.time;
  event.value = value;
  event.secondaryValue = secondaryValue;
  event.flag = flag;
  event.position = position;
  events_.push_back(event);
}

void GameSimulation::emitAchievement(Achievement achievement) {
  emit(EventType::AchievementUnlocked, static_cast<int>(toIndex(achievement)));
  events_.back().achievement = achievement;
}

void GameSimulation::emitCameraChanged() {
  emit(EventType::CameraChanged,
       static_cast<int>(static_cast<std::uint8_t>(state_.camera.mode)));
  events_.back().cameraMode = state_.camera.mode;
}

void GameSimulation::shiftGear(int direction, bool automatic) {
  const int next = clamp(state_.gear + direction, 0,
                         static_cast<int>(kGears.size()) - 1);
  if (next == state_.gear) {
    return;
  }
  state_.gear = next;
  if (!automatic) {
    state_.lastManualGearTime = state_.time;
  }
  emit(EventType::GearChanged, state_.gear, automatic ? 1 : 0, automatic);
}

Vec3 GameSimulation::approximateMouthPosition() const noexcept {
  // The renderer owns the articulated pelican rig. This anchor approximates the
  // H5 mouth world position closely enough for deterministic gameplay collision.
  return {0.48, state_.verticalPosition + 1.24, state_.lane};
}

}  // namespace pelican
