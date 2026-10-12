#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

#include <EGL/egl.h>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <napi/native_api.h>
#include <native_vsync/native_vsync.h>
#include <rawfile/raw_file_manager.h>

#include "engine.h"
#include "touch_tracker.h"

namespace pelican::integration {

class PelicanRenderer final : public SurfaceInputSink {
public:
    static PelicanRenderer& Instance();

    bool AttachXComponent(napi_env env, napi_value exports);
    bool Initialize(napi_env env, napi_value options);
    bool Start(bool withSound);
    void SetPaused(bool paused);
    void SetInput(const std::string& name, bool pressed);
    void TriggerAction(const std::string& action, double x, double y, bool hasCoordinates);
    void SetCamera(const std::string& camera);
    bool SetSetting(const std::string& name, const SettingValue& value);
    HudSnapshot Snapshot() const;
    bool SetEventCallback(napi_env env, napi_value callback);
    void RequestScreenshot();
    void Dispose();

    bool IsOrbitCamera() const override;
    void SwitchToOrbitCamera() override;
    void OrbitDrag(float dxNormalized, float dyNormalized) override;
    void OrbitZoom(float scaleDelta) override;
    void Pick(float normalizedX, float normalizedY) override;

private:
    PelicanRenderer();
    ~PelicanRenderer() = default;
    PelicanRenderer(const PelicanRenderer&) = delete;
    PelicanRenderer& operator=(const PelicanRenderer&) = delete;

    static void OnSurfaceCreated(OH_NativeXComponent* component, void* window);
    static void OnSurfaceChanged(OH_NativeXComponent* component, void* window);
    static void OnSurfaceDestroyed(OH_NativeXComponent* component, void* window);
    static void DispatchTouchEvent(OH_NativeXComponent* component, void* window);
    static void OnVSync(long long timestamp, void* data);
    static void CallJsEvent(napi_env env, napi_value callback, void* context, void* data);

    void HandleSurfaceCreated(OH_NativeXComponent* component, void* window);
    void HandleSurfaceChanged(OH_NativeXComponent* component, void* window);
    void HandleSurfaceDestroyed(OH_NativeXComponent* component, void* window);
    void HandleTouch(OH_NativeXComponent* component, void* window);
    void HandleVSync(long long timestamp);

    bool CreateEglLocked(void* window, std::vector<BridgeEvent>& events);
    void DestroyEglLocked();
    bool RenderFrameLocked(long long timestamp, std::vector<BridgeEvent>& events);
    bool RequestNextFrameLocked();
    void StopSchedulingLocked();
    void UpdateSurfaceSizeLocked(OH_NativeXComponent* component, void* window);
    void FailLocked(const std::string& code, const std::string& message,
                    std::vector<BridgeEvent>& events);
    void QueueEvents(std::vector<BridgeEvent> events);
    void QueueEvent(BridgeEvent event);
    void AppendEngineEventsLocked(std::vector<BridgeEvent>& events);
    void EmitPerfLocked(long long timestamp);
    EngineSettings ParseInitializeOptionsLocked(napi_env env, napi_value options);
    std::vector<std::uint8_t> ReadRawFile(const std::string& name) const;

    mutable std::mutex mutex_;
    std::condition_variable renderIdleCv_;
    bool initialized_ = false;
    bool started_ = false;
    bool paused_ = false;
    bool disposed_ = false;
    bool surfaceReady_ = false;
    bool scheduling_ = false;
    bool fatalRenderError_ = false;
    bool screenshotPending_ = false;
    uint64_t surfaceGeneration_ = 0;
    uint32_t inFlightRenders_ = 0;
    uint64_t width_ = 1;
    uint64_t height_ = 1;
    uint64_t surfaceId_ = 0;
    long long lastFrameTimestamp_ = 0;
    long long fpsWindowTimestamp_ = 0;
    long long lastHudTimestamp_ = 0;
    long long lastPerfTimestamp_ = 0;
    uint32_t fpsWindowFrames_ = 0;
    uint64_t totalFrames_ = 0;
    double fps_ = 0.0;

    OH_NativeXComponent* xcomponent_ = nullptr;
    OH_NativeXComponent_Callback callbacks_{};
    TouchTracker touchTracker_{};
    Engine engine_{};

    EGLDisplay display_ = EGL_NO_DISPLAY;
    EGLConfig config_ = nullptr;
    EGLContext context_ = EGL_NO_CONTEXT;
    EGLSurface surface_ = EGL_NO_SURFACE;

    OH_NativeVSync* vsync_ = nullptr;
    long long vsyncPeriod_ = 0;

    NativeResourceManager* resourceManager_ = nullptr;
    napi_threadsafe_function eventTsfn_ = nullptr;
};

} // namespace pelican::integration
