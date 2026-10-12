#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include "RenderScene.h"
#include "engine_types.h"
#include "pelican/simulation.hpp"
#include "pelican_audio/audio_engine.h"

namespace pelican::integration {

class Engine final {
public:
    Engine();
    ~Engine();

    Engine(const Engine&) = delete;
    Engine& operator=(const Engine&) = delete;

    void Initialize(const EngineSettings& settings = EngineSettings{});
    bool Start(bool withSound);
    void SetPaused(bool paused);
    void SetAudioSuspended(bool suspended);
    void SetInput(const std::string& name, bool pressed);
    void TriggerAction(const std::string& action, double x = 0.0, double y = 0.0,
                       bool hasCoordinates = false);
    void SetCamera(const std::string& camera);
    bool SetSetting(const std::string& name, const SettingValue& value);

    FrameOutput Advance(double deltaSeconds, double aspectRatio);
    HudSnapshot Snapshot(double fps) const;
    std::vector<BridgeEvent> DrainEvents();

    // RenderScene has no EGL ownership. These methods must run while the caller's
    // GLES context is current and while no other thread is using this Engine.
    bool InitializeScene(int width, int height);
    bool RebuildSceneIfNeeded(int width, int height);
    void ResizeScene(int width, int height);
    bool UpdateAndRender(const GameSnapshot& snapshot, float deltaSeconds);
    void DestroyScene();
    bool SceneInitialized() const noexcept;
    const std::string& SceneError() const noexcept;
    scene::RenderStats SceneStats() const;
    std::vector<std::uint8_t> ScreenshotPixels() const;

    void OrbitDrag(float dxNormalized, float dyNormalized);
    void OrbitZoom(float scaleDelta);
    scene::PickTarget Pick(float normalizedX, float normalizedY);

    const EngineSettings& settings() const noexcept { return settings_; }
    bool audioRunning() const noexcept;
    bool started() const noexcept { return started_; }
    bool paused() const noexcept { return paused_; }
    bool withSound() const noexcept { return withSound_; }

    void Dispose();

private:
    void ApplySettingsToSimulation(bool resetState);
    void ProcessGameEvents(const std::vector<GameEvent>& events,
                           const GameSnapshot& snapshot, double aspectRatio);
    void TriggerAudioForEvent(const GameEvent& event);
    void UpdateAudio(const GameSnapshot& snapshot, double deltaSeconds, bool force);
    scene::RenderState MakeRenderState(const GameSnapshot& snapshot,
                                       float deltaSeconds) const;
    scene::Quality SceneQuality() const noexcept;
    void QueueError(const std::string& code, const std::string& message);
    void QueueToast(const std::string& message);
    void SetPendingCommand(const std::string& action);

    EngineSettings settings_{};
    GameSimulation simulation_{};
    scene::RenderScene renderScene_{};
    std::unique_ptr<audio::AudioEngine> audioEngine_{};
    EventRouter eventRouter_{};
    InputState input_{};
    std::unordered_map<std::string, bool> continuousInputs_{};
    std::vector<BridgeEvent> pendingEvents_{};

    bool initialized_ = false;
    bool started_ = false;
    bool paused_ = false;
    bool withSound_ = false;
    bool sceneRebuildPending_ = false;
    double audioUpdateAccumulator_ = 0.0;
    double mouthPulseSeconds_ = 0.0;
};

} // namespace pelican::integration
