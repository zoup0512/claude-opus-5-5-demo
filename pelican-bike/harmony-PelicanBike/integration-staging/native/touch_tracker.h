#pragma once

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>

namespace pelican::integration {

enum class TouchAction : std::uint8_t {
    Down = 0,
    Move,
    Up,
    Cancel,
};

struct TouchPointSample {
    int32_t id = -1;
    float x = 0.0F;
    float y = 0.0F;
    bool pressed = false;
};

struct TouchSample {
    TouchAction action = TouchAction::Move;
    int32_t changedId = -1;
    std::array<TouchPointSample, 10> points{};
    std::size_t pointCount = 0;
};

class SurfaceInputSink {
public:
    virtual ~SurfaceInputSink() = default;
    virtual bool IsOrbitCamera() const = 0;
    virtual void SwitchToOrbitCamera() = 0;
    virtual void OrbitDrag(float dxNormalized, float dyNormalized) = 0;
    virtual void OrbitZoom(float scaleDelta) = 0;
    virtual void Pick(float normalizedX, float normalizedY) = 0;
};

class TouchTracker final {
public:
    using Clock = std::chrono::steady_clock;

    void Reset();
    void Process(const TouchSample& sample, uint64_t width, uint64_t height,
                 SurfaceInputSink& sink, Clock::time_point now = Clock::now());

private:
    struct PointerState {
        bool active = false;
        int32_t id = -1;
        float startX = 0.0F;
        float startY = 0.0F;
        float x = 0.0F;
        float y = 0.0F;
        float lastX = 0.0F;
        float lastY = 0.0F;
        float maxMoveSquared = 0.0F;
        Clock::time_point downAt{};
        bool hasDownTime = false;
    };

    static constexpr std::size_t kMaxPointers = 10;
    static constexpr float kTapMoveThreshold = 6.0F;
    static constexpr float kOrbitSwitchThreshold = 10.0F;
    static constexpr std::chrono::milliseconds kTapDuration{450};

    PointerState* Find(int32_t id);
    PointerState* Acquire(int32_t id);
    void Release(int32_t id);
    std::size_t ActiveCount() const;
    void FirstTwo(PointerState*& first, PointerState*& second);

    std::array<PointerState, kMaxPointers> pointers_{};
    float pinchDistance_ = 0.0F;
    bool pinchValid_ = false;
};

} // namespace pelican::integration
