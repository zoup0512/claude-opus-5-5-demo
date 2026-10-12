#include "pelican_renderer.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <iomanip>
#include <memory>
#include <sstream>
#include <utility>

#include <hilog/log.h>
#include <native_window/external_window.h>
#include <rawfile/raw_file.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xF2534
#define LOG_TAG "PelicanNative"

namespace pelican::integration {
namespace {

constexpr const char* kVSyncName = "pelican-vsync";
constexpr double kNanosecondsToSeconds = 1.0 / 1000000000.0;
constexpr long long kHudPeriodNanoseconds = 100000000LL;
constexpr long long kPerfPeriodNanoseconds = 1000000000LL;

std::string EglErrorString(EGLint error)
{
    std::ostringstream stream;
    stream << "0x" << std::hex << error;
    return stream.str();
}

void SetString(napi_env env, napi_value object, const char* name, const std::string& value)
{
    napi_value property = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &property);
    napi_set_named_property(env, object, name, property);
}

void SetDouble(napi_env env, napi_value object, const char* name, double value)
{
    napi_value property = nullptr;
    napi_create_double(env, value, &property);
    napi_set_named_property(env, object, name, property);
}

void SetInt(napi_env env, napi_value object, const char* name, int32_t value)
{
    napi_value property = nullptr;
    napi_create_int32(env, value, &property);
    napi_set_named_property(env, object, name, property);
}

void SetBool(napi_env env, napi_value object, const char* name, bool value)
{
    napi_value property = nullptr;
    napi_get_boolean(env, value, &property);
    napi_set_named_property(env, object, name, property);
}

napi_value SnapshotToJs(napi_env env, const HudSnapshot& snapshot)
{
    napi_value object = nullptr;
    napi_create_object(env, &object);
    SetDouble(env, object, "speedKmh", snapshot.speedKmh);
    SetDouble(env, object, "cadence", snapshot.cadence);
    SetInt(env, object, "gear", snapshot.gear);
    SetInt(env, object, "gearCount", snapshot.gearCount);
    SetDouble(env, object, "distanceKm", snapshot.distanceKm);
    SetInt(env, object, "fish", snapshot.fish);
    SetInt(env, object, "achievements", snapshot.achievements);
    SetInt(env, object, "achievementTotal", snapshot.achievementTotal);
    SetDouble(env, object, "hour", snapshot.hour);
    SetDouble(env, object, "fps", snapshot.fps);
    SetString(env, object, "quality", snapshot.quality);
    SetString(env, object, "camera", snapshot.camera);
    SetBool(env, object, "night", snapshot.night);
    SetBool(env, object, "started", snapshot.started);
    SetBool(env, object, "paused", snapshot.paused);
    return object;
}

bool HasProperty(napi_env env, napi_value object, const char* name, napi_value& output)
{
    bool hasProperty = false;
    return napi_has_named_property(env, object, name, &hasProperty) == napi_ok && hasProperty &&
           napi_get_named_property(env, object, name, &output) == napi_ok;
}

bool ReadBool(napi_env env, napi_value object, const char* name, bool& output)
{
    napi_value value = nullptr;
    return HasProperty(env, object, name, value) && napi_get_value_bool(env, value, &output) == napi_ok;
}

bool ReadNumber(napi_env env, napi_value object, const char* name, double& output)
{
    napi_value value = nullptr;
    return HasProperty(env, object, name, value) && napi_get_value_double(env, value, &output) == napi_ok &&
           std::isfinite(output);
}

bool ReadString(napi_env env, napi_value object, const char* name, std::string& output)
{
    napi_value value = nullptr;
    if (!HasProperty(env, object, name, value)) {
        return false;
    }
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    std::string buffer(length + 1, '\0');
    size_t written = 0;
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &written) != napi_ok) {
        return false;
    }
    buffer.resize(written);
    output = std::move(buffer);
    return true;
}

const char* EventTypeName(BridgeEventType type)
{
    switch (type) {
        case BridgeEventType::Hud: return "hud";
        case BridgeEventType::Toast: return "toast";
        case BridgeEventType::Score: return "score";
        case BridgeEventType::Achievement: return "achievement";
        case BridgeEventType::CameraFlash: return "cameraFlash";
        case BridgeEventType::SeaJumper: return "seaJumper";
        case BridgeEventType::Screenshot: return "screenshot";
        case BridgeEventType::Error: return "error";
    }
    return "error";
}

TouchAction ConvertTouchAction(OH_NativeXComponent_TouchEventType type)
{
    switch (type) {
        case OH_NATIVEXCOMPONENT_DOWN: return TouchAction::Down;
        case OH_NATIVEXCOMPONENT_UP: return TouchAction::Up;
        case OH_NATIVEXCOMPONENT_CANCEL: return TouchAction::Cancel;
        case OH_NATIVEXCOMPONENT_MOVE:
        default:
            return TouchAction::Move;
    }
}

} // namespace

PelicanRenderer& PelicanRenderer::Instance()
{
    static PelicanRenderer renderer;
    return renderer;
}

PelicanRenderer::PelicanRenderer()
{
    callbacks_.OnSurfaceCreated = OnSurfaceCreated;
    callbacks_.OnSurfaceChanged = OnSurfaceChanged;
    callbacks_.OnSurfaceDestroyed = OnSurfaceDestroyed;
    callbacks_.DispatchTouchEvent = DispatchTouchEvent;
}

bool PelicanRenderer::AttachXComponent(napi_env env, napi_value exports)
{
    bool hasNativeObject = false;
    if (napi_has_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &hasNativeObject) != napi_ok ||
        !hasNativeObject) {
        // A plain ArkTS import legitimately has no XComponent object. The same
        // library is initialized again for XComponent({ libraryname: 'pelican' }),
        // at which point this property is present and callbacks are registered.
        return false;
    }
    napi_value nativeObject = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &nativeObject) != napi_ok ||
        nativeObject == nullptr) {
        return false;
    }
    OH_NativeXComponent* component = nullptr;
    if (napi_unwrap(env, nativeObject, reinterpret_cast<void**>(&component)) != napi_ok ||
        component == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
                     "Failed to unwrap OH_NATIVE_XCOMPONENT_OBJ");
        return false;
    }
    const int32_t result = OH_NativeXComponent_RegisterCallback(component, &callbacks_);
    if (result != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
                     "OH_NativeXComponent_RegisterCallback failed: %{public}d", result);
        return false;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    xcomponent_ = component;
    return true;
}

EngineSettings PelicanRenderer::ParseInitializeOptionsLocked(napi_env env, napi_value options)
{
    EngineSettings settings;
    if (options == nullptr) {
        return settings;
    }
    napi_valuetype type = napi_undefined;
    napi_typeof(env, options, &type);
    if (type != napi_object) {
        return settings;
    }

    napi_value resourceManagerValue = nullptr;
    if (HasProperty(env, options, "resourceManager", resourceManagerValue)) {
        if (resourceManager_ != nullptr) {
            OH_ResourceManager_ReleaseNativeResourceManager(resourceManager_);
            resourceManager_ = nullptr;
        }
        resourceManager_ = OH_ResourceManager_InitNativeResourceManager(env, resourceManagerValue);
        if (resourceManager_ == nullptr) {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
                         "NativeResourceManager initialization failed");
        }
    }

    ReadString(env, options, "quality", settings.quality);
    std::string camera;
    ReadString(env, options, "camera", camera);
    ReadNumber(env, options, "hour", settings.hour);
    ReadNumber(env, options, "cruise", settings.cruise);
    ReadBool(env, options, "autopilot", settings.autopilot);
    ReadBool(env, options, "autoGear", settings.autoGear);
    ReadNumber(env, options, "dayRate", settings.dayRate);
    ReadBool(env, options, "timeFlow", settings.timeFlow);
    ReadNumber(env, options, "cloud", settings.cloud);
    ReadNumber(env, options, "waveAmp", settings.waveAmp);
    ReadNumber(env, options, "fog", settings.fog);
    ReadBool(env, options, "bloom", settings.bloom);
    ReadNumber(env, options, "bloomBoost", settings.bloomBoost);
    ReadNumber(env, options, "exposure", settings.exposure);
    ReadBool(env, options, "showFps", settings.showFps);
    ReadBool(env, options, "helmet", settings.helmet);
    ReadString(env, options, "glasses", settings.glasses);
    ReadBool(env, options, "scarf", settings.scarf);
    ReadBool(env, options, "lookMouse", settings.lookMouse);
    ReadNumber(env, options, "volume", settings.volume);
    ReadBool(env, options, "music", settings.music);
    ReadNumber(env, options, "musicVolume", settings.musicVolume);

    bool night = false;
    if (ReadBool(env, options, "night", night)) {
        settings.hour = night ? 23.0 : settings.hour;
    }
    if (!camera.empty()) {
        // Engine reset starts at cine; apply requested camera after Initialize.
        settings.quality = settings.quality.empty() ? "medium" : settings.quality;
    }
    return settings;
}

bool PelicanRenderer::Initialize(napi_env env, napi_value options)
{
    std::vector<BridgeEvent> events;
    std::string camera;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        disposed_ = false;
        const EngineSettings settings = ParseInitializeOptionsLocked(env, options);
        if (options != nullptr) {
            ReadString(env, options, "camera", camera);
        }
        engine_.Initialize(settings);
        if (!camera.empty()) {
            engine_.SetCamera(camera);
        }
        initialized_ = true;
        started_ = false;
        paused_ = false;
        fatalRenderError_ = false;
        screenshotPending_ = false;
        lastFrameTimestamp_ = 0;
        fpsWindowTimestamp_ = 0;
        lastHudTimestamp_ = 0;
        lastPerfTimestamp_ = 0;
        fpsWindowFrames_ = 0;
        totalFrames_ = 0;
        fps_ = 0.0;
        AppendEngineEventsLocked(events);
    }
    QueueEvents(std::move(events));
    return true;
}

bool PelicanRenderer::Start(bool withSound)
{
    std::vector<BridgeEvent> events;
    bool result = false;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (disposed_) {
            return false;
        }
        if (!initialized_) {
            engine_.Initialize();
            initialized_ = true;
        }
        result = engine_.Start(withSound);
        started_ = result;
        paused_ = false;
        AppendEngineEventsLocked(events);
        if (result && surfaceReady_ && !fatalRenderError_) {
            RequestNextFrameLocked();
        }
    }
    QueueEvents(std::move(events));
    return result;
}

void PelicanRenderer::SetPaused(bool paused)
{
    std::vector<BridgeEvent> events;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        paused_ = paused;
        engine_.SetPaused(paused);
        AppendEngineEventsLocked(events);
        if (!paused && started_ && surfaceReady_ && !fatalRenderError_ && !scheduling_) {
            lastFrameTimestamp_ = 0;
            RequestNextFrameLocked();
        }
    }
    QueueEvents(std::move(events));
}

void PelicanRenderer::SetInput(const std::string& name, bool pressed)
{
    std::lock_guard<std::mutex> lock(mutex_);
    engine_.SetInput(name, pressed);
}

void PelicanRenderer::TriggerAction(const std::string& action, double x, double y, bool hasCoordinates)
{
    std::vector<BridgeEvent> events;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        engine_.TriggerAction(action, x, y, hasCoordinates);
        AppendEngineEventsLocked(events);
    }
    QueueEvents(std::move(events));
}

void PelicanRenderer::SetCamera(const std::string& camera)
{
    std::vector<BridgeEvent> events;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        engine_.SetCamera(camera);
        AppendEngineEventsLocked(events);
    }
    QueueEvents(std::move(events));
}

bool PelicanRenderer::SetSetting(const std::string& name, const SettingValue& value)
{
    std::lock_guard<std::mutex> lock(mutex_);
    return engine_.SetSetting(name, value);
}

HudSnapshot PelicanRenderer::Snapshot() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return engine_.Snapshot(fps_);
}

bool PelicanRenderer::SetEventCallback(napi_env env, napi_value callback)
{
    napi_threadsafe_function replacement = nullptr;
    napi_valuetype type = napi_undefined;
    if (callback != nullptr) {
        napi_typeof(env, callback, &type);
    }
    if (type == napi_function) {
        napi_value resourceName = nullptr;
        napi_create_string_utf8(env, "pelican-events", NAPI_AUTO_LENGTH, &resourceName);
        if (napi_create_threadsafe_function(env, callback, nullptr, resourceName, 64, 1, nullptr,
                                            nullptr, nullptr, CallJsEvent, &replacement) != napi_ok) {
            return false;
        }
    } else if (type != napi_null && type != napi_undefined) {
        napi_throw_type_error(env, nullptr, "callback must be a function or null");
        return false;
    }

    napi_threadsafe_function old = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        old = eventTsfn_;
        eventTsfn_ = replacement;
    }
    if (old != nullptr) {
        napi_release_threadsafe_function(old, napi_tsfn_abort);
    }
    return true;
}

void PelicanRenderer::RequestScreenshot()
{
    BridgeEvent error;
    bool queueError = false;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!started_ || paused_ || !surfaceReady_ || fatalRenderError_) {
            error.type = BridgeEventType::Screenshot;
            error.success = false;
            error.message = "当前没有可截图的活动渲染帧";
            queueError = true;
        } else {
            screenshotPending_ = true;
            if (!scheduling_) {
                RequestNextFrameLocked();
            }
        }
    }
    if (queueError) {
        QueueEvent(std::move(error));
    }
}

void PelicanRenderer::Dispose()
{
    napi_threadsafe_function callback = nullptr;
    NativeResourceManager* resourceManager = nullptr;
    {
        std::unique_lock<std::mutex> lock(mutex_);
        disposed_ = true;
        initialized_ = false;
        started_ = false;
        paused_ = true;
        screenshotPending_ = false;
        StopSchedulingLocked();
        surfaceReady_ = false;
        renderIdleCv_.wait(lock, [this] { return inFlightRenders_ == 0; });
        DestroyEglLocked();
        engine_.Dispose();
        surfaceId_ = 0;
        width_ = 1;
        height_ = 1;
        lastFrameTimestamp_ = 0;
        fpsWindowTimestamp_ = 0;
        lastHudTimestamp_ = 0;
        lastPerfTimestamp_ = 0;
        fpsWindowFrames_ = 0;
        totalFrames_ = 0;
        fps_ = 0.0;
        touchTracker_.Reset();
        callback = eventTsfn_;
        eventTsfn_ = nullptr;
        resourceManager = resourceManager_;
        resourceManager_ = nullptr;
    }
    if (callback != nullptr) {
        napi_release_threadsafe_function(callback, napi_tsfn_abort);
    }
    if (resourceManager != nullptr) {
        OH_ResourceManager_ReleaseNativeResourceManager(resourceManager);
    }
}

bool PelicanRenderer::IsOrbitCamera() const
{
    return engine_.Snapshot(fps_).camera == "orbit";
}

void PelicanRenderer::SwitchToOrbitCamera()
{
    engine_.SetCamera("orbit");
}

void PelicanRenderer::OrbitDrag(float dxNormalized, float dyNormalized)
{
    engine_.OrbitDrag(dxNormalized, dyNormalized);
}

void PelicanRenderer::OrbitZoom(float scaleDelta)
{
    engine_.OrbitZoom(scaleDelta);
}

void PelicanRenderer::Pick(float normalizedX, float normalizedY)
{
    engine_.Pick(normalizedX, normalizedY);
}

void PelicanRenderer::OnSurfaceCreated(OH_NativeXComponent* component, void* window)
{
    Instance().HandleSurfaceCreated(component, window);
}

void PelicanRenderer::OnSurfaceChanged(OH_NativeXComponent* component, void* window)
{
    Instance().HandleSurfaceChanged(component, window);
}

void PelicanRenderer::OnSurfaceDestroyed(OH_NativeXComponent* component, void* window)
{
    Instance().HandleSurfaceDestroyed(component, window);
}

void PelicanRenderer::DispatchTouchEvent(OH_NativeXComponent* component, void* window)
{
    Instance().HandleTouch(component, window);
}

void PelicanRenderer::OnVSync(long long timestamp, void* data)
{
    if (data != nullptr) {
        static_cast<PelicanRenderer*>(data)->HandleVSync(timestamp);
    }
}

void PelicanRenderer::HandleSurfaceCreated(OH_NativeXComponent* component, void* window)
{
    std::vector<BridgeEvent> events;
    {
        std::unique_lock<std::mutex> lock(mutex_);
        ++surfaceGeneration_;
        scheduling_ = false;
        surfaceReady_ = false;
        renderIdleCv_.wait(lock, [this] { return inFlightRenders_ == 0; });
        DestroyEglLocked();
        xcomponent_ = component;
        UpdateSurfaceSizeLocked(component, window);
        if (!CreateEglLocked(window, events)) {
            width_ = 1;
            height_ = 1;
            surfaceId_ = 0;
            FailLocked("EGL_INIT", "Unable to initialize an OpenGL ES 3 surface", events);
        } else {
            surfaceReady_ = true;
            fatalRenderError_ = false;
            engine_.SetAudioSuspended(paused_);
            lastFrameTimestamp_ = 0;
            if (started_ && !paused_) {
                RequestNextFrameLocked();
            }
        }
        AppendEngineEventsLocked(events);
    }
    QueueEvents(std::move(events));
}

void PelicanRenderer::HandleSurfaceChanged(OH_NativeXComponent* component, void* window)
{
    std::vector<BridgeEvent> events;
    {
        std::unique_lock<std::mutex> lock(mutex_);
        if (!surfaceReady_ || window == nullptr) {
            return;
        }
        ++surfaceGeneration_;
        scheduling_ = false;
        renderIdleCv_.wait(lock, [this] { return inFlightRenders_ == 0; });
        UpdateSurfaceSizeLocked(component, window);
        OH_NativeWindow_NativeWindowHandleOpt(reinterpret_cast<OHNativeWindow*>(window), SET_BUFFER_GEOMETRY,
                                               static_cast<int32_t>(width_), static_cast<int32_t>(height_));
        if (eglMakeCurrent(display_, surface_, surface_, context_) != EGL_TRUE) {
            FailLocked("EGL_RESIZE", "eglMakeCurrent during resize failed: " +
                       EglErrorString(eglGetError()), events);
        } else {
            engine_.ResizeScene(static_cast<int>(width_), static_cast<int>(height_));
            if (eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT) != EGL_TRUE) {
                FailLocked("EGL_UNBIND", "EGL context unbind after resize failed: " +
                           EglErrorString(eglGetError()), events);
            }
        }
        if (started_ && !paused_ && !fatalRenderError_) {
            RequestNextFrameLocked();
        }
        AppendEngineEventsLocked(events);
    }
    QueueEvents(std::move(events));
}

void PelicanRenderer::HandleSurfaceDestroyed(OH_NativeXComponent* component, void* window)
{
    (void)component;
    (void)window;
    std::unique_lock<std::mutex> lock(mutex_);
    ++surfaceGeneration_;
    surfaceReady_ = false;
    engine_.SetAudioSuspended(true);
    scheduling_ = false;
    screenshotPending_ = false;
    renderIdleCv_.wait(lock, [this] { return inFlightRenders_ == 0; });
    DestroyEglLocked();
    surfaceId_ = 0;
    width_ = 1;
    height_ = 1;
    lastFrameTimestamp_ = 0;
    fpsWindowTimestamp_ = 0;
    lastHudTimestamp_ = 0;
    lastPerfTimestamp_ = 0;
    fpsWindowFrames_ = 0;
    fps_ = 0.0;
    touchTracker_.Reset();
}

void PelicanRenderer::HandleTouch(OH_NativeXComponent* component, void* window)
{
    OH_NativeXComponent_TouchEvent nativeEvent{};
    if (OH_NativeXComponent_GetTouchEvent(component, window, &nativeEvent) !=
        OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        return;
    }

    TouchSample sample;
    sample.action = ConvertTouchAction(nativeEvent.type);
    sample.changedId = nativeEvent.id;
    sample.pointCount = std::min<std::size_t>(nativeEvent.numPoints, sample.points.size());
    for (std::size_t index = 0; index < sample.pointCount; ++index) {
        sample.points[index].id = nativeEvent.touchPoints[index].id;
        sample.points[index].x = nativeEvent.touchPoints[index].x;
        sample.points[index].y = nativeEvent.touchPoints[index].y;
        sample.points[index].pressed = nativeEvent.touchPoints[index].isPressed;
    }

    std::vector<BridgeEvent> events;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        touchTracker_.Process(sample, width_, height_, *this);
        AppendEngineEventsLocked(events);
    }
    QueueEvents(std::move(events));
}

void PelicanRenderer::HandleVSync(long long timestamp)
{
    std::vector<BridgeEvent> events;
    bool shouldRender = false;
    uint64_t generation = 0;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        scheduling_ = false;
        shouldRender = surfaceReady_ && !paused_ && started_ && !fatalRenderError_ &&
            display_ != EGL_NO_DISPLAY && surface_ != EGL_NO_SURFACE && context_ != EGL_NO_CONTEXT;
        if (shouldRender) {
            ++inFlightRenders_;
            generation = surfaceGeneration_;
        }
    }
    if (!shouldRender) {
        return;
    }

    bool rendered = false;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (generation == surfaceGeneration_ && surfaceReady_ && !paused_ && started_ &&
            !fatalRenderError_) {
            rendered = RenderFrameLocked(timestamp, events);
        }
        --inFlightRenders_;
        renderIdleCv_.notify_all();
        if (rendered && generation == surfaceGeneration_ && surfaceReady_ && !paused_ && started_ &&
            !fatalRenderError_) {
            RequestNextFrameLocked();
        }
    }
    QueueEvents(std::move(events));
}

bool PelicanRenderer::CreateEglLocked(void* window, std::vector<BridgeEvent>& events)
{
    surfaceReady_ = false;
    surfaceId_ = 0;
    auto fail = [this]() {
        DestroyEglLocked();
        surfaceId_ = 0;
        return false;
    };
    if (window == nullptr) {
        return fail();
    }
    if (eglBindAPI(EGL_OPENGL_ES_API) != EGL_TRUE) {
        return fail();
    }
    display_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display_ == EGL_NO_DISPLAY) {
        return fail();
    }
    EGLint major = 0;
    EGLint minor = 0;
    if (eglInitialize(display_, &major, &minor) != EGL_TRUE) {
        return fail();
    }
    const EGLint attributes[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_STENCIL_SIZE, 8,
        EGL_NONE
    };
    EGLint count = 0;
    if (eglChooseConfig(display_, attributes, &config_, 1, &count) != EGL_TRUE ||
        count < 1 || config_ == nullptr) {
        return fail();
    }
    const EGLint contextAttributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    context_ = eglCreateContext(display_, config_, EGL_NO_CONTEXT, contextAttributes);
    if (context_ == EGL_NO_CONTEXT) {
        return fail();
    }
    surface_ = eglCreateWindowSurface(display_, config_, reinterpret_cast<EGLNativeWindowType>(window), nullptr);
    if (surface_ == EGL_NO_SURFACE) {
        return fail();
    }
    if (eglSwapInterval(display_, 0) != EGL_TRUE) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
                     "eglSwapInterval(0) failed: %{public}s", EglErrorString(eglGetError()).c_str());
    }
    if (eglMakeCurrent(display_, surface_, surface_, context_) != EGL_TRUE) {
        return fail();
    }
    if (!engine_.InitializeScene(static_cast<int>(width_), static_cast<int>(height_))) {
        AppendEngineEventsLocked(events);
        eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        return fail();
    }
    const char* version = reinterpret_cast<const char*>(glGetString(GL_VERSION));
    const char* renderer = reinterpret_cast<const char*>(glGetString(GL_RENDERER));
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "GL_VERSION=%{public}s",
                 version != nullptr ? version : "unknown");
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "GL_RENDERER=%{public}s",
                 renderer != nullptr ? renderer : "unknown");
    if (eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT) != EGL_TRUE) {
        return fail();
    }

    OHNativeWindow* nativeWindow = reinterpret_cast<OHNativeWindow*>(window);
    if (OH_NativeWindow_GetSurfaceId(nativeWindow, &surfaceId_) != 0 || surfaceId_ == 0) {
        return fail();
    }
    vsync_ = OH_NativeVSync_Create_ForAssociatedWindow(
        surfaceId_, kVSyncName, static_cast<unsigned int>(std::strlen(kVSyncName)));
    if (vsync_ == nullptr) {
        return fail();
    }
    return true;
}

void PelicanRenderer::DestroyEglLocked()
{
    if (vsync_ != nullptr) {
        OH_NativeVSync_Destroy(vsync_);
        vsync_ = nullptr;
    }
    if (display_ != EGL_NO_DISPLAY) {
        if (surface_ != EGL_NO_SURFACE && context_ != EGL_NO_CONTEXT &&
            eglMakeCurrent(display_, surface_, surface_, context_) == EGL_TRUE) {
            engine_.DestroyScene();
            eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        }
        if (surface_ != EGL_NO_SURFACE) {
            eglDestroySurface(display_, surface_);
            surface_ = EGL_NO_SURFACE;
        }
        if (context_ != EGL_NO_CONTEXT) {
            eglDestroyContext(display_, context_);
            context_ = EGL_NO_CONTEXT;
        }
        eglTerminate(display_);
        display_ = EGL_NO_DISPLAY;
    }
    config_ = nullptr;
    surfaceReady_ = false;
    scheduling_ = false;
}

bool PelicanRenderer::RenderFrameLocked(long long timestamp, std::vector<BridgeEvent>& events)
{
    if (eglMakeCurrent(display_, surface_, surface_, context_) != EGL_TRUE) {
        FailLocked("EGL_MAKE_CURRENT", "eglMakeCurrent failed: " + EglErrorString(eglGetError()), events);
        return false;
    }

    double deltaSeconds = 0.0;
    if (lastFrameTimestamp_ > 0 && timestamp > lastFrameTimestamp_) {
        deltaSeconds = std::clamp(static_cast<double>(timestamp - lastFrameTimestamp_) *
                                  kNanosecondsToSeconds, 0.0, 0.1);
    }
    lastFrameTimestamp_ = timestamp;
    const double aspectRatio = static_cast<double>(std::max<uint64_t>(width_, 1)) /
                               static_cast<double>(std::max<uint64_t>(height_, 1));
    FrameOutput frame = engine_.Advance(deltaSeconds, aspectRatio);
    events.insert(events.end(), std::make_move_iterator(frame.events.begin()),
                  std::make_move_iterator(frame.events.end()));

    if (!engine_.RebuildSceneIfNeeded(static_cast<int>(width_), static_cast<int>(height_))) {
        AppendEngineEventsLocked(events);
        eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        FailLocked("SCENE_REBUILD", engine_.SceneError(), events);
        return false;
    }
    if (!engine_.UpdateAndRender(frame.game, static_cast<float>(deltaSeconds))) {
        eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        FailLocked("SCENE_RENDER", engine_.SceneError().empty() ? "RenderScene is not initialized"
                                                                 : engine_.SceneError(), events);
        return false;
    }

    if (screenshotPending_) {
        BridgeEvent screenshot;
        screenshot.type = BridgeEventType::Screenshot;
        screenshot.width = static_cast<int32_t>(width_);
        screenshot.height = static_cast<int32_t>(height_);
        screenshot.pixels = engine_.ScreenshotPixels();
        screenshot.success = !screenshot.pixels.empty();
        if (!screenshot.success) {
            screenshot.message = "glReadPixels 截图失败";
            screenshot.width = 0;
            screenshot.height = 0;
        }
        events.push_back(std::move(screenshot));
        screenshotPending_ = false;
    }

    if (eglSwapBuffers(display_, surface_) != EGL_TRUE) {
        const EGLint error = eglGetError();
        eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        FailLocked("EGL_SWAP", "eglSwapBuffers failed: " + EglErrorString(error), events);
        return false;
    }
    if (eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT) != EGL_TRUE) {
        FailLocked("EGL_UNBIND", "EGL context unbind failed: " + EglErrorString(eglGetError()), events);
        return false;
    }

    ++fpsWindowFrames_;
    ++totalFrames_;
    if (fpsWindowTimestamp_ == 0) {
        fpsWindowTimestamp_ = timestamp;
    } else if (timestamp - fpsWindowTimestamp_ >= kPerfPeriodNanoseconds) {
        const double elapsed = static_cast<double>(timestamp - fpsWindowTimestamp_) * kNanosecondsToSeconds;
        fps_ = elapsed > 0.0 ? static_cast<double>(fpsWindowFrames_) / elapsed : 0.0;
        fpsWindowTimestamp_ = timestamp;
        fpsWindowFrames_ = 0;
    }
    if (lastHudTimestamp_ == 0 || timestamp - lastHudTimestamp_ >= kHudPeriodNanoseconds) {
        BridgeEvent hud;
        hud.type = BridgeEventType::Hud;
        hud.snapshot = engine_.Snapshot(fps_);
        events.push_back(std::move(hud));
        lastHudTimestamp_ = timestamp;
    }
    if (lastPerfTimestamp_ == 0 || timestamp - lastPerfTimestamp_ >= kPerfPeriodNanoseconds) {
        EmitPerfLocked(timestamp);
        lastPerfTimestamp_ = timestamp;
    }
    return true;
}

bool PelicanRenderer::RequestNextFrameLocked()
{
    if (scheduling_ || vsync_ == nullptr || !surfaceReady_ || paused_ || !started_ ||
        fatalRenderError_) {
        return false;
    }
    scheduling_ = true;
    const int result = OH_NativeVSync_RequestFrame(vsync_, OnVSync, this);
    if (result != 0) {
        scheduling_ = false;
        fatalRenderError_ = true;
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,
                     "OH_NativeVSync_RequestFrame failed: %{public}d", result);
        return false;
    }
    if (OH_NativeVSync_GetPeriod(vsync_, &vsyncPeriod_) != 0) {
        vsyncPeriod_ = 0;
    }
    return true;
}

void PelicanRenderer::StopSchedulingLocked()
{
    scheduling_ = false;
    ++surfaceGeneration_;
}

void PelicanRenderer::UpdateSurfaceSizeLocked(OH_NativeXComponent* component, void* window)
{
    uint64_t width = width_;
    uint64_t height = height_;
    if (component != nullptr && window != nullptr &&
        OH_NativeXComponent_GetXComponentSize(component, window, &width, &height) ==
            OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        width_ = std::max<uint64_t>(width, 1);
        height_ = std::max<uint64_t>(height, 1);
    }
}

void PelicanRenderer::FailLocked(const std::string& code, const std::string& message,
                                 std::vector<BridgeEvent>& events)
{
    fatalRenderError_ = true;
    scheduling_ = false;
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "%{public}s: %{public}s",
                 code.c_str(), message.c_str());
    BridgeEvent event;
    event.type = BridgeEventType::Error;
    event.code = code;
    event.message = message;
    events.push_back(std::move(event));
}

void PelicanRenderer::QueueEvents(std::vector<BridgeEvent> events)
{
    for (BridgeEvent& event : events) {
        QueueEvent(std::move(event));
    }
}

void PelicanRenderer::QueueEvent(BridgeEvent event)
{
    auto* payload = new BridgeEvent(std::move(event));
    napi_threadsafe_function callback = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        callback = eventTsfn_;
        if (callback != nullptr) {
            napi_acquire_threadsafe_function(callback);
        }
    }
    if (callback == nullptr) {
        delete payload;
        return;
    }
    const napi_status status = napi_call_threadsafe_function(callback, payload, napi_tsfn_nonblocking);
    napi_release_threadsafe_function(callback, napi_tsfn_release);
    if (status != napi_ok) {
        // Nonblocking TSFN returns napi_queue_full when saturated. The producer
        // owns payload until a successful enqueue, so every failure is released.
        delete payload;
    }
}

void PelicanRenderer::AppendEngineEventsLocked(std::vector<BridgeEvent>& events)
{
    std::vector<BridgeEvent> pending = engine_.DrainEvents();
    events.insert(events.end(), std::make_move_iterator(pending.begin()),
                  std::make_move_iterator(pending.end()));
}

void PelicanRenderer::EmitPerfLocked(long long timestamp)
{
    const scene::RenderStats stats = engine_.SceneStats();
    const HudSnapshot snapshot = engine_.Snapshot(fps_);
    std::ostringstream json;
    json << std::fixed << std::setprecision(3)
         << "PEL_PERF {\"v\":1,\"event\":\"sample\",\"runId\":\"native-live\","
         << "\"scenario\":\"xcomponent-vsync\",\"quality\":\"" << snapshot.quality << "\","
         << "\"tsMs\":" << static_cast<double>(timestamp) / 1000000.0 << ','
         << "\"frame\":" << totalFrames_ << ','
         << "\"fps\":" << std::max(fps_, 0.001) << ','
         << "\"frameCpuMs\":" << (stats.cpuUpdateMs + stats.cpuRenderMs) << ','
         << "\"drawCalls\":" << stats.drawCalls << ','
         << "\"triangles\":" << stats.triangles << ','
         << "\"heapMiB\":0,"
         << "\"distanceM\":" << snapshot.distanceKm * 1000.0 << ','
         << "\"hour\":" << snapshot.hour << ','
         << "\"surfaceWidth\":" << width_ << ','
         << "\"surfaceHeight\":" << height_ << ','
         << "\"resources\":{"
         << "\"textures\":" << stats.textures << ','
         << "\"buffers\":" << stats.buffers << ','
         << "\"framebuffers\":" << stats.framebuffers << ','
         << "\"renderbuffers\":" << stats.renderbuffers << ','
         << "\"programs\":" << stats.programs << ','
         << "\"vaos\":" << stats.vaos << ','
         << "\"glErrors\":" << stats.glErrors << "}}";
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "%{public}s", json.str().c_str());
}

void PelicanRenderer::CallJsEvent(napi_env env, napi_value callback, void* context, void* data)
{
    (void)context;
    std::unique_ptr<BridgeEvent> event(static_cast<BridgeEvent*>(data));
    if (event == nullptr || env == nullptr || callback == nullptr) {
        return;
    }

    napi_value object = nullptr;
    napi_create_object(env, &object);
    SetString(env, object, "type", EventTypeName(event->type));
    if (!event->message.empty()) SetString(env, object, "message", event->message);
    if (!event->code.empty()) SetString(env, object, "code", event->code);

    switch (event->type) {
        case BridgeEventType::Hud: {
            napi_value snapshot = SnapshotToJs(env, event->snapshot);
            napi_set_named_property(env, object, "snapshot", snapshot);
            break;
        }
        case BridgeEventType::Score:
            SetDouble(env, object, "score", event->score);
            SetDouble(env, object, "delta", event->delta);
            SetDouble(env, object, "x", event->x);
            SetDouble(env, object, "y", event->y);
            SetBool(env, object, "golden", event->golden);
            break;
        case BridgeEventType::Achievement:
            SetString(env, object, "id", event->achievementId);
            SetString(env, object, "icon", event->icon);
            SetString(env, object, "title", event->title);
            SetString(env, object, "detail", event->detail);
            break;
        case BridgeEventType::CameraFlash:
            SetDouble(env, object, "intensity", event->intensity);
            SetDouble(env, object, "x", event->x);
            SetDouble(env, object, "y", event->y);
            SetBool(env, object, "golden", event->golden);
            break;
        case BridgeEventType::SeaJumper:
            SetDouble(env, object, "x", event->x);
            SetDouble(env, object, "y", event->y);
            break;
        case BridgeEventType::Screenshot: {
            SetBool(env, object, "success", event->success);
            SetInt(env, object, "width", event->width);
            SetInt(env, object, "height", event->height);
            if (event->success && !event->pixels.empty()) {
                void* copied = nullptr;
                napi_value buffer = nullptr;
                if (napi_create_arraybuffer(env, event->pixels.size(), &copied, &buffer) == napi_ok &&
                    copied != nullptr) {
                    std::memcpy(copied, event->pixels.data(), event->pixels.size());
                    napi_set_named_property(env, object, "pixels", buffer);
                } else {
                    SetBool(env, object, "success", false);
                    SetString(env, object, "message", "ArrayBuffer allocation failed");
                }
            }
            break;
        }
        case BridgeEventType::Toast:
        case BridgeEventType::Error:
            break;
    }

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_value result = nullptr;
    napi_call_function(env, undefined, callback, 1, &object, &result);
}

std::vector<std::uint8_t> PelicanRenderer::ReadRawFile(const std::string& name) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (resourceManager_ == nullptr || name.empty()) {
        return {};
    }
    RawFile* file = OH_ResourceManager_OpenRawFile(resourceManager_, name.c_str());
    if (file == nullptr) {
        return {};
    }
    const long size = OH_ResourceManager_GetRawFileSize(file);
    if (size <= 0) {
        OH_ResourceManager_CloseRawFile(file);
        return {};
    }
    std::vector<std::uint8_t> data(static_cast<std::size_t>(size));
    const int read = OH_ResourceManager_ReadRawFile(file, data.data(), data.size());
    OH_ResourceManager_CloseRawFile(file);
    if (read < 0) {
        return {};
    }
    data.resize(static_cast<std::size_t>(read));
    return data;
}

} // namespace pelican::integration
