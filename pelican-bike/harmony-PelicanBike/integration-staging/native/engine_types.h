#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <variant>
#include <vector>

#include "pelican/simulation.hpp"
#include "pelican_audio/synthesizer.h"

namespace pelican::integration {

using SettingValue = std::variant<bool, double, std::string>;

struct EngineSettings {
    double cruise = 7.5;
    bool autopilot = true;
    bool autoGear = true;
    double hour = 17.35;
    double dayRate = 0.025;
    bool timeFlow = true;
    double cloud = 0.42;
    double waveAmp = 1.0;
    double fog = 1.0;
    std::string quality = "medium";
    bool bloom = true;
    double bloomBoost = 1.0;
    double exposure = 1.0;
    bool showFps = false;
    bool helmet = true;
    std::string glasses = "auto";
    bool scarf = true;
    bool lookMouse = true;
    double volume = 0.8;
    bool music = true;
    double musicVolume = 0.55;
};

struct HudSnapshot {
    double speedKmh = 0.0;
    double cadence = 0.0;
    int32_t gear = 3;
    int32_t gearCount = static_cast<int32_t>(kGears.size());
    double distanceKm = 0.0;
    int32_t fish = 0;
    int32_t achievements = 0;
    int32_t achievementTotal = static_cast<int32_t>(kAchievementCount);
    double hour = 17.35;
    double fps = 0.0;
    std::string quality = "medium";
    std::string camera = "cine";
    bool night = false;
    bool started = false;
    bool paused = false;
};

struct AchievementPresentation {
    Achievement achievement = Achievement::FirstFish;
    const char* id = "fish1";
    const char* icon = "🐟";
    const char* title = "第一条鱼";
    const char* detail = "张嘴就是干饭";
};

enum class BridgeEventType : std::uint8_t {
    Hud = 0,
    Toast,
    Score,
    Achievement,
    CameraFlash,
    SeaJumper,
    Screenshot,
    Error,
};

struct BridgeEvent {
    BridgeEventType type = BridgeEventType::Hud;
    HudSnapshot snapshot{};
    std::string message{};
    std::string code{};
    std::string icon{};
    std::string title{};
    std::string detail{};
    std::string achievementId{};
    double score = 0.0;
    double delta = 0.0;
    double x = 0.5;
    double y = 0.34;
    double intensity = 0.0;
    bool golden = false;
    bool success = false;
    int32_t width = 0;
    int32_t height = 0;
    std::vector<std::uint8_t> pixels{};
};

struct FrameOutput {
    GameSnapshot game{};
    std::vector<BridgeEvent> events{};
};

const AchievementPresentation& DescribeAchievement(Achievement achievement) noexcept;
CameraMode ParseCameraMode(const std::string& camera) noexcept;
std::string CameraName(CameraMode camera);
std::array<double, 2> ProjectMouthNormalized(const GameSnapshot& snapshot,
                                              double aspectRatio = 16.0 / 9.0) noexcept;
audio::Parameters MakeAudioParameters(const GameSnapshot& snapshot,
                                       const EngineSettings& settings) noexcept;

class EventRouter final {
public:
    std::vector<BridgeEvent> Route(const std::vector<GameEvent>& events,
                                   const GameSnapshot& snapshot,
                                   double aspectRatio = 16.0 / 9.0) const;
};

} // namespace pelican::integration
