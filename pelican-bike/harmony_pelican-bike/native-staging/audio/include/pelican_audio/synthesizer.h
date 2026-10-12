#ifndef PELICAN_AUDIO_SYNTHESIZER_H_
#define PELICAN_AUDIO_SYNTHESIZER_H_

#include <cstddef>
#include <cstdint>
#include <memory>

namespace pelican::audio {

inline constexpr std::uint32_t kSampleRate = 48000;
inline constexpr std::uint32_t kChannelCount = 2;

// Values are copied into the SPSC command queue. Call update() from one game
// thread; render() consumes commands from the single audio callback thread.
struct Parameters {
  float speed = 0.0F;
  float cadence = 84.0F;
  float night = 0.0F;
  float masterVolume = 0.8F;
  float musicVolume = 0.55F;
  float effectsVolume = 0.9F;
  bool pedaling = true;
  bool airborne = false;
  bool musicEnabled = true;
};

enum class Event : std::uint8_t {
  Bell,
  Honk,
  Gulp,
  GulpGolden,
  Splash,
  Thump,
  Whoosh,
  Seagull,
};

// Fixed-storage real-time synthesizer. Construction/reset happen off the audio
// callback. render() performs no locking, allocation, file I/O, or logging.
class Synthesizer final {
 public:
  Synthesizer();
  ~Synthesizer();

  Synthesizer(const Synthesizer&) = delete;
  Synthesizer& operator=(const Synthesizer&) = delete;
  Synthesizer(Synthesizer&&) = delete;
  Synthesizer& operator=(Synthesizer&&) = delete;

  // Producer-side API. False means the bounded command queue was full.
  bool update(const Parameters& parameters) noexcept;
  bool trigger(Event event) noexcept;
  bool setPaused(bool paused) noexcept;

  // Consumer-side API. The output is interleaved stereo float PCM.
  void render(float* interleavedStereo, std::size_t frameCount) noexcept;

  // Only call while no render() call can be active.
  void reset() noexcept;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace pelican::audio

#endif  // PELICAN_AUDIO_SYNTHESIZER_H_
