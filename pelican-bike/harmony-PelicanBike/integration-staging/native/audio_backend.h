#pragma once

#include <memory>

#include "pelican_audio/audio_engine.h"

namespace pelican::integration {

class AudioBackend {
public:
    virtual ~AudioBackend() = default;
    virtual bool Start() noexcept = 0;
    virtual void Stop() noexcept = 0;
    virtual bool SetPaused(bool paused) noexcept = 0;
    virtual bool Update(const audio::Parameters& parameters) noexcept = 0;
    virtual bool Trigger(audio::Event event) noexcept = 0;
    virtual bool IsRunning() const noexcept = 0;
};

class NativeAudioBackend final : public AudioBackend {
public:
    bool Start() noexcept override { return engine_.start(); }
    void Stop() noexcept override { engine_.stop(); }
    bool SetPaused(bool paused) noexcept override { return engine_.setPaused(paused); }
    bool Update(const audio::Parameters& parameters) noexcept override { return engine_.update(parameters); }
    bool Trigger(audio::Event event) noexcept override { return engine_.trigger(event); }
    bool IsRunning() const noexcept override { return engine_.isRunning(); }

private:
    audio::AudioEngine engine_{};
};

} // namespace pelican::integration
