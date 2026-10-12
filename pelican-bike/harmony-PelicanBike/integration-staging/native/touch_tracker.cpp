#include "touch_tracker.h"

#include <algorithm>
#include <cmath>

namespace pelican::integration {
namespace {

float Distance(float x1, float y1, float x2, float y2)
{
    const float dx = x2 - x1;
    const float dy = y2 - y1;
    return std::sqrt(dx * dx + dy * dy);
}

float Clamp01(float value)
{
    return std::max(0.0F, std::min(1.0F, value));
}

} // namespace

void TouchTracker::Reset()
{
    for (PointerState& pointer : pointers_) {
        pointer = PointerState{};
    }
    pinchDistance_ = 0.0F;
    pinchValid_ = false;
}

TouchTracker::PointerState* TouchTracker::Find(int32_t id)
{
    for (PointerState& pointer : pointers_) {
        if (pointer.active && pointer.id == id) {
            return &pointer;
        }
    }
    return nullptr;
}

TouchTracker::PointerState* TouchTracker::Acquire(int32_t id)
{
    if (PointerState* existing = Find(id); existing != nullptr) {
        return existing;
    }
    for (PointerState& pointer : pointers_) {
        if (!pointer.active) {
            pointer = PointerState{};
            pointer.active = true;
            pointer.id = id;
            return &pointer;
        }
    }
    return nullptr;
}

void TouchTracker::Release(int32_t id)
{
    if (PointerState* pointer = Find(id); pointer != nullptr) {
        *pointer = PointerState{};
    }
}

std::size_t TouchTracker::ActiveCount() const
{
    return static_cast<std::size_t>(std::count_if(
        pointers_.begin(), pointers_.end(), [](const PointerState& pointer) { return pointer.active; }));
}

void TouchTracker::FirstTwo(PointerState*& first, PointerState*& second)
{
    first = nullptr;
    second = nullptr;
    for (PointerState& pointer : pointers_) {
        if (!pointer.active) {
            continue;
        }
        if (first == nullptr) {
            first = &pointer;
        } else {
            second = &pointer;
            return;
        }
    }
}

void TouchTracker::Process(const TouchSample& sample, uint64_t width, uint64_t height,
                           SurfaceInputSink& sink, Clock::time_point now)
{
    if (sample.action == TouchAction::Cancel) {
        Reset();
        return;
    }

    const std::size_t pointCount = std::min(sample.pointCount, sample.points.size());
    for (std::size_t index = 0; index < pointCount; ++index) {
        const TouchPointSample& point = sample.points[index];
        if (!point.pressed && sample.action != TouchAction::Up) {
            continue;
        }
        PointerState* state = Acquire(point.id);
        if (state == nullptr) {
            continue;
        }
        if (!state->hasDownTime) {
            state->startX = point.x;
            state->startY = point.y;
            state->x = point.x;
            state->y = point.y;
            state->lastX = point.x;
            state->lastY = point.y;
            state->downAt = now;
            state->hasDownTime = true;
        } else {
            state->lastX = state->x;
            state->lastY = state->y;
            state->x = point.x;
            state->y = point.y;
            const float fromStartX = state->x - state->startX;
            const float fromStartY = state->y - state->startY;
            state->maxMoveSquared = std::max(
                state->maxMoveSquared, fromStartX * fromStartX + fromStartY * fromStartY);
        }
    }

    const std::size_t activeCount = ActiveCount();
    if (sample.action == TouchAction::Move && activeCount == 1) {
        PointerState* first = nullptr;
        PointerState* unused = nullptr;
        FirstTwo(first, unused);
        if (first != nullptr) {
            const float dx = first->x - first->lastX;
            const float dy = first->y - first->lastY;
            const float switchThresholdSquared = kOrbitSwitchThreshold * kOrbitSwitchThreshold;
            if (!sink.IsOrbitCamera() && first->maxMoveSquared > switchThresholdSquared) {
                sink.SwitchToOrbitCamera();
            }
            if (sink.IsOrbitCamera()) {
                const float safeWidth = static_cast<float>(std::max<uint64_t>(width, 1));
                const float safeHeight = static_cast<float>(std::max<uint64_t>(height, 1));
                sink.OrbitDrag(dx / safeWidth, dy / safeHeight);
            }
        }
        pinchValid_ = false;
    } else if (activeCount >= 2) {
        PointerState* first = nullptr;
        PointerState* second = nullptr;
        FirstTwo(first, second);
        if (first != nullptr && second != nullptr) {
            const float distance = Distance(first->x, first->y, second->x, second->y);
            if (sample.action == TouchAction::Move && pinchValid_ && pinchDistance_ > 0.0F) {
                const float ratio = distance / pinchDistance_;
                if (std::isfinite(ratio) && ratio > 0.0F) {
                    sink.OrbitZoom(ratio);
                }
            }
            pinchDistance_ = distance;
            pinchValid_ = true;
        }
    } else {
        pinchValid_ = false;
    }

    if (sample.action == TouchAction::Up) {
        int32_t releasedId = sample.changedId;
        PointerState* released = Find(releasedId);
        if (released == nullptr) {
            for (PointerState& pointer : pointers_) {
                if (!pointer.active) {
                    continue;
                }
                bool stillPressed = false;
                for (std::size_t index = 0; index < pointCount; ++index) {
                    if (sample.points[index].id == pointer.id && sample.points[index].pressed) {
                        stillPressed = true;
                        break;
                    }
                }
                if (!stillPressed) {
                    released = &pointer;
                    releasedId = pointer.id;
                    break;
                }
            }
        }
        if (released != nullptr) {
            const auto duration = now - released->downAt;
            const float tapThresholdSquared = kTapMoveThreshold * kTapMoveThreshold;
            if (released->hasDownTime && released->maxMoveSquared <= tapThresholdSquared &&
                duration <= kTapDuration) {
                const float safeWidth = static_cast<float>(std::max<uint64_t>(width, 1));
                const float safeHeight = static_cast<float>(std::max<uint64_t>(height, 1));
                sink.Pick(Clamp01(released->x / safeWidth), Clamp01(released->y / safeHeight));
            }
            Release(releasedId);
        }
        if (ActiveCount() < 2) {
            pinchValid_ = false;
        }
    }
}

} // namespace pelican::integration
