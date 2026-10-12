#ifndef PELICAN_AUDIO_AUDIO_ENGINE_H_
#define PELICAN_AUDIO_AUDIO_ENGINE_H_

#include <memory>

#include "pelican_audio/synthesizer.h"

namespace pelican::audio {

// Lifecycle-safe OHAudio owner. All public methods may be called from the game
// thread. update()/trigger() feed the Synthesizer's bounded SPSC queue; the
// OHAudio callback is the only queue consumer.
class AudioEngine final {
 public:
  AudioEngine();
  ~AudioEngine();

  AudioEngine(const AudioEngine&) = delete;
  AudioEngine& operator=(const AudioEngine&) = delete;
  AudioEngine(AudioEngine&&) = delete;
  AudioEngine& operator=(AudioEngine&&) = delete;

  // Creates and starts a 48 kHz stereo OHAudio renderer. F32LE is attempted
  // first; S16LE is used if float output is rejected by the platform.
  bool start() noexcept;
  void stop() noexcept;
  bool setPaused(bool paused) noexcept;
  bool update(const Parameters& parameters) noexcept;
  bool trigger(Event event) noexcept;
  bool isRunning() const noexcept;

  // False in host builds where OHAudio headers/backend are intentionally absent.
  static bool nativeBackendAvailable() noexcept;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace pelican::audio

#endif  // PELICAN_AUDIO_AUDIO_ENGINE_H_
