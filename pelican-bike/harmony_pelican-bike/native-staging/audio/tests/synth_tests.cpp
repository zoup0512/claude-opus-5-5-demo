#include "pelican_audio/audio_engine.h"
#include "pelican_audio/synthesizer.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <new>

namespace {

std::atomic<bool> gTrackAllocations{false};
std::atomic<std::uint64_t> gAllocationCount{0};

using pelican::audio::Event;
using pelican::audio::Parameters;
using pelican::audio::Synthesizer;
using pelican::audio::kChannelCount;
using pelican::audio::kSampleRate;

struct Metrics {
  bool finite = true;
  float peak = 0.0F;
  double rms = 0.0;
  double difference = 0.0;
};

Metrics Analyze(const float* samples, std::size_t frames) {
  Metrics metrics;
  double squares = 0.0;
  double difference = 0.0;
  for (std::size_t frame = 0; frame < frames; ++frame) {
    const float left = samples[frame * 2U];
    const float right = samples[frame * 2U + 1U];
    metrics.finite = metrics.finite && std::isfinite(left) && std::isfinite(right);
    metrics.peak = std::max(metrics.peak, std::max(std::fabs(left), std::fabs(right)));
    squares += static_cast<double>(left) * left + static_cast<double>(right) * right;
    difference += std::fabs(static_cast<double>(left) - right);
  }
  metrics.rms = std::sqrt(squares / static_cast<double>(frames * kChannelCount));
  metrics.difference = difference / static_cast<double>(frames);
  return metrics;
}

bool Expect(bool condition, const char* message) {
  if (!condition) std::cerr << "FAIL: " << message << '\n';
  return condition;
}

bool TestFiniteAndEvents() {
  Synthesizer synth;
  Parameters parameters;
  parameters.speed = 16.0F;
  parameters.cadence = 118.0F;
  parameters.masterVolume = 1.0F;
  parameters.musicVolume = 0.75F;
  parameters.effectsVolume = 1.0F;
  if (!synth.update(parameters)) return false;
  for (Event event : {Event::Bell, Event::Honk, Event::Gulp, Event::GulpGolden,
                      Event::Splash, Event::Thump, Event::Whoosh, Event::Seagull}) {
    if (!synth.trigger(event)) return false;
  }

  constexpr std::size_t blockFrames = 256;
  constexpr std::size_t blockCount = 4U * kSampleRate / blockFrames;
  std::array<float, blockFrames * kChannelCount> block{};
  double squares = 0.0;
  float peak = 0.0F;
  bool finite = true;
  for (std::size_t blockIndex = 0; blockIndex < blockCount; ++blockIndex) {
    synth.render(block.data(), blockFrames);
    const Metrics metrics = Analyze(block.data(), blockFrames);
    finite = finite && metrics.finite;
    peak = std::max(peak, metrics.peak);
    squares += metrics.rms * metrics.rms;
  }
  const double aggregateRms = std::sqrt(squares / blockCount);
  return Expect(finite, "event mix must contain only finite samples") &&
         Expect(peak > 0.05F && peak <= 1.0001F, "soft-limited peak must be audible and bounded") &&
         Expect(aggregateRms > 0.01, "event mix RMS must be non-silent");
}

bool TestPauseAndStereoSurf() {
  Synthesizer synth;
  Parameters parameters;
  parameters.speed = 0.0F;
  parameters.musicEnabled = false;
  parameters.effectsVolume = 1.0F;
  if (!synth.update(parameters)) return false;
  constexpr std::size_t frames = 4096;
  std::array<float, frames * kChannelCount> output{};
  synth.render(output.data(), frames);
  const Metrics surf = Analyze(output.data(), frames);
  if (!Expect(surf.difference > 0.0001, "left-panned surf must produce stereo difference")) return false;

  if (!synth.setPaused(true)) return false;
  output.fill(1.0F);
  synth.render(output.data(), frames);
  for (float sample : output) {
    if (!Expect(sample == 0.0F, "paused render must produce exact silence")) return false;
  }
  return true;
}

bool TestBoundedQueueAndNoRenderAllocations() {
  Synthesizer synth;
  Parameters parameters;
  std::size_t accepted = 0;
  while (synth.update(parameters)) ++accepted;
  if (!Expect(accepted > 0 && accepted < 300, "SPSC queue must be bounded")) return false;
  std::array<float, 512 * kChannelCount> output{};
  synth.render(output.data(), 512);
  if (!Expect(synth.update(parameters), "consumer must free SPSC queue capacity")) return false;

  gAllocationCount.store(0, std::memory_order_relaxed);
  gTrackAllocations.store(true, std::memory_order_release);
  for (int i = 0; i < 100; ++i) synth.render(output.data(), 512);
  gTrackAllocations.store(false, std::memory_order_release);
  return Expect(gAllocationCount.load(std::memory_order_relaxed) == 0,
                "render callback must not allocate");
}

bool TestCadenceClampAndNight() {
  Synthesizer synth;
  Parameters parameters;
  parameters.speed = 8.0F;
  parameters.cadence = 400.0F;  // Must clamp to 126 BPM.
  parameters.night = 1.0F;      // Must suppress drums while retaining ambience/music.
  parameters.musicEnabled = true;
  if (!synth.update(parameters)) return false;
  constexpr std::size_t frames = 2U * kSampleRate;
  constexpr std::size_t blockFrames = 256;
  std::array<float, blockFrames * kChannelCount> output{};
  double squares = 0.0;
  std::size_t rendered = 0;
  while (rendered < frames) {
    const std::size_t count = std::min(blockFrames, frames - rendered);
    synth.render(output.data(), count);
    const Metrics metrics = Analyze(output.data(), count);
    if (!metrics.finite) return false;
    squares += metrics.rms * metrics.rms * count;
    rendered += count;
  }
  const double rms = std::sqrt(squares / frames);
  return Expect(rms > 0.003, "night mix must retain ambient music");
}

bool TestTwentySecondIntegratedRender() {
  Synthesizer synth;
  constexpr std::size_t blockFrames = 256;
  constexpr std::size_t totalFrames = 20U * kSampleRate;
  constexpr std::array<Event, 8> events{
      Event::Bell, Event::Honk, Event::Gulp, Event::GulpGolden,
      Event::Splash, Event::Thump, Event::Whoosh, Event::Seagull};
  constexpr std::array<double, 10> eventTimes{0.7, 2.2, 4.0, 5.4, 7.1,
                                               8.6, 10.3, 12.2, 15.1, 18.2};
  std::array<float, blockFrames * kChannelCount> output{};
  std::size_t nextEvent = 0;
  double squareSum = 0.0;
  double differenceSum = 0.0;
  float peak = 0.0F;

  for (std::size_t firstFrame = 0; firstFrame < totalFrames; firstFrame += blockFrames) {
    const double seconds = static_cast<double>(firstFrame) / kSampleRate;
    Parameters parameters;
    parameters.masterVolume = 0.8F;
    parameters.musicVolume = 0.55F;
    parameters.effectsVolume = 0.9F;
    parameters.speed = seconds < 10.0 ? static_cast<float>(4.0 + 1.4 * seconds)
                                     : static_cast<float>(18.0 - 0.65 * (seconds - 10.0));
    parameters.cadence = seconds < 10.0 ? static_cast<float>(72.0 + 5.4 * seconds) : 140.0F;
    parameters.night = seconds >= 10.0 && seconds < 15.0 ? 0.85F : 0.2F;
    parameters.pedaling = !(seconds >= 6.0 && seconds < 8.5);
    parameters.airborne = seconds >= 16.0 && seconds < 16.8;
    if (!synth.update(parameters)) return false;
    while (nextEvent < eventTimes.size() && eventTimes[nextEvent] <= seconds) {
      if (!synth.trigger(events[nextEvent % events.size()])) return false;
      ++nextEvent;
    }

    const std::size_t count = std::min(blockFrames, totalFrames - firstFrame);
    synth.render(output.data(), count);
    for (std::size_t frame = 0; frame < count; ++frame) {
      const float left = output[frame * 2U];
      const float right = output[frame * 2U + 1U];
      if (!Expect(std::isfinite(left) && std::isfinite(right),
                  "20 second integrated render must remain finite")) {
        return false;
      }
      peak = std::max(peak, std::max(std::fabs(left), std::fabs(right)));
      squareSum += static_cast<double>(left) * left + static_cast<double>(right) * right;
      differenceSum += std::fabs(static_cast<double>(left) - right);
    }
  }
  const double rms = std::sqrt(squareSum / (totalFrames * kChannelCount));
  const double stereoDifference = differenceSum / totalFrames;
  return Expect(peak > 0.05F && peak <= 1.0001F,
                "20 second integrated peak must be audible and limited") &&
         Expect(rms > 0.005 && rms < 0.6, "20 second integrated RMS must be healthy") &&
         Expect(stereoDifference > 0.0001, "20 second integrated render must remain stereo");
}

}  // namespace

void* operator new(std::size_t size) {
  if (gTrackAllocations.load(std::memory_order_acquire)) {
    gAllocationCount.fetch_add(1, std::memory_order_relaxed);
  }
  if (void* pointer = std::malloc(size)) return pointer;
  throw std::bad_alloc();
}

void* operator new[](std::size_t size) {
  if (gTrackAllocations.load(std::memory_order_acquire)) {
    gAllocationCount.fetch_add(1, std::memory_order_relaxed);
  }
  if (void* pointer = std::malloc(size)) return pointer;
  throw std::bad_alloc();
}

void operator delete(void* pointer) noexcept { std::free(pointer); }
void operator delete[](void* pointer) noexcept { std::free(pointer); }
void operator delete(void* pointer, std::size_t) noexcept { std::free(pointer); }
void operator delete[](void* pointer, std::size_t) noexcept { std::free(pointer); }

int main() {
  bool ok = true;
  ok = TestFiniteAndEvents() && ok;
  ok = TestPauseAndStereoSurf() && ok;
  ok = TestBoundedQueueAndNoRenderAllocations() && ok;
  ok = TestCadenceClampAndNight() && ok;
  ok = TestTwentySecondIntegratedRender() && ok;
  ok = Expect(!pelican::audio::AudioEngine::nativeBackendAvailable(),
              "host test build must select the fallback backend") && ok;
  if (ok) std::cout << "All pelican audio tests passed\n";
  return ok ? 0 : 1;
}
