#include "engine.h"

#include <algorithm>
#include <cmath>
#include <type_traits>
#include <utility>

namespace pelican::integration {
namespace {

constexpr double kAudioUpdatePeriodSeconds = 0.05;

bool GetBool(const SettingValue& value, bool& output)
{
    if (const bool* item = std::get_if<bool>(&value)) {
        output = *item;
        return true;
    }
    return false;
}

bool GetNumber(const SettingValue& value, double& output)
{
    if (const double* item = std::get_if<double>(&value); item != nullptr && std::isfinite(*item)) {
        output = *item;
        return true;
    }
    return false;
}

bool GetString(const SettingValue& value, std::string& output)
{
    if (const std::string* item = std::get_if<std::string>(&value)) {
        output = *item;
        return true;
    }
    return false;
}

std::string NormalizeQuality(const std::string& quality)
{
    if (quality == "low" || quality == "medium" || quality == "high" || quality == "ultra") {
        return quality;
    }
    return "medium";
}

std::string NormalizeGlasses(const std::string& glasses)
{
    if (glasses == "auto" || glasses == "on" || glasses == "off") {
        return glasses;
    }
    return "auto";
}

} // namespace

Engine::Engine() = default;

Engine::~Engine()
{
    // GL resources are deliberately not destroyed from the destructor because a
    // context may not be current. Surface/Dispose integration calls DestroyScene.
    if (audioEngine_ != nullptr) {
        audioEngine_->stop();
    }
}

void Engine::Initialize(const EngineSettings& settings)
{
    if (audioEngine_ != nullptr) {
        audioEngine_->stop();
        audioEngine_.reset();
    }
    settings_ = settings;
    settings_.quality = NormalizeQuality(settings_.quality);
    settings_.glasses = NormalizeGlasses(settings_.glasses);
    settings_.cruise = clamp(settings_.cruise, 0.0, 14.0);
    settings_.hour = std::fmod(settings_.hour, 24.0);
    if (settings_.hour < 0.0) {
        settings_.hour += 24.0;
    }
    settings_.dayRate = clamp(settings_.dayRate, 0.0, 0.5);
    settings_.cloud = clamp(settings_.cloud, 0.0, 1.0);
    settings_.waveAmp = clamp(settings_.waveAmp, 0.0, 2.2);
    settings_.fog = clamp(settings_.fog, 0.0, 3.0);
    settings_.bloomBoost = clamp(settings_.bloomBoost, 0.0, 3.0);
    settings_.exposure = clamp(settings_.exposure, 0.4, 2.0);
    settings_.volume = clamp(settings_.volume, 0.0, 1.0);
    settings_.musicVolume = clamp(settings_.musicVolume, 0.0, 1.0);

    started_ = false;
    paused_ = false;
    withSound_ = false;
    initialized_ = true;
    sceneRebuildPending_ = renderScene_.initialized();
    audioUpdateAccumulator_ = 0.0;
    mouthPulseSeconds_ = 0.0;
    input_ = {};
    continuousInputs_.clear();
    pendingEvents_.clear();
    ApplySettingsToSimulation(true);
}

bool Engine::Start(bool withSound)
{
    if (!initialized_) {
        Initialize();
    }
    if (started_) {
        if (!withSound && audioEngine_ != nullptr) {
            audioEngine_->stop();
            audioEngine_.reset();
            withSound_ = false;
        }
        return true;
    }

    withSound_ = withSound;
    if (withSound_) {
        audioEngine_ = std::make_unique<audio::AudioEngine>();
        if (!audioEngine_->start()) {
            audioEngine_.reset();
            withSound_ = false;
            QueueError("AUDIO_START", "无法启动 OHAudio，游戏将静音继续");
        }
    }

    simulation_.start();
    started_ = true;
    paused_ = false;
    ProcessGameEvents(simulation_.consumeEvents(), simulation_.snapshot(), 16.0 / 9.0);
    UpdateAudio(simulation_.snapshot(), 0.0, true);
    return true;
}

void Engine::SetPaused(bool paused)
{
    paused_ = paused;
    simulation_.setPaused(paused);
    if (audioEngine_ != nullptr) {
        audioEngine_->setPaused(paused);
    }
    ProcessGameEvents(simulation_.consumeEvents(), simulation_.snapshot(), 16.0 / 9.0);
}

void Engine::SetAudioSuspended(bool suspended)
{
    if (audioEngine_ != nullptr) {
        audioEngine_->setPaused(suspended);
    }
}

void Engine::SetInput(const std::string& name, bool pressed)
{
    continuousInputs_[name] = pressed;
    if (name == "left") {
        input_.steerLeft = pressed;
    } else if (name == "right") {
        input_.steerRight = pressed;
    } else if (name == "up" || name == "pedal" || name == "accelerate") {
        input_.accelerate = pressed;
    } else if (name == "down" || name == "brake") {
        input_.brake = pressed;
    }
}

void Engine::SetPendingCommand(const std::string& action)
{
    if (action == "jump") {
        input_.jumpPressed = true;
    } else if (action == "trick") {
        input_.trickPressed = true;
    } else if (action == "bell") {
        input_.bellPressed = true;
    } else if (action == "honk") {
        input_.honkPressed = true;
    }
}

void Engine::TriggerAction(const std::string& action, double x, double y, bool hasCoordinates)
{
    if (action == "jump" || action == "trick" || action == "bell" || action == "honk") {
        SetPendingCommand(action);
        return;
    }
    if (action == "night") {
        settings_.hour = std::fmod(settings_.hour + 3.0, 24.0);
        simulation_.setHour(settings_.hour);
        return;
    }
    if (action == "flow") {
        settings_.timeFlow = !settings_.timeFlow;
        simulation_.mutableSettings().timeFlow = settings_.timeFlow;
        QueueToast(settings_.timeFlow ? "时间流动已开启" : "时间已冻结");
        return;
    }
    if (action == "pick" && hasCoordinates) {
        (void)Pick(static_cast<float>(x), static_cast<float>(y));
        return;
    }
}

void Engine::SetCamera(const std::string& camera)
{
    simulation_.setCameraMode(ParseCameraMode(camera));
    ProcessGameEvents(simulation_.consumeEvents(), simulation_.snapshot(), 16.0 / 9.0);
}

bool Engine::SetSetting(const std::string& name, const SettingValue& value)
{
    bool boolean = false;
    double number = 0.0;
    std::string text;

    if (name == "cruise" && GetNumber(value, number)) {
        settings_.cruise = clamp(number, 0.0, 14.0);
        simulation_.mutableSettings().cruiseSpeed = settings_.cruise;
    } else if (name == "autopilot" && GetBool(value, boolean)) {
        settings_.autopilot = boolean;
        simulation_.mutableSettings().autopilot = boolean;
    } else if (name == "autoGear" && GetBool(value, boolean)) {
        settings_.autoGear = boolean;
        simulation_.mutableSettings().autoGear = boolean;
    } else if (name == "hour" && GetNumber(value, number)) {
        settings_.hour = std::fmod(number, 24.0);
        if (settings_.hour < 0.0) settings_.hour += 24.0;
        simulation_.setHour(settings_.hour);
    } else if (name == "night" && GetBool(value, boolean)) {
        settings_.hour = boolean ? 23.0 : 12.0;
        simulation_.setHour(settings_.hour);
    } else if (name == "dayRate" && GetNumber(value, number)) {
        settings_.dayRate = clamp(number, 0.0, 0.5);
        simulation_.mutableSettings().dayRate = settings_.dayRate;
    } else if (name == "timeFlow" && GetBool(value, boolean)) {
        settings_.timeFlow = boolean;
        simulation_.mutableSettings().timeFlow = boolean;
    } else if (name == "cloud" && GetNumber(value, number)) {
        settings_.cloud = clamp(number, 0.0, 1.0);
    } else if ((name == "waveAmp" || name == "waveAmplitude") && GetNumber(value, number)) {
        settings_.waveAmp = clamp(number, 0.0, 2.2);
        simulation_.mutableSettings().waveAmplitude = settings_.waveAmp;
    } else if (name == "fog" && GetNumber(value, number)) {
        // RenderScene currently uses a fixed shader fog density; retain the exact
        // public value so the future scene hook does not require a bridge change.
        settings_.fog = clamp(number, 0.0, 3.0);
    } else if (name == "quality" && GetString(value, text)) {
        text = NormalizeQuality(text);
        if (settings_.quality != text) {
            settings_.quality = text;
            sceneRebuildPending_ = true;
        }
    } else if (name == "bloom" && GetBool(value, boolean)) {
        // Staging RenderScene ties bloom allocation to quality. Store this switch;
        // quality still controls actual FBO construction until scene exposes it.
        settings_.bloom = boolean;
    } else if (name == "bloomBoost" && GetNumber(value, number)) {
        settings_.bloomBoost = clamp(number, 0.0, 3.0);
    } else if (name == "exposure" && GetNumber(value, number)) {
        settings_.exposure = clamp(number, 0.4, 2.0);
    } else if (name == "showFps" && GetBool(value, boolean)) {
        settings_.showFps = boolean;
    } else if (name == "helmet" && GetBool(value, boolean)) {
        settings_.helmet = boolean;
    } else if (name == "glasses" && GetString(value, text)) {
        settings_.glasses = NormalizeGlasses(text);
    } else if (name == "scarf" && GetBool(value, boolean)) {
        // Staging scene always simulates/draws the scarf. Preserve the setting and
        // pass it through RenderState when the upstream scene gains visibility flags.
        settings_.scarf = boolean;
    } else if (name == "lookMouse" && GetBool(value, boolean)) {
        settings_.lookMouse = boolean;
    } else if (name == "volume" && GetNumber(value, number)) {
        settings_.volume = clamp(number, 0.0, 1.0);
        EnsureAudioStarted();
        UpdateAudio(simulation_.snapshot(), 0.0, true);
    } else if (name == "music" && GetBool(value, boolean)) {
        settings_.music = boolean;
        if (boolean) {
            EnsureAudioStarted();
        }
        UpdateAudio(simulation_.snapshot(), 0.0, true);
    } else if (name == "musicVolume" && GetNumber(value, number)) {
        settings_.musicVolume = clamp(number, 0.0, 1.0);
        EnsureAudioStarted();
        UpdateAudio(simulation_.snapshot(), 0.0, true);
    } else {
        return false;
    }
    return true;
}

void Engine::EnsureAudioStarted()
{
    // Mirrors the web build: a silent start creates no audio context, but the
    // first volume/music interaction after starting creates one on demand.
    if (!started_ || audioEngine_ != nullptr) {
        return;
    }
    audioEngine_ = std::make_unique<audio::AudioEngine>();
    if (!audioEngine_->start()) {
        audioEngine_.reset();
        QueueError("AUDIO_START", "无法启动 OHAudio，游戏将静音继续");
        return;
    }
    withSound_ = true;
    audioEngine_->setPaused(paused_);
    UpdateAudio(simulation_.snapshot(), 0.0, true);
}

FrameOutput Engine::Advance(double deltaSeconds, double aspectRatio)
{
    FrameOutput output;
    if (!initialized_) {
        output.game = simulation_.snapshot();
        output.events = DrainEvents();
        return output;
    }

    const double clampedDelta = clamp(deltaSeconds, 0.0, 0.1);
    mouthPulseSeconds_ = std::max(0.0, mouthPulseSeconds_ - clampedDelta);
    const std::size_t advancedSteps = simulation_.advance(clampedDelta, input_);
    (void)advancedSteps;
    input_.startPressed = false;
    input_.pausePressed = false;
    input_.jumpPressed = false;
    input_.trickPressed = false;
    input_.bellPressed = false;
    input_.honkPressed = false;
    input_.gearDownPressed = false;
    input_.gearUpPressed = false;
    input_.nextCameraPressed = false;

    output.game = simulation_.snapshot();
    const std::vector<GameEvent> gameEvents = simulation_.consumeEvents();
    ProcessGameEvents(gameEvents, output.game, aspectRatio);
    UpdateAudio(output.game, clampedDelta, false);
    output.events = DrainEvents();
    return output;
}

HudSnapshot Engine::Snapshot(double fps) const
{
    const GameSnapshot game = simulation_.snapshot();
    HudSnapshot snapshot;
    snapshot.speedKmh = game.speedKmh;
    snapshot.cadence = game.cadenceRpm;
    snapshot.gear = static_cast<int32_t>(game.gear + 1);
    snapshot.gearCount = static_cast<int32_t>(kGears.size());
    snapshot.distanceKm = game.distance / 1000.0;
    snapshot.fish = game.score;
    snapshot.achievements = static_cast<int32_t>(game.achievementCount);
    snapshot.achievementTotal = static_cast<int32_t>(kAchievementCount);
    snapshot.hour = game.hour;
    snapshot.fps = fps;
    snapshot.quality = settings_.quality;
    snapshot.camera = CameraName(game.camera.mode);
    snapshot.night = game.nightFactor > 0.5;
    snapshot.started = started_;
    snapshot.paused = paused_;
    return snapshot;
}

std::vector<BridgeEvent> Engine::DrainEvents()
{
    std::vector<BridgeEvent> events;
    events.swap(pendingEvents_);
    return events;
}

bool Engine::InitializeScene(int width, int height)
{
    sceneRebuildPending_ = false;
    if (!renderScene_.initialize(width, height, SceneQuality())) {
        QueueError("SCENE_INIT", renderScene_.lastError());
        return false;
    }
    return true;
}

bool Engine::RebuildSceneIfNeeded(int width, int height)
{
    if (!sceneRebuildPending_) {
        return true;
    }
    sceneRebuildPending_ = false;
    renderScene_.destroy();
    if (!renderScene_.initialize(width, height, SceneQuality())) {
        QueueError("SCENE_REBUILD", renderScene_.lastError());
        return false;
    }
    return true;
}

void Engine::ResizeScene(int width, int height)
{
    if (renderScene_.initialized()) {
        renderScene_.resize(width, height);
    }
}

bool Engine::UpdateAndRender(const GameSnapshot& snapshot, float deltaSeconds)
{
    if (!renderScene_.initialized()) {
        return false;
    }
    renderScene_.update(MakeRenderState(snapshot, deltaSeconds));
    renderScene_.render();
    return true;
}

void Engine::DestroyScene()
{
    renderScene_.destroy();
}

bool Engine::SceneInitialized() const noexcept
{
    return renderScene_.initialized();
}

const std::string& Engine::SceneError() const noexcept
{
    return renderScene_.lastError();
}

scene::RenderStats Engine::SceneStats() const
{
    return renderScene_.stats();
}

std::vector<std::uint8_t> Engine::ScreenshotPixels() const
{
    return renderScene_.screenshotPixels();
}

void Engine::OrbitDrag(float dxNormalized, float dyNormalized)
{
    if (renderScene_.initialized()) {
        renderScene_.orbitDrag(dxNormalized, dyNormalized);
    }
}

void Engine::OrbitZoom(float scaleDelta)
{
    if (renderScene_.initialized()) {
        renderScene_.orbitZoom(scaleDelta);
    }
}

scene::PickTarget Engine::Pick(float normalizedX, float normalizedY)
{
    const scene::PickTarget target = renderScene_.initialized()
        ? renderScene_.pick(normalizedX, normalizedY)
        : scene::PickTarget::None;
    switch (target) {
        case scene::PickTarget::Bell:
        case scene::PickTarget::Bicycle:
            SetPendingCommand("bell");
            break;
        case scene::PickTarget::Pelican:
            SetPendingCommand("honk");
            break;
        case scene::PickTarget::Sea: {
            BridgeEvent jumper;
            jumper.type = BridgeEventType::SeaJumper;
            jumper.x = clamp(static_cast<double>(normalizedX), 0.0, 1.0);
            jumper.y = clamp(static_cast<double>(normalizedY), 0.0, 1.0);
            pendingEvents_.push_back(std::move(jumper));
            if (audioEngine_ != nullptr) {
                audioEngine_->trigger(audio::Event::Splash);
            }
            break;
        }
        case scene::PickTarget::None:
            break;
    }
    return target;
}

bool Engine::audioRunning() const noexcept
{
    return audioEngine_ != nullptr && audioEngine_->isRunning();
}

void Engine::Dispose()
{
    if (audioEngine_ != nullptr) {
        audioEngine_->stop();
        audioEngine_.reset();
    }
    initialized_ = false;
    started_ = false;
    paused_ = true;
    withSound_ = false;
    sceneRebuildPending_ = false;
    audioUpdateAccumulator_ = 0.0;
    mouthPulseSeconds_ = 0.0;
    input_ = {};
    continuousInputs_.clear();
    pendingEvents_.clear();
}

void Engine::ApplySettingsToSimulation(bool resetState)
{
    Settings simulationSettings;
    simulationSettings.cruiseSpeed = settings_.cruise;
    simulationSettings.autopilot = settings_.autopilot;
    simulationSettings.autoGear = settings_.autoGear;
    simulationSettings.hour = settings_.hour;
    simulationSettings.dayRate = settings_.dayRate;
    simulationSettings.timeFlow = settings_.timeFlow;
    simulationSettings.waveAmplitude = settings_.waveAmp;
    if (resetState) {
        simulation_.reset(simulationSettings);
    } else {
        simulation_.mutableSettings() = simulationSettings;
        simulation_.setHour(settings_.hour);
    }
}

void Engine::ProcessGameEvents(const std::vector<GameEvent>& events,
                               const GameSnapshot& snapshot, double aspectRatio)
{
    for (const GameEvent& event : events) {
        TriggerAudioForEvent(event);
        if (event.type == EventType::FishCaught || event.type == EventType::Honked) {
            mouthPulseSeconds_ = 0.34;
        }
    }
    std::vector<BridgeEvent> bridgeEvents = eventRouter_.Route(events, snapshot, aspectRatio);
    pendingEvents_.insert(pendingEvents_.end(),
                          std::make_move_iterator(bridgeEvents.begin()),
                          std::make_move_iterator(bridgeEvents.end()));
}

void Engine::TriggerAudioForEvent(const GameEvent& event)
{
    if (audioEngine_ == nullptr) {
        return;
    }
    switch (event.type) {
        case EventType::BellRung:
            audioEngine_->trigger(audio::Event::Bell);
            break;
        case EventType::Honked:
            audioEngine_->trigger(audio::Event::Honk);
            break;
        case EventType::FishCaught:
            audioEngine_->trigger(event.flag ? audio::Event::GulpGolden : audio::Event::Gulp);
            break;
        case EventType::Jumped:
            audioEngine_->trigger(audio::Event::Whoosh);
            break;
        case EventType::TrickStarted:
            // Web build plays both the jump whoosh and the pelican honk for a trick.
            audioEngine_->trigger(audio::Event::Whoosh);
            audioEngine_->trigger(audio::Event::Honk);
            break;
        case EventType::Landed:
            audioEngine_->trigger(audio::Event::Thump);
            break;
        default:
            break;
    }
}

void Engine::UpdateAudio(const GameSnapshot& snapshot, double deltaSeconds, bool force)
{
    if (audioEngine_ == nullptr) {
        return;
    }
    audioUpdateAccumulator_ += std::max(0.0, deltaSeconds);
    if (!force && audioUpdateAccumulator_ < kAudioUpdatePeriodSeconds) {
        return;
    }
    audioUpdateAccumulator_ = 0.0;
    audioEngine_->update(MakeAudioParameters(snapshot, settings_));
}

scene::RenderState Engine::MakeRenderState(const GameSnapshot& snapshot,
                                           float deltaSeconds) const
{
    scene::RenderState state;
    state.totalDistance = snapshot.distance;
    state.timeSeconds = snapshot.time;
    state.deltaSeconds = clamp(deltaSeconds, 0.0F, 0.1F);
    state.speedMetersPerSecond = static_cast<float>(snapshot.speed);
    state.steering = static_cast<float>(snapshot.steer);
    // Coasting keeps a reduced bob amplitude so the rider never freezes mid-stroke.
    state.pedal = snapshot.pedaling ? 1.0F : 0.3F;
    state.airborne = snapshot.airborne ? 1.0F : 0.0F;
    state.trick = static_cast<float>(snapshot.trickBlend);
    state.crankAngle = static_cast<float>(snapshot.crankAngle);
    state.wheelAngle = static_cast<float>(snapshot.wheelAngle);
    state.lean = static_cast<float>(snapshot.lean);
    state.wheelie = static_cast<float>(snapshot.wheelie);
    state.verticalPosition = static_cast<float>(snapshot.verticalPosition);
    state.lane = static_cast<float>(snapshot.lane);
    state.laneVelocity = static_cast<float>(snapshot.laneVelocity);
    state.fishCount = static_cast<uint32_t>(std::min<std::size_t>(snapshot.activeFishCount, state.fish.size()));
    for (uint32_t index = 0; index < state.fishCount; ++index) {
        const FishSnapshot& source = snapshot.fish[index];
        state.fish[index].localPosition = {source.localPosition.x, source.localPosition.y, source.localPosition.z};
        state.fish[index].phase = source.phase;
        state.fish[index].scale = source.scale;
        state.fish[index].golden = source.golden;
    }
    state.mouthOpen = mouthPulseSeconds_ > 0.0 ? 0.78F : 0.0F;
    state.hour = static_cast<float>(snapshot.hour);
    state.cloudCover = static_cast<float>(settings_.cloud);
    state.waveAmplitude = static_cast<float>(settings_.waveAmp);
    state.cameraFovDegrees = snapshot.camera.verticalFovDegrees;
    state.cameraPosition = {snapshot.camera.localPosition.x,
                            snapshot.camera.localPosition.y,
                            snapshot.camera.localPosition.z};
    state.cameraTarget = {snapshot.camera.localLookAt.x,
                          snapshot.camera.localLookAt.y,
                          snapshot.camera.localLookAt.z};
    state.helmet = settings_.helmet;
    state.glasses = settings_.glasses == "on" ||
                    (settings_.glasses == "auto" && snapshot.nightFactor < 0.3);
    state.scarf = settings_.scarf;
    state.bloom = settings_.bloom;
    state.bloomBoost = static_cast<float>(settings_.bloomBoost);
    state.fogMultiplier = static_cast<float>(settings_.fog);
    state.exposureMultiplier = static_cast<float>(settings_.exposure);
    state.enableSpeedLines = settings_.quality != "low";
    state.useExternalCamera = snapshot.camera.mode != CameraMode::Orbit;
    state.autoRotateOrbit = true;
    return state;
}

scene::Quality Engine::SceneQuality() const noexcept
{
    if (settings_.quality == "low") {
        return scene::Quality::Low;
    }
    if (settings_.quality == "high" || settings_.quality == "ultra") {
        return scene::Quality::High;
    }
    return scene::Quality::Medium;
}

void Engine::QueueError(const std::string& code, const std::string& message)
{
    BridgeEvent event;
    event.type = BridgeEventType::Error;
    event.code = code;
    event.message = message;
    pendingEvents_.push_back(std::move(event));
}

void Engine::QueueToast(const std::string& message)
{
    BridgeEvent event;
    event.type = BridgeEventType::Toast;
    event.message = message;
    pendingEvents_.push_back(std::move(event));
}

} // namespace pelican::integration
