#include "pelican_audio/audio_engine.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>

#if defined(__OHOS__) && __has_include(<ohaudio/native_audiostreambuilder.h>) && \
    __has_include(<ohaudio/native_audiorenderer.h>)
#define PELICAN_AUDIO_HAS_OHAUDIO 1
#include <ohaudio/native_audiorenderer.h>
#include <ohaudio/native_audiostream_base.h>
#include <ohaudio/native_audiostreambuilder.h>
#else
#define PELICAN_AUDIO_HAS_OHAUDIO 0
#endif

namespace pelican::audio {
namespace {

constexpr std::size_t kConversionFrames = 2048;

inline std::int16_t FloatToS16(float sample) noexcept {
  if (!std::isfinite(sample)) sample = 0.0F;
  sample = std::max(-1.0F, std::min(1.0F, sample));
  const long value = std::lround(sample * 32767.0F);
  return static_cast<std::int16_t>(std::max(-32768L, std::min(32767L, value)));
}

}  // namespace

class AudioEngine::Impl final {
 public:
  Impl() = default;
  ~Impl() { stop(); }

  bool update(const Parameters& parameters) noexcept { return synth_.update(parameters); }
  bool trigger(Event event) noexcept { return synth_.trigger(event); }

  bool setPaused(bool paused) noexcept {
    std::lock_guard<std::mutex> lock(lifecycleMutex_);
    if (!synth_.setPaused(paused)) return false;
#if PELICAN_AUDIO_HAS_OHAUDIO
    if (renderer_ == nullptr || !running_.load(std::memory_order_acquire)) return true;
    OH_AudioStream_Result result = paused ? OH_AudioRenderer_Pause(renderer_)
                                          : OH_AudioRenderer_Start(renderer_);
    if (result != AUDIOSTREAM_SUCCESS) return false;
#endif
    paused_.store(paused, std::memory_order_release);
    return true;
  }

  bool start() noexcept {
    std::lock_guard<std::mutex> lock(lifecycleMutex_);
    if (running_.load(std::memory_order_acquire)) return true;
#if PELICAN_AUDIO_HAS_OHAUDIO
    synth_.reset();
    stopping_.store(false, std::memory_order_release);
    paused_.store(false, std::memory_order_release);
    if (!createRenderer(AUDIOSTREAM_SAMPLE_F32LE)) {
      destroyRenderer();
      if (!createRenderer(AUDIOSTREAM_SAMPLE_S16LE)) {
        destroyRenderer();
        return false;
      }
    }
    if (OH_AudioRenderer_Start(renderer_) != AUDIOSTREAM_SUCCESS) {
      destroyRenderer();
      return false;
    }
    running_.store(true, std::memory_order_release);
    return true;
#else
    return false;
#endif
  }

  void stop() noexcept {
    std::lock_guard<std::mutex> lock(lifecycleMutex_);
#if PELICAN_AUDIO_HAS_OHAUDIO
    if (renderer_ == nullptr && builder_ == nullptr) {
      running_.store(false, std::memory_order_release);
      return;
    }
    stopping_.store(true, std::memory_order_release);
    if (renderer_ != nullptr) OH_AudioRenderer_Stop(renderer_);
    // OH_AudioRenderer_Stop synchronously stops further data requests for this
    // renderer. Release follows before the Synthesizer can be reset/destroyed.
    destroyRenderer();
#endif
    running_.store(false, std::memory_order_release);
    paused_.store(false, std::memory_order_release);
  }

  bool isRunning() const noexcept { return running_.load(std::memory_order_acquire); }

#if PELICAN_AUDIO_HAS_OHAUDIO
  static OH_AudioData_Callback_Result OnWriteData(OH_AudioRenderer*, void* userData,
                                                   void* audioData,
                                                   int32_t audioDataSize) noexcept {
    auto* self = static_cast<Impl*>(userData);
    if (audioData == nullptr || audioDataSize <= 0) {
      return AUDIO_DATA_CALLBACK_RESULT_INVALID;
    }
    if (self->stopping_.load(std::memory_order_acquire)) {
      std::fill_n(static_cast<std::uint8_t*>(audioData),
                  static_cast<std::size_t>(audioDataSize), std::uint8_t{0});
      return AUDIO_DATA_CALLBACK_RESULT_VALID;
    }
    const std::size_t bytes = static_cast<std::size_t>(audioDataSize);
    if (self->sampleFormat_ == AUDIOSTREAM_SAMPLE_F32LE) {
      const std::size_t frames = bytes / (kChannelCount * sizeof(float));
      self->synth_.render(static_cast<float*>(audioData), frames);
      return AUDIO_DATA_CALLBACK_RESULT_VALID;
    }

    auto* output = static_cast<std::int16_t*>(audioData);
    std::size_t remainingFrames = bytes / (kChannelCount * sizeof(std::int16_t));
    while (remainingFrames > 0) {
      const std::size_t blockFrames = std::min(remainingFrames, kConversionFrames);
      self->synth_.render(self->conversionBuffer_.data(), blockFrames);
      const std::size_t sampleCount = blockFrames * kChannelCount;
      for (std::size_t sample = 0; sample < sampleCount; ++sample) {
        output[sample] = FloatToS16(self->conversionBuffer_[sample]);
      }
      output += sampleCount;
      remainingFrames -= blockFrames;
    }
    return AUDIO_DATA_CALLBACK_RESULT_VALID;
  }

  bool createRenderer(OH_AudioStream_SampleFormat format) noexcept {
    if (OH_AudioStreamBuilder_Create(&builder_, AUDIOSTREAM_TYPE_RENDERER) != AUDIOSTREAM_SUCCESS ||
        builder_ == nullptr) {
      return false;
    }
    const bool configured =
        OH_AudioStreamBuilder_SetSamplingRate(builder_, static_cast<int32_t>(kSampleRate)) ==
            AUDIOSTREAM_SUCCESS &&
        OH_AudioStreamBuilder_SetChannelCount(builder_, static_cast<int32_t>(kChannelCount)) ==
            AUDIOSTREAM_SUCCESS &&
        OH_AudioStreamBuilder_SetSampleFormat(builder_, format) == AUDIOSTREAM_SUCCESS &&
        OH_AudioStreamBuilder_SetEncodingType(builder_, AUDIOSTREAM_ENCODING_TYPE_RAW) ==
            AUDIOSTREAM_SUCCESS &&
        OH_AudioStreamBuilder_SetLatencyMode(builder_, AUDIOSTREAM_LATENCY_MODE_FAST) ==
            AUDIOSTREAM_SUCCESS &&
        OH_AudioStreamBuilder_SetRendererInfo(builder_, AUDIOSTREAM_USAGE_GAME) ==
            AUDIOSTREAM_SUCCESS &&
        OH_AudioStreamBuilder_SetRendererWriteDataCallback(builder_, &Impl::OnWriteData, this) ==
            AUDIOSTREAM_SUCCESS &&
        OH_AudioStreamBuilder_GenerateRenderer(builder_, &renderer_) == AUDIOSTREAM_SUCCESS &&
        renderer_ != nullptr;
    if (!configured) return false;
    sampleFormat_ = format;
    return true;
  }

  void destroyRenderer() noexcept {
    if (renderer_ != nullptr) {
      OH_AudioRenderer_Release(renderer_);
      renderer_ = nullptr;
    }
    if (builder_ != nullptr) {
      OH_AudioStreamBuilder_Destroy(builder_);
      builder_ = nullptr;
    }
  }
#endif

 private:
  Synthesizer synth_{};
  mutable std::mutex lifecycleMutex_{};  // Never touched by the RT callback.
  std::atomic<bool> running_{false};
  std::atomic<bool> stopping_{false};
  std::atomic<bool> paused_{false};
#if PELICAN_AUDIO_HAS_OHAUDIO
  OH_AudioStreamBuilder* builder_ = nullptr;
  OH_AudioRenderer* renderer_ = nullptr;
  OH_AudioStream_SampleFormat sampleFormat_ = AUDIOSTREAM_SAMPLE_F32LE;
  std::array<float, kConversionFrames * kChannelCount> conversionBuffer_{};
#endif
};

AudioEngine::AudioEngine() : impl_(std::make_unique<Impl>()) {}
AudioEngine::~AudioEngine() = default;

bool AudioEngine::start() noexcept { return impl_->start(); }
void AudioEngine::stop() noexcept { impl_->stop(); }
bool AudioEngine::setPaused(bool paused) noexcept { return impl_->setPaused(paused); }
bool AudioEngine::update(const Parameters& parameters) noexcept { return impl_->update(parameters); }
bool AudioEngine::trigger(Event event) noexcept { return impl_->trigger(event); }
bool AudioEngine::isRunning() const noexcept { return impl_->isRunning(); }
bool AudioEngine::nativeBackendAvailable() noexcept { return PELICAN_AUDIO_HAS_OHAUDIO != 0; }

}  // namespace pelican::audio
