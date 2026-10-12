#include "engine_types.h"

#include <algorithm>
#include <cmath>
#include <string_view>

namespace pelican::integration {
namespace {

constexpr std::array<AchievementPresentation, kAchievementCount> kAchievementPresentations{{
    {Achievement::FirstFish, "fish1", "🐟", "第一条鱼", "张嘴就是干饭"},
    {Achievement::GoldenFish, "golden", "🌟", "金色传说", "吞下了一条金鱼 (+5)"},
    {Achievement::TenFish, "fish10", "🎣", "十鱼到手", "喉囊开始沉甸甸了"},
    {Achievement::FiftyFish, "fish50", "🏆", "海岸渔王", "累计 50 条鱼"},
    {Achievement::FirstJump, "jump", "🦘", "起飞！", "第一次跳跃"},
    {Achievement::FirstTrick, "trick", "🪽", "放手特技", "展翅 + 抬前轮"},
    {Achievement::ThreeTricks, "trick3", "🎪", "杂技鹈鹕", "完成 3 次特技"},
    {Achievement::Speed30Kmh, "speed30", "💨", "时速 30", "风在耳边呼啸"},
    {Achievement::Speed45Kmh, "speed45", "⚡", "疾风鹈鹕", "时速突破 45 km/h"},
    {Achievement::OneKilometre, "km1", "🛣️", "骑行 1 公里", "海岸线才刚开始"},
    {Achievement::FiveKilometres, "km5", "🗺️", "骑行 5 公里", "真正的长途鹈鹕"},
    {Achievement::NightRide, "night", "🌙", "夜骑", "星光与路灯作伴"},
    {Achievement::TenBells, "bell10", "🔔", "铃铃铃", "按铃 10 次，路人已让开"},
    {Achievement::FirstHonk, "honk", "📢", "嘎——！", "鹈鹕的呐喊"},
}};

bool IsMilestoneAchievement(Achievement achievement) noexcept
{
    switch (achievement) {
        case Achievement::GoldenFish:
        case Achievement::TenFish:
        case Achievement::FiftyFish:
        case Achievement::ThreeTricks:
        case Achievement::Speed45Kmh:
        case Achievement::OneKilometre:
        case Achievement::FiveKilometres:
            return true;
        default:
            return false;
    }
}

Vec3 CameraPosition(const GameSnapshot& snapshot) noexcept
{
    return {snapshot.camera.localPosition.x,
            snapshot.camera.localPosition.y,
            snapshot.camera.localPosition.z};
}

Vec3 CameraLookAt(const GameSnapshot& snapshot) noexcept
{
    return {snapshot.camera.localLookAt.x,
            snapshot.camera.localLookAt.y,
            snapshot.camera.localLookAt.z};
}

} // namespace

const AchievementPresentation& DescribeAchievement(Achievement achievement) noexcept
{
    const std::size_t index = toIndex(achievement);
    return index < kAchievementPresentations.size() ? kAchievementPresentations[index]
                                                     : kAchievementPresentations.front();
}

CameraMode ParseCameraMode(const std::string& camera) noexcept
{
    if (camera == "orbit") {
        return CameraMode::Orbit;
    }
    if (camera == "chase" || camera == "follow") {
        return CameraMode::Chase;
    }
    if (camera == "side") {
        return CameraMode::Side;
    }
    if (camera == "pov" || camera == "firstPerson" || camera == "first-person") {
        return CameraMode::Pov;
    }
    return CameraMode::Cine;
}

std::string CameraName(CameraMode camera)
{
    return std::string(cameraModeId(camera));
}

std::array<double, 2> ProjectMouthNormalized(const GameSnapshot& snapshot,
                                              double aspectRatio) noexcept
{
    if (!std::isfinite(aspectRatio) || aspectRatio <= 0.0) {
        aspectRatio = 16.0 / 9.0;
    }

    const Vec3 cameraPosition = CameraPosition(snapshot);
    const Vec3 cameraTarget = CameraLookAt(snapshot);
    const Vec3 mouth{0.48, snapshot.verticalPosition + 1.24, snapshot.lane};
    const double fovRadians = clamp(static_cast<double>(snapshot.camera.verticalFovDegrees),
                                    20.0, 120.0) * kPi / 180.0;
    const Mat4 cameraWorldRotation = Mat4::lookAt(cameraPosition, cameraTarget, {0.0, 1.0, 0.0});
    Mat4 view = cameraWorldRotation.inverse();
    view.elements[12] = -(view.elements[0] * cameraPosition.x +
                          view.elements[4] * cameraPosition.y +
                          view.elements[8] * cameraPosition.z);
    view.elements[13] = -(view.elements[1] * cameraPosition.x +
                          view.elements[5] * cameraPosition.y +
                          view.elements[9] * cameraPosition.z);
    view.elements[14] = -(view.elements[2] * cameraPosition.x +
                          view.elements[6] * cameraPosition.y +
                          view.elements[10] * cameraPosition.z);
    const Mat4 projection = Mat4::perspective(fovRadians, aspectRatio, 0.05, 700.0);
    const Vec3 ndc = (projection * view).transformPoint(mouth);

    double x = ndc.x * 0.5 + 0.5;
    double y = -ndc.y * 0.5 + 0.5;
    if (!std::isfinite(x) || !std::isfinite(y) || x < -0.25 || x > 1.25 ||
        y < -0.25 || y > 1.25) {
        return {0.56, 0.34};
    }
    return {clamp(x, 0.04, 0.96), clamp(y, 0.06, 0.94)};
}

audio::Parameters MakeAudioParameters(const GameSnapshot& snapshot,
                                       const EngineSettings& settings) noexcept
{
    audio::Parameters parameters;
    parameters.speed = static_cast<float>(std::max(0.0, snapshot.speed));
    parameters.cadence = static_cast<float>(std::max(0.0, snapshot.cadenceRpm));
    parameters.night = static_cast<float>(clamp(snapshot.nightFactor, 0.0, 1.0));
    parameters.masterVolume = static_cast<float>(clamp(settings.volume, 0.0, 1.0));
    parameters.musicVolume = static_cast<float>(clamp(settings.musicVolume, 0.0, 1.0));
    parameters.effectsVolume = 1.0F;
    parameters.pedaling = snapshot.pedaling;
    parameters.airborne = snapshot.airborne;
    parameters.musicEnabled = settings.music;
    return parameters;
}

std::vector<BridgeEvent> EventRouter::Route(const std::vector<GameEvent>& events,
                                             const GameSnapshot& snapshot,
                                             double aspectRatio) const
{
    std::vector<BridgeEvent> output;
    output.reserve(events.size() * 2U);
    const std::array<double, 2> mouth = ProjectMouthNormalized(snapshot, aspectRatio);

    for (const GameEvent& event : events) {
        switch (event.type) {
            case EventType::Started: {
                BridgeEvent bridge;
                bridge.type = BridgeEventType::Toast;
                bridge.message = "出发！";
                output.push_back(std::move(bridge));
                break;
            }
            case EventType::GearChanged:
                break;
            case EventType::Jumped: {
                BridgeEvent flash;
                flash.type = BridgeEventType::CameraFlash;
                flash.intensity = 0.18;
                output.push_back(std::move(flash));
                break;
            }
            case EventType::TrickStarted: {
                BridgeEvent toast;
                toast.type = BridgeEventType::Toast;
                toast.message = "展翅特技！";
                output.push_back(std::move(toast));
                BridgeEvent flash;
                flash.type = BridgeEventType::CameraFlash;
                flash.intensity = 0.32;
                output.push_back(std::move(flash));
                break;
            }
            case EventType::BellRung: {
                BridgeEvent toast;
                toast.type = BridgeEventType::Toast;
                toast.message = "铃铃！";
                output.push_back(std::move(toast));
                break;
            }
            case EventType::Honked: {
                BridgeEvent toast;
                toast.type = BridgeEventType::Toast;
                toast.message = "嘎——！";
                output.push_back(std::move(toast));
                break;
            }
            case EventType::FishCaught: {
                const double delta = event.flag ? 5.0 : 1.0;
                BridgeEvent score;
                score.type = BridgeEventType::Score;
                score.score = static_cast<double>(event.value);
                score.delta = delta;
                score.golden = event.flag;
                score.x = mouth[0];
                score.y = mouth[1];
                output.push_back(std::move(score));

                BridgeEvent flash;
                flash.type = BridgeEventType::CameraFlash;
                flash.intensity = event.flag ? 1.0 : 0.42;
                flash.golden = event.flag;
                flash.x = mouth[0];
                flash.y = mouth[1];
                output.push_back(std::move(flash));
                break;
            }
            case EventType::AchievementUnlocked: {
                const AchievementPresentation& presentation = DescribeAchievement(event.achievement);
                BridgeEvent achievement;
                achievement.type = BridgeEventType::Achievement;
                achievement.achievementId = presentation.id;
                achievement.icon = presentation.icon;
                achievement.title = presentation.title;
                achievement.detail = presentation.detail;
                output.push_back(std::move(achievement));
                if (IsMilestoneAchievement(event.achievement)) {
                    BridgeEvent flash;
                    flash.type = BridgeEventType::CameraFlash;
                    flash.intensity = 0.85;
                    flash.golden = event.achievement == Achievement::GoldenFish;
                    flash.x = mouth[0];
                    flash.y = mouth[1];
                    output.push_back(std::move(flash));
                }
                break;
            }
            case EventType::CameraChanged:
            case EventType::Paused:
            case EventType::Resumed:
            case EventType::Landed:
            case EventType::FishSpawned:
                break;
        }
    }
    return output;
}

} // namespace pelican::integration
