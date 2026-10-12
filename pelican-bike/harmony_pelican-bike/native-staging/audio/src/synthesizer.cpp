#include "pelican_audio/synthesizer.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace pelican::audio {
namespace {

constexpr float kPi = 3.14159265358979323846F;
constexpr float kTwoPi = 2.0F * kPi;
constexpr float kInvSampleRate = 1.0F / static_cast<float>(kSampleRate);
constexpr float kTiny = 1.0e-5F;

template <typename T>
constexpr T Clamp(T value, T low, T high) noexcept {
  return value < low ? low : (value > high ? high : value);
}

inline float MidiToHz(int note) noexcept {
  return 440.0F * std::exp2((static_cast<float>(note) - 69.0F) / 12.0F);
}

inline float AdvancePhase(float& phase, float frequency) noexcept {
  if (!std::isfinite(phase) || !std::isfinite(frequency)) phase = 0.0F;
  frequency = Clamp(frequency, 0.0F, 0.475F * static_cast<float>(kSampleRate));
  phase += frequency * kInvSampleRate;
  if (phase >= 1.0F) phase -= std::floor(phase);
  return phase;
}

inline float WaveSample(float phase, std::uint8_t waveform) noexcept {
  switch (waveform) {
    case 1:  // triangle
      return 1.0F - 4.0F * std::fabs(phase - 0.5F);
    case 2:  // saw
      return 2.0F * phase - 1.0F;
    default:
      return std::sin(kTwoPi * phase);
  }
}

inline float EqualPowerLeft(float pan) noexcept {
  return std::cos((Clamp(pan, -1.0F, 1.0F) + 1.0F) * (kPi * 0.25F));
}

inline float EqualPowerRight(float pan) noexcept {
  return std::sin((Clamp(pan, -1.0F, 1.0F) + 1.0F) * (kPi * 0.25F));
}

inline float OnePoleCoefficient(float cutoff) noexcept {
  cutoff = Clamp(cutoff, 10.0F, 20000.0F);
  return 1.0F - std::exp(-kTwoPi * cutoff * kInvSampleRate);
}

inline float FiniteOrZero(float value) noexcept {
  return std::isfinite(value) ? value : 0.0F;
}

inline float SoftLimit(float sample) noexcept {
  // A rational tanh approximation. The input clamp keeps x*x finite even if a
  // future voice mix is accidentally extreme; internal DSP state is guarded at
  // its source rather than relying on this final safety boundary.
  const float x = Clamp(FiniteOrZero(sample) * 1.1F, -4.0F, 4.0F);
  const float x2 = x * x;
  return Clamp(x * (27.0F + x2) / (27.0F + 9.0F * x2), -1.0F, 1.0F);
}

struct Stereo {
  float left = 0.0F;
  float right = 0.0F;

  Stereo& operator+=(const Stereo& other) noexcept {
    left += other.left;
    right += other.right;
    return *this;
  }
};

struct Rng {
  std::uint32_t state = 0x6d2b79f5U;

  std::uint32_t nextU32() noexcept {
    std::uint32_t x = state;
    x ^= x << 13U;
    x ^= x >> 17U;
    x ^= x << 5U;
    state = x;
    return x;
  }

  float bipolar() noexcept {
    return static_cast<float>(nextU32() >> 8U) * (2.0F / 16777216.0F) - 1.0F;
  }

  float unit() noexcept {
    return static_cast<float>(nextU32() >> 8U) * (1.0F / 16777216.0F);
  }
};

class Biquad final {
 public:
  void setLowpass(float frequency, float q = 0.70710678F) noexcept {
    setCoefficients(frequency, q, false);
  }

  void setBandpass(float frequency, float q) noexcept {
    setCoefficients(frequency, q, true);
  }

  float process(float input) noexcept {
    input = FiniteOrZero(input);
    float output = b0_ * input + z1_;
    float nextZ1 = b1_ * input - a1_ * output + z2_;
    float nextZ2 = b2_ * input - a2_ * output;
    if (!std::isfinite(output) || !std::isfinite(nextZ1) || !std::isfinite(nextZ2)) {
      clear();
      output = 0.0F;
    } else {
      // Stable coefficients should never approach these bounds. Keeping state
      // finite here prevents a damaged stream from contaminating later frames.
      z1_ = Clamp(nextZ1, -16.0F, 16.0F);
      z2_ = Clamp(nextZ2, -16.0F, 16.0F);
    }
    return output;
  }

  void clear() noexcept { z1_ = z2_ = 0.0F; }

 private:
  void setCoefficients(float frequency, float q, bool bandpass) noexcept {
    frequency = Clamp(frequency, 20.0F, 0.475F * static_cast<float>(kSampleRate));
    q = std::max(q, 0.05F);
    const float omega = kTwoPi * frequency * kInvSampleRate;
    const float cosine = std::cos(omega);
    const float sine = std::sin(omega);
    const float alpha = sine / (2.0F * q);
    const float inverseA0 = 1.0F / (1.0F + alpha);
    if (bandpass) {
      b0_ = alpha * inverseA0;
      b1_ = 0.0F;
      b2_ = -alpha * inverseA0;
    } else {
      b0_ = 0.5F * (1.0F - cosine) * inverseA0;
      b1_ = (1.0F - cosine) * inverseA0;
      b2_ = b0_;
    }
    a1_ = -2.0F * cosine * inverseA0;
    a2_ = (1.0F - alpha) * inverseA0;
  }

  float b0_ = 1.0F;
  float b1_ = 0.0F;
  float b2_ = 0.0F;
  float a1_ = 0.0F;
  float a2_ = 0.0F;
  float z1_ = 0.0F;
  float z2_ = 0.0F;
};

class DcBlock final {
 public:
  float process(float input) noexcept {
    input = FiniteOrZero(input);
    float output = input - previousInput_ + 0.995F * previousOutput_;
    if (!std::isfinite(output)) {
      clear();
      return 0.0F;
    }
    output = Clamp(output, -8.0F, 8.0F);
    previousInput_ = input;
    previousOutput_ = output;
    return output;
  }

  void clear() noexcept { previousInput_ = previousOutput_ = 0.0F; }

 private:
  float previousInput_ = 0.0F;
  float previousOutput_ = 0.0F;
};

enum class CommandType : std::uint8_t { Update, Trigger, Pause };

struct Command {
  CommandType type = CommandType::Update;
  Parameters parameters{};
  Event event = Event::Bell;
  bool paused = false;
};

template <typename T, std::size_t Capacity>
class SpscQueue final {
 public:
  static_assert(Capacity >= 2, "SPSC queue needs a spare slot");

  bool push(const T& value) noexcept {
    const std::size_t write = write_.load(std::memory_order_relaxed);
    const std::size_t next = increment(write);
    if (next == read_.load(std::memory_order_acquire)) return false;
    storage_[write] = value;
    write_.store(next, std::memory_order_release);
    return true;
  }

  bool pop(T& value) noexcept {
    const std::size_t read = read_.load(std::memory_order_relaxed);
    if (read == write_.load(std::memory_order_acquire)) return false;
    value = storage_[read];
    read_.store(increment(read), std::memory_order_release);
    return true;
  }

  void clearConsumerSide() noexcept {
    read_.store(write_.load(std::memory_order_acquire), std::memory_order_release);
  }

 private:
  static constexpr std::size_t increment(std::size_t value) noexcept {
    return value + 1U == Capacity ? 0U : value + 1U;
  }

  std::array<T, Capacity> storage_{};
  alignas(64) std::atomic<std::size_t> write_{0};
  alignas(64) std::atomic<std::size_t> read_{0};
};

struct ToneVoice {
  bool active = false;
  std::uint8_t waveform = 0;
  float phase = 0.0F;
  float startHz = 440.0F;
  float endHz = 440.0F;
  float volume = 0.1F;
  float attackSeconds = 0.005F;
  float durationSeconds = 0.25F;
  float pan = 0.0F;
  float vibratoHz = 0.0F;
  float vibratoDepthHz = 0.0F;
  float vibratoPhase = 0.0F;
  float ageSeconds = 0.0F;
  float delaySend = 0.0F;
  float reverbSend = 0.0F;
  bool music = false;
};

struct NoiseVoice {
  bool active = false;
  bool music = false;
  bool highpass = false;
  float durationSeconds = 0.1F;
  float ageSeconds = 0.0F;
  float volume = 0.1F;
  float attackSeconds = 0.0F;
  float startHz = 1800.0F;
  float endHz = 1800.0F;
  float q = 0.8F;
  float pan = 0.0F;
  float delaySend = 0.0F;
  float reverbSend = 0.0F;
  float lowpassState = 0.0F;
  Biquad filter{};
};

struct PendingTone {
  bool active = false;
  std::uint64_t dueFrame = 0;
  ToneVoice voice{};
};

struct PendingNoise {
  bool active = false;
  std::uint64_t dueFrame = 0;
  NoiseVoice voice{};
};

template <std::size_t Size>
class DelayLine final {
 public:
  float read(std::size_t delaySamples) noexcept {
    const std::size_t delay = std::min(delaySamples, Size - 1U);
    const std::size_t position = (index_ + Size - delay) % Size;
    if (!std::isfinite(samples_[position])) samples_[position] = 0.0F;
    return samples_[position];
  }

  void write(float value) noexcept {
    samples_[index_] = Clamp(FiniteOrZero(value), -8.0F, 8.0F);
    index_ = (index_ + 1U) % Size;
  }

  void clear() noexcept {
    samples_.fill(0.0F);
    index_ = 0U;
  }

 private:
  std::array<float, Size> samples_{};
  std::size_t index_ = 0U;
};

class Effects final {
 public:
  Stereo process(Stereo dry, Stereo delayInput, Stereo reverbInput) noexcept {
    dry.left = FiniteOrZero(dry.left);
    dry.right = FiniteOrZero(dry.right);
    delayInput.left = FiniteOrZero(delayInput.left);
    delayInput.right = FiniteOrZero(delayInput.right);
    reverbInput.left = FiniteOrZero(reverbInput.left);
    reverbInput.right = FiniteOrZero(reverbInput.right);
    const float delayedL = delayLeft_.read(11520U);   // 240 ms
    const float delayedR = delayRight_.read(14880U);  // 310 ms
    delayLeft_.write(delayInput.left + delayedR * 0.28F);
    delayRight_.write(delayInput.right + delayedL * 0.28F);

    const float inputL = reverbInput.left + 0.10F * delayedL;
    const float inputR = reverbInput.right + 0.10F * delayedR;
    const float a = reverbA_.read(1423U);
    const float b = reverbB_.read(1889U);
    const float c = reverbC_.read(2437U);
    const float d = reverbD_.read(3163U);
    // Four delay lines form a damped feedback-delay network. The former
    // difference matrix had an eigenvalue magnitude of 1.32 and inevitably
    // diverged after about ten seconds. This signed cyclic matrix has row sum
    // magnitude 0.68, so its spectral radius is strictly below one.
    constexpr float feedback = 0.68F;
    reverbA_.write(inputL + feedback * b);
    reverbB_.write(inputR - feedback * c);
    reverbC_.write(inputL + feedback * d);
    reverbD_.write(inputR - feedback * a);
    const float wetL = 0.25F * (a + c);
    const float wetR = 0.25F * (b + d);

    dry.left += 0.18F * delayedL + 0.32F * wetL;
    dry.right += 0.18F * delayedR + 0.32F * wetR;
    return dry;
  }

  void clear() noexcept {
    delayLeft_.clear();
    delayRight_.clear();
    reverbA_.clear();
    reverbB_.clear();
    reverbC_.clear();
    reverbD_.clear();
  }

 private:
  DelayLine<16384> delayLeft_{};
  DelayLine<16384> delayRight_{};
  DelayLine<4096> reverbA_{};
  DelayLine<4096> reverbB_{};
  DelayLine<4096> reverbC_{};
  DelayLine<4096> reverbD_{};
};

}  // namespace

class Synthesizer::Impl final {
 public:
  Impl() noexcept { reset(); }

  bool update(const Parameters& parameters) noexcept {
    Command command;
    command.type = CommandType::Update;
    command.parameters = parameters;
    return commands_.push(command);
  }

  bool trigger(Event event) noexcept {
    Command command;
    command.type = CommandType::Trigger;
    command.event = event;
    return commands_.push(command);
  }

  bool setPaused(bool paused) noexcept {
    Command command;
    command.type = CommandType::Pause;
    command.paused = paused;
    return commands_.push(command);
  }

  void render(float* output, std::size_t frameCount) noexcept {
    if (output == nullptr) return;
    consumeCommands();
    for (std::size_t frame = 0; frame < frameCount; ++frame) {
      activatePending();
      Stereo sample{};
      Stereo delayInput{};
      Stereo reverbInput{};
      if (!paused_) {
        smoothParameters();
        scheduleContinuousAndMusic();
        renderEnvironment(sample);
        renderVoices(sample, delayInput, reverbInput);
        sample = effects_.process(sample, delayInput, reverbInput);
        sample.left = dcLeft_.process(sample.left);
        sample.right = dcRight_.process(sample.right);
        sample.left = SoftLimit(sample.left * smoothed_.masterVolume);
        sample.right = SoftLimit(sample.right * smoothed_.masterVolume);
      }
      output[frame * 2U] = sample.left;
      output[frame * 2U + 1U] = sample.right;
      ++frameClock_;
    }
  }

  void reset() noexcept {
    commands_.clearConsumerSide();
    target_ = Parameters{};
    smoothed_ = target_;
    paused_ = false;
    frameClock_ = 0;
    nextMusicFrame_ = 0.0;
    musicStep_ = 0;
    nextClickFrame_ = 0;
    windUpdateCountdown_ = 0;
    rollUpdateCountdown_ = 0;
    windFilter_.clear();
    rollFilter_.clear();
    surfFilter_.clear();
    surfFilter_.setLowpass(700.0F);
    brownState_ = 0.0F;
    surfBrownState_ = 0.0F;
    surfLfoPhase_ = 0.0F;
    dcLeft_.clear();
    dcRight_.clear();
    effects_.clear();
    for (auto& voice : tones_) voice = ToneVoice{};
    for (auto& voice : noises_) voice = NoiseVoice{};
    for (auto& pending : pendingTones_) pending = PendingTone{};
    for (auto& pending : pendingNoises_) pending = PendingNoise{};
  }

 private:
  static Parameters sanitize(Parameters value) noexcept {
    value.speed = Clamp(value.speed, 0.0F, 80.0F);
    value.cadence = Clamp(value.cadence, 0.0F, 240.0F);
    value.night = Clamp(value.night, 0.0F, 1.0F);
    value.masterVolume = Clamp(value.masterVolume, 0.0F, 1.0F);
    value.musicVolume = Clamp(value.musicVolume, 0.0F, 1.0F);
    value.effectsVolume = Clamp(value.effectsVolume, 0.0F, 1.0F);
    return value;
  }

  void consumeCommands() noexcept {
    Command command;
    while (commands_.pop(command)) {
      switch (command.type) {
        case CommandType::Update:
          target_ = sanitize(command.parameters);
          break;
        case CommandType::Trigger:
          scheduleEvent(command.event);
          break;
        case CommandType::Pause:
          paused_ = command.paused;
          if (!paused_) {
            nextMusicFrame_ = static_cast<double>(frameClock_) + 0.05 * kSampleRate;
          }
          break;
      }
    }
  }

  void smoothParameters() noexcept {
    // Precomputed 1-exp(-1/(sampleRate*tau)) for 100 ms and 35 ms.
    constexpr float slow = 0.00020831163F;
    constexpr float fast = 0.00059506018F;
    smoothed_.speed += slow * (target_.speed - smoothed_.speed);
    smoothed_.cadence += slow * (target_.cadence - smoothed_.cadence);
    smoothed_.night += slow * (target_.night - smoothed_.night);
    smoothed_.masterVolume += fast * (target_.masterVolume - smoothed_.masterVolume);
    smoothed_.musicVolume += slow * (target_.musicVolume - smoothed_.musicVolume);
    smoothed_.effectsVolume += fast * (target_.effectsVolume - smoothed_.effectsVolume);
    smoothed_.pedaling = target_.pedaling;
    smoothed_.airborne = target_.airborne;
    smoothed_.musicEnabled = target_.musicEnabled;
  }

  void scheduleContinuousAndMusic() noexcept {
    if (!smoothed_.pedaling && smoothed_.speed > 0.5F && frameClock_ >= nextClickFrame_) {
      NoiseVoice click;
      click.durationSeconds = 0.02F;
      click.volume = 0.05F;
      click.startHz = click.endHz = 3500.0F;
      click.highpass = true;
      startNoise(click);
      const float seconds = std::max(0.012F, 0.35F / smoothed_.speed);
      nextClickFrame_ = frameClock_ + static_cast<std::uint64_t>(seconds * kSampleRate);
    }

    if (!smoothed_.musicEnabled) return;
    if (nextMusicFrame_ <= 0.0 || nextMusicFrame_ < static_cast<double>(frameClock_)) {
      nextMusicFrame_ = static_cast<double>(frameClock_) + 0.05 * kSampleRate;
    }
    if (static_cast<double>(frameClock_) >= nextMusicFrame_) {
      const float bpm = Clamp(smoothed_.cadence > 0.0F ? smoothed_.cadence : 84.0F, 72.0F, 126.0F);
      const float sixteenthSeconds = 60.0F / bpm / 4.0F;
      scheduleMusicStep(musicStep_, sixteenthSeconds);
      const float swing = (musicStep_ & 1U) != 0U ? 0.92F : 1.08F;
      nextMusicFrame_ += static_cast<double>(sixteenthSeconds * swing * kSampleRate);
      musicStep_ = (musicStep_ + 1U) & 255U;
    }
  }

  void renderEnvironment(Stereo& output) noexcept {
    if (windUpdateCountdown_ == 0) {
      windFilter_.setBandpass(250.0F + smoothed_.speed * 70.0F, 0.6F);
      windUpdateCountdown_ = 64;
    }
    if (rollUpdateCountdown_ == 0) {
      rollFilter_.setLowpass(160.0F + smoothed_.speed * 22.0F);
      rollUpdateCountdown_ = 64;
    }
    --windUpdateCountdown_;
    --rollUpdateCountdown_;

    const float white = rng_.bipolar();
    const float windGain = std::min(0.5F, smoothed_.speed * smoothed_.speed * 0.0022F);
    const float wind = windFilter_.process(white) * windGain;

    brownState_ = (brownState_ + 0.02F * rng_.bipolar()) / 1.02F;
    const float brown = brownState_ * 3.5F;
    const float rollGain = smoothed_.airborne ? 0.0F : std::min(0.35F, smoothed_.speed * 0.028F);
    const float roll = rollFilter_.process(brown) * rollGain;

    surfBrownState_ = (surfBrownState_ + 0.02F * rng_.bipolar()) / 1.02F;
    const float surfNoise = surfFilter_.process(surfBrownState_ * 3.5F);
    const float surfLfo = std::sin(kTwoPi * surfLfoPhase_);
    AdvancePhase(surfLfoPhase_, 0.11F);
    const float surf = surfNoise * (0.12F + 0.08F * surfLfo);
    constexpr float surfPan = -0.6F;
    output.left += smoothed_.effectsVolume *
                   (0.70710678F * (wind + roll) + surf * EqualPowerLeft(surfPan));
    output.right += smoothed_.effectsVolume *
                    (0.70710678F * (wind + roll) + surf * EqualPowerRight(surfPan));
  }

  void renderVoices(Stereo& output, Stereo& delayInput, Stereo& reverbInput) noexcept {
    for (auto& voice : tones_) {
      if (!voice.active) continue;
      const float progress = Clamp(voice.ageSeconds / std::max(voice.durationSeconds, kTiny), 0.0F, 1.0F);
      float frequency = voice.startHz;
      if (voice.startHz > 0.0F && voice.endHz > 0.0F) {
        frequency = voice.startHz * std::pow(voice.endHz / voice.startHz, progress);
      }
      if (voice.vibratoDepthHz != 0.0F) {
        frequency += std::sin(kTwoPi * voice.vibratoPhase) * voice.vibratoDepthHz;
        AdvancePhase(voice.vibratoPhase, voice.vibratoHz);
      }
      const float attack = std::max(voice.attackSeconds, kInvSampleRate);
      const float envelope = voice.ageSeconds < attack
                                 ? voice.ageSeconds / attack
                                 : std::pow(kTiny, (voice.ageSeconds - attack) /
                                                      std::max(voice.durationSeconds - attack, kInvSampleRate));
      const float raw = WaveSample(voice.phase, voice.waveform) * envelope * voice.volume;
      AdvancePhase(voice.phase, std::max(frequency, 1.0F));
      const float bus = voice.music ? smoothed_.musicVolume : smoothed_.effectsVolume;
      const Stereo stereo{raw * EqualPowerLeft(voice.pan) * bus,
                          raw * EqualPowerRight(voice.pan) * bus};
      output += stereo;
      delayInput.left += stereo.left * voice.delaySend;
      delayInput.right += stereo.right * voice.delaySend;
      reverbInput.left += stereo.left * voice.reverbSend;
      reverbInput.right += stereo.right * voice.reverbSend;
      voice.ageSeconds += kInvSampleRate;
      if (voice.ageSeconds >= voice.durationSeconds) voice.active = false;
    }

    for (auto& voice : noises_) {
      if (!voice.active) continue;
      const float progress = Clamp(voice.ageSeconds / std::max(voice.durationSeconds, kTiny), 0.0F, 1.0F);
      const float frequency = voice.startHz > 0.0F && voice.endHz > 0.0F
                                  ? voice.startHz * std::pow(voice.endHz / voice.startHz, progress)
                                  : voice.startHz;
      if (voice.highpass) {
        const float coefficient = OnePoleCoefficient(frequency);
        const float input = rng_.bipolar();
        voice.lowpassState += coefficient * (input - voice.lowpassState);
        voice.filter.setBandpass(std::min(frequency * 1.8F, 15000.0F), 0.55F);
      } else {
        voice.filter.setBandpass(frequency, voice.q);
      }
      const float noise = rng_.bipolar();
      const float filtered = voice.highpass ? noise - voice.lowpassState : voice.filter.process(noise);
      const float attack = std::max(voice.attackSeconds, kInvSampleRate);
      const float attackEnvelope = voice.ageSeconds < attack ? voice.ageSeconds / attack : 1.0F;
      const float decayEnvelope = std::pow(kTiny, progress);
      const float raw = filtered * voice.volume * attackEnvelope * decayEnvelope;
      const float bus = voice.music ? smoothed_.musicVolume : smoothed_.effectsVolume;
      const Stereo stereo{raw * EqualPowerLeft(voice.pan) * bus,
                          raw * EqualPowerRight(voice.pan) * bus};
      output += stereo;
      delayInput.left += stereo.left * voice.delaySend;
      delayInput.right += stereo.right * voice.delaySend;
      reverbInput.left += stereo.left * voice.reverbSend;
      reverbInput.right += stereo.right * voice.reverbSend;
      voice.ageSeconds += kInvSampleRate;
      if (voice.ageSeconds >= voice.durationSeconds) voice.active = false;
    }
  }

  void activatePending() noexcept {
    for (auto& pending : pendingTones_) {
      if (pending.active && pending.dueFrame <= frameClock_) {
        startTone(pending.voice);
        pending.active = false;
      }
    }
    for (auto& pending : pendingNoises_) {
      if (pending.active && pending.dueFrame <= frameClock_) {
        startNoise(pending.voice);
        pending.active = false;
      }
    }
  }

  void startTone(ToneVoice voice) noexcept {
    for (auto& slot : tones_) {
      if (!slot.active) {
        voice.active = true;
        voice.ageSeconds = 0.0F;
        slot = voice;
        return;
      }
    }
    std::size_t oldest = 0;
    for (std::size_t i = 1; i < tones_.size(); ++i) {
      if (tones_[i].ageSeconds > tones_[oldest].ageSeconds) oldest = i;
    }
    voice.active = true;
    voice.ageSeconds = 0.0F;
    tones_[oldest] = voice;
  }

  void startNoise(NoiseVoice voice) noexcept {
    voice.active = true;
    voice.ageSeconds = 0.0F;
    voice.lowpassState = 0.0F;
    voice.filter.clear();
    if (!voice.highpass) voice.filter.setBandpass(voice.startHz, voice.q);
    for (auto& slot : noises_) {
      if (!slot.active) {
        slot = voice;
        return;
      }
    }
    std::size_t oldest = 0;
    for (std::size_t i = 1; i < noises_.size(); ++i) {
      if (noises_[i].ageSeconds > noises_[oldest].ageSeconds) oldest = i;
    }
    noises_[oldest] = voice;
  }

  void scheduleTone(std::uint64_t delayFrames, ToneVoice voice) noexcept {
    if (delayFrames == 0) {
      startTone(voice);
      return;
    }
    for (auto& slot : pendingTones_) {
      if (!slot.active) {
        slot.active = true;
        slot.dueFrame = frameClock_ + delayFrames;
        slot.voice = voice;
        return;
      }
    }
  }

  void scheduleNoise(std::uint64_t delayFrames, NoiseVoice voice) noexcept {
    if (delayFrames == 0) {
      startNoise(voice);
      return;
    }
    for (auto& slot : pendingNoises_) {
      if (!slot.active) {
        slot.active = true;
        slot.dueFrame = frameClock_ + delayFrames;
        slot.voice = voice;
        return;
      }
    }
  }

  static std::uint64_t secondsToFrames(float seconds) noexcept {
    return static_cast<std::uint64_t>(seconds * static_cast<float>(kSampleRate) + 0.5F);
  }

  void scheduleEvent(Event event) noexcept {
    switch (event) {
      case Event::Bell:
        scheduleBell();
        break;
      case Event::Honk:
        scheduleHonk();
        break;
      case Event::Gulp:
        scheduleGulp(false);
        break;
      case Event::GulpGolden:
        scheduleGulp(true);
        break;
      case Event::Splash:
        scheduleSplash();
        break;
      case Event::Thump:
        scheduleThump();
        break;
      case Event::Whoosh:
        scheduleWhoosh();
        break;
      case Event::Seagull:
        scheduleSeagull();
        break;
    }
  }

  void scheduleBell() noexcept {
    constexpr std::array<float, 4> ratios{1.0F, 2.63F, 4.17F, 5.43F};
    for (float offset : {0.0F, 0.16F}) {
      for (std::size_t index = 0; index < ratios.size(); ++index) {
        ToneVoice tone;
        tone.startHz = tone.endHz = 2350.0F * ratios[index] * std::exp2((index * 4.0F) / 1200.0F);
        tone.durationSeconds = 1.4F - static_cast<float>(index) * 0.25F;
        tone.volume = 0.18F / static_cast<float>(index + 1U);
        tone.attackSeconds = 0.005F;
        tone.reverbSend = 0.75F;
        scheduleTone(secondsToFrames(offset), tone);
      }
      ToneVoice shimmer;
      shimmer.startHz = shimmer.endHz = 2350.0F * 1.004F;
      shimmer.durationSeconds = 1.2F;
      shimmer.volume = 0.08F;
      shimmer.reverbSend = 0.35F;
      scheduleTone(secondsToFrames(offset), shimmer);
    }
  }

  void scheduleHonk() noexcept {
    ToneVoice honk;
    honk.waveform = 2;
    honk.startHz = 190.0F;
    honk.endHz = 240.0F;
    honk.durationSeconds = 0.08F;
    honk.volume = 0.48F;
    honk.attackSeconds = 0.03F;
    honk.vibratoHz = 28.0F;
    honk.vibratoDepthHz = 18.0F;
    honk.reverbSend = 0.45F;
    startTone(honk);
    honk.startHz = 240.0F;
    honk.endHz = 120.0F;
    honk.durationSeconds = 0.42F;
    honk.attackSeconds = 0.001F;
    scheduleTone(secondsToFrames(0.08F), honk);
    for (float formant : {720.0F, 1250.0F}) {
      ToneVoice nasal = honk;
      nasal.waveform = 1;
      nasal.startHz = nasal.endHz = formant;
      nasal.durationSeconds = 0.5F;
      nasal.volume = formant < 1000.0F ? 0.10F : 0.07F;
      nasal.attackSeconds = 0.03F;
      nasal.reverbSend = 0.5F;
      startTone(nasal);
    }
  }

  void scheduleGulp(bool golden) noexcept {
    ToneVoice gulp;
    gulp.startHz = 420.0F;
    gulp.endHz = 90.0F;
    gulp.durationSeconds = 0.18F;
    gulp.volume = 0.35F;
    startTone(gulp);
    gulp.startHz = 260.0F;
    gulp.endHz = 70.0F;
    gulp.durationSeconds = 0.20F;
    gulp.volume = 0.25F;
    scheduleTone(secondsToFrames(0.12F), gulp);

    constexpr std::array<int, 5> goldenNotes{79, 83, 86, 91, 95};
    constexpr std::array<int, 3> normalNotes{76, 81, 88};
    const std::size_t count = golden ? goldenNotes.size() : normalNotes.size();
    for (std::size_t i = 0; i < count; ++i) {
      const int note = golden ? goldenNotes[i] : normalNotes[i];
      ToneVoice collect;
      collect.waveform = 1;
      collect.startHz = collect.endHz = MidiToHz(note);
      collect.durationSeconds = 0.6F;
      collect.volume = 0.12F;
      collect.reverbSend = 0.75F;
      collect.delaySend = 0.22F;
      scheduleTone(secondsToFrames(0.05F + static_cast<float>(i) * 0.07F), collect);
    }
  }

  void scheduleSplash() noexcept {
    NoiseVoice splash;
    splash.durationSeconds = 0.55F;
    splash.volume = 0.30F;
    splash.startHz = 2400.0F;
    splash.endHz = 400.0F;
    splash.q = 0.8F;
    splash.pan = -0.5F;
    splash.reverbSend = 0.28F;
    startNoise(splash);
  }

  void scheduleThump() noexcept {
    ToneVoice thump;
    thump.startHz = 110.0F;
    thump.endHz = 45.0F;
    thump.durationSeconds = 0.25F;
    thump.volume = 0.5F;
    startTone(thump);
    NoiseVoice click;
    click.durationSeconds = 0.02F;
    click.volume = 0.2F;
    click.startHz = click.endHz = 3500.0F;
    click.highpass = true;
    startNoise(click);
  }

  void scheduleWhoosh() noexcept {
    NoiseVoice whoosh;
    whoosh.durationSeconds = 0.5F;
    whoosh.attackSeconds = 0.15F;
    whoosh.volume = 0.35F;
    whoosh.startHz = 300.0F;
    whoosh.endHz = 2200.0F;
    whoosh.q = 1.5F;
    whoosh.reverbSend = 0.18F;
    startNoise(whoosh);
  }

  void scheduleSeagull() noexcept {
    const int count = 2 + static_cast<int>(rng_.nextU32() % 3U);
    const float pan = -0.3F - rng_.unit() * 0.6F;
    for (int i = 0; i < count; ++i) {
      const float offset = static_cast<float>(i) * 0.28F;
      ToneVoice rise;
      rise.waveform = 2;
      rise.startHz = 1500.0F;
      rise.endHz = 2300.0F;
      rise.durationSeconds = 0.06F;
      rise.volume = 0.05F;
      rise.attackSeconds = 0.03F;
      rise.pan = pan;
      rise.reverbSend = 0.8F;
      scheduleTone(secondsToFrames(offset), rise);
      ToneVoice fall = rise;
      fall.startHz = 2300.0F;
      fall.endHz = 1100.0F;
      fall.durationSeconds = 0.16F;
      fall.attackSeconds = 0.001F;
      scheduleTone(secondsToFrames(offset + 0.06F), fall);
    }
  }

  void scheduleMusicStep(std::uint32_t step, float sixteenthSeconds) noexcept {
    constexpr int chords[4][5] = {
        {50, 57, 61, 64, 66},  // Dmaj9
        {47, 54, 57, 61, 62},  // Bm9
        {43, 50, 54, 57, 59},  // Gmaj9
        {45, 52, 55, 59, 61},  // A13
    };
    constexpr int arpeggio[8] = {0, 2, 3, 4, 1, 3, 2, 4};
    const std::uint32_t bar = (step / 16U) % 4U;
    const std::uint32_t position = step % 16U;
    const int* chord = chords[bar];

    if (position == 0U) {
      for (std::size_t index = 0; index < 5; ++index) {
        ToneVoice pad;
        pad.waveform = 1;
        const float detune = (index & 1U) != 0U ? 6.0F : -6.0F;
        pad.startHz = pad.endHz = MidiToHz(chord[index] + 12) * std::exp2(detune / 1200.0F);
        pad.durationSeconds = sixteenthSeconds * 16.0F;
        pad.volume = 0.045F;
        pad.attackSeconds = 0.4F;
        pad.reverbSend = 0.5F;
        pad.music = true;
        startTone(pad);
      }
      ToneVoice bass;
      bass.startHz = bass.endHz = MidiToHz(chord[0] - 12);
      bass.durationSeconds = sixteenthSeconds * 8.0F;
      bass.volume = 0.16F;
      bass.attackSeconds = 0.02F;
      bass.music = true;
      startTone(bass);
    }
    if (position == 8U) {
      ToneVoice bass;
      bass.startHz = bass.endHz = MidiToHz(chord[0] - 12 + ((bar & 1U) != 0U ? 7 : 0));
      bass.durationSeconds = sixteenthSeconds * 6.0F;
      bass.volume = 0.12F;
      bass.attackSeconds = 0.02F;
      bass.music = true;
      startTone(bass);
    }
    if ((position & 1U) == 0U) {
      const int index = arpeggio[(position / 2U) % 8U];
      const int octave = position >= 8U && (bar & 1U) != 0U ? 24 : 12;
      const float frequency = MidiToHz(chord[index] + octave);
      ToneVoice arp;
      arp.startHz = arp.endHz = frequency;
      arp.durationSeconds = sixteenthSeconds * 3.5F;
      arp.volume = 0.07F * (smoothed_.night > 0.5F ? 0.8F : 1.0F);
      arp.reverbSend = 0.45F;
      arp.delaySend = 0.18F;
      arp.music = true;
      startTone(arp);
      ToneVoice harmonic = arp;
      harmonic.startHz = harmonic.endHz = frequency * 2.001F;
      harmonic.durationSeconds = sixteenthSeconds * 1.5F;
      harmonic.volume = 0.012F;
      startTone(harmonic);
    }
    if (smoothed_.night > 0.6F) return;

    if (position == 0U || position == 10U) {
      ToneVoice kick;
      kick.startHz = 120.0F;
      kick.endHz = 42.0F;
      kick.durationSeconds = 0.22F;
      kick.volume = 0.30F;
      kick.music = true;
      startTone(kick);
    }
    if (position == 4U || position == 12U) {
      NoiseVoice snare;
      snare.durationSeconds = 0.16F;
      snare.volume = 0.07F;
      snare.startHz = snare.endHz = 1800.0F;
      snare.q = 0.8F;
      snare.music = true;
      snare.reverbSend = 0.15F;
      startNoise(snare);
    }
    if ((position & 1U) == 0U) {
      NoiseVoice hat;
      hat.durationSeconds = 0.05F;
      hat.volume = position % 4U == 2U ? 0.035F : 0.018F;
      hat.startHz = hat.endHz = 7000.0F;
      hat.highpass = true;
      hat.music = true;
      startNoise(hat);
    }
  }

  SpscQueue<Command, 256> commands_{};
  Parameters target_{};
  Parameters smoothed_{};
  bool paused_ = false;
  Rng rng_{};
  std::uint64_t frameClock_ = 0;
  std::uint64_t nextClickFrame_ = 0;
  double nextMusicFrame_ = 0.0;
  std::uint32_t musicStep_ = 0;
  std::uint32_t windUpdateCountdown_ = 0;
  std::uint32_t rollUpdateCountdown_ = 0;
  float brownState_ = 0.0F;
  float surfBrownState_ = 0.0F;
  float surfLfoPhase_ = 0.0F;
  Biquad windFilter_{};
  Biquad rollFilter_{};
  Biquad surfFilter_{};
  DcBlock dcLeft_{};
  DcBlock dcRight_{};
  std::array<ToneVoice, 64> tones_{};
  std::array<NoiseVoice, 24> noises_{};
  std::array<PendingTone, 48> pendingTones_{};
  std::array<PendingNoise, 16> pendingNoises_{};
  Effects effects_{};
};

Synthesizer::Synthesizer() : impl_(std::make_unique<Impl>()) {}
Synthesizer::~Synthesizer() = default;

bool Synthesizer::update(const Parameters& parameters) noexcept { return impl_->update(parameters); }
bool Synthesizer::trigger(Event event) noexcept { return impl_->trigger(event); }
bool Synthesizer::setPaused(bool paused) noexcept { return impl_->setPaused(paused); }
void Synthesizer::render(float* output, std::size_t frameCount) noexcept {
  impl_->render(output, frameCount);
}
void Synthesizer::reset() noexcept { impl_->reset(); }

}  // namespace pelican::audio
