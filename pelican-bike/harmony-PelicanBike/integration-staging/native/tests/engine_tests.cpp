#include "engine.h"
#include "engine_types.h"
#include "touch_tracker.h"

#include <cassert>
#include <chrono>
#include <cmath>
#include <iostream>
#include <string>
#include <vector>

namespace {

using namespace pelican;
using namespace pelican::integration;

bool HasEvent(const std::vector<BridgeEvent>& events, BridgeEventType type)
{
    for (const BridgeEvent& event : events) {
        if (event.type == type) {
            return true;
        }
    }
    return false;
}

const BridgeEvent* FindEvent(const std::vector<BridgeEvent>& events, BridgeEventType type)
{
    for (const BridgeEvent& event : events) {
        if (event.type == type) {
            return &event;
        }
    }
    return nullptr;
}

void TestAchievementPresentation()
{
    for (std::size_t index = 0; index < kAchievementCount; ++index) {
        const auto achievement = static_cast<Achievement>(index);
        const AchievementPresentation& presentation = DescribeAchievement(achievement);
        assert(presentation.achievement == achievement);
        assert(presentation.id != nullptr && std::string(presentation.id).size() > 0);
        assert(presentation.icon != nullptr && std::string(presentation.icon).size() > 0);
        assert(presentation.title != nullptr && std::string(presentation.title).size() > 0);
        assert(presentation.detail != nullptr && std::string(presentation.detail).size() > 0);
        assert(std::string(presentation.id) == achievementId(achievement));
    }
}

void TestEventRouting()
{
    GameSnapshot snapshot;
    snapshot.camera.localPosition = {-3.0F, 1.6F, 3.2F};
    snapshot.camera.localLookAt = {0.4F, 1.0F, 0.8F};
    snapshot.camera.verticalFovDegrees = 46.0F;
    snapshot.verticalPosition = 0.0;
    snapshot.lane = 0.9;

    GameEvent fish;
    fish.type = EventType::FishCaught;
    fish.value = 5;
    fish.flag = true;

    GameEvent achievement;
    achievement.type = EventType::AchievementUnlocked;
    achievement.achievement = Achievement::GoldenFish;

    EventRouter router;
    const std::vector<BridgeEvent> events = router.Route({fish, achievement}, snapshot, 16.0 / 9.0);
    const BridgeEvent* score = FindEvent(events, BridgeEventType::Score);
    assert(score != nullptr);
    assert(score->score == 5.0);
    assert(score->delta == 5.0);
    assert(score->golden);
    assert(score->x >= 0.0 && score->x <= 1.0);
    assert(score->y >= 0.0 && score->y <= 1.0);

    const BridgeEvent* unlocked = FindEvent(events, BridgeEventType::Achievement);
    assert(unlocked != nullptr);
    assert(unlocked->achievementId == "golden");
    assert(unlocked->title == "金色传说");
    assert(HasEvent(events, BridgeEventType::CameraFlash));
}

void TestEngineCommandsAndSettings()
{
    Engine engine;
    EngineSettings settings;
    settings.timeFlow = false;
    settings.hour = 17.35;
    engine.Initialize(settings);
    assert(engine.Start(false));
    assert(!engine.audioRunning());

    engine.SetInput("up", true);
    for (int frame = 0; frame < 120; ++frame) {
        (void)engine.Advance(1.0 / 60.0, 16.0 / 9.0);
    }
    engine.SetInput("up", false);
    HudSnapshot hud = engine.Snapshot(60.0);
    assert(hud.started);
    assert(hud.speedKmh > 0.0);
    assert(hud.gear >= 1 && hud.gear <= hud.gearCount);

    engine.TriggerAction("jump");
    const FrameOutput jumped = engine.Advance(1.0 / 60.0, 16.0 / 9.0);
    assert(HasEvent(jumped.events, BridgeEventType::CameraFlash));
    assert(engine.Snapshot(60.0).achievements >= 1);

    assert(engine.SetSetting("quality", std::string("high")));
    assert(engine.SetSetting("volume", 0.25));
    assert(engine.SetSetting("music", false));
    assert(engine.SetSetting("glasses", std::string("off")));
    assert(!engine.SetSetting("unknown-setting", true));
    assert(engine.settings().quality == "high");
    assert(std::abs(engine.settings().volume - 0.25) < 1e-12);
    assert(!engine.settings().music);
    assert(engine.settings().glasses == "off");

    engine.TriggerAction("night");
    assert(std::abs(engine.Snapshot(60.0).hour - 20.35) < 1e-6);
    engine.TriggerAction("flow");
    assert(engine.settings().timeFlow);

    engine.SetPaused(true);
    assert(engine.Snapshot(60.0).paused);
    engine.SetPaused(false);
    assert(!engine.Snapshot(60.0).paused);
    engine.Dispose();
}

class TouchSink final : public SurfaceInputSink {
public:
    bool IsOrbitCamera() const override { return orbit; }
    void SwitchToOrbitCamera() override { orbit = true; ++switches; }
    void OrbitDrag(float dxNormalized, float dyNormalized) override
    {
        dragX += dxNormalized;
        dragY += dyNormalized;
        ++drags;
    }
    void OrbitZoom(float scaleDelta) override
    {
        lastScale = scaleDelta;
        ++zooms;
    }
    void Pick(float normalizedX, float normalizedY) override
    {
        pickX = normalizedX;
        pickY = normalizedY;
        ++picks;
    }

    bool orbit = false;
    int switches = 0;
    int drags = 0;
    int zooms = 0;
    int picks = 0;
    float dragX = 0.0F;
    float dragY = 0.0F;
    float lastScale = 1.0F;
    float pickX = 0.0F;
    float pickY = 0.0F;
};

TouchSample OnePoint(TouchAction action, int id, float x, float y, bool pressed)
{
    TouchSample sample;
    sample.action = action;
    sample.changedId = id;
    sample.pointCount = 1;
    sample.points[0] = {id, x, y, pressed};
    return sample;
}

void TestSteadyTouchTracking()
{
    TouchTracker tracker;
    TouchSink sink;
    const auto t0 = TouchTracker::Clock::time_point{} + std::chrono::seconds(10);

    tracker.Process(OnePoint(TouchAction::Down, 1, 20.0F, 30.0F, true), 200, 100, sink, t0);
    tracker.Process(OnePoint(TouchAction::Up, 1, 20.0F, 30.0F, false), 200, 100, sink,
                    t0 + std::chrono::milliseconds(100));
    assert(sink.picks == 1);
    assert(std::abs(sink.pickX - 0.1F) < 1e-6F);
    assert(std::abs(sink.pickY - 0.3F) < 1e-6F);

    tracker.Process(OnePoint(TouchAction::Down, 2, 20.0F, 30.0F, true), 200, 100, sink, t0);
    tracker.Process(OnePoint(TouchAction::Move, 2, 60.0F, 30.0F, true), 200, 100, sink,
                    t0 + std::chrono::milliseconds(30));
    assert(sink.switches == 1);
    assert(sink.drags >= 1);

    tracker.Reset();
    TouchSample down;
    down.action = TouchAction::Down;
    down.changedId = 3;
    down.pointCount = 2;
    down.points[0] = {3, 50.0F, 50.0F, true};
    down.points[1] = {4, 100.0F, 50.0F, true};
    tracker.Process(down, 200, 100, sink, t0);
    TouchSample move = down;
    move.action = TouchAction::Move;
    move.points[1].x = 125.0F;
    tracker.Process(move, 200, 100, sink, t0 + std::chrono::milliseconds(16));
    assert(sink.zooms == 1);
    assert(std::abs(sink.lastScale - 1.5F) < 1e-5F);
}

} // namespace

int main()
{
    TestAchievementPresentation();
    TestEventRouting();
    TestEngineCommandsAndSettings();
    TestSteadyTouchTracking();
    std::cout << "pelican_engine_tests: PASS\n";
    return 0;
}
