#include "pelican_audio/synthesizer.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <string>
#include <vector>

namespace {

using pelican::audio::Event;
using pelican::audio::Parameters;
using pelican::audio::Synthesizer;
using pelican::audio::kChannelCount;
using pelican::audio::kSampleRate;

void WriteU16(std::ostream& stream, std::uint16_t value) {
  const char bytes[2] = {static_cast<char>(value & 0xffU),
                         static_cast<char>((value >> 8U) & 0xffU)};
  stream.write(bytes, sizeof(bytes));
}

void WriteU32(std::ostream& stream, std::uint32_t value) {
  const char bytes[4] = {static_cast<char>(value & 0xffU),
                         static_cast<char>((value >> 8U) & 0xffU),
                         static_cast<char>((value >> 16U) & 0xffU),
                         static_cast<char>((value >> 24U) & 0xffU)};
  stream.write(bytes, sizeof(bytes));
}

void WriteWavHeader(std::ostream& stream, std::uint32_t frameCount) {
  constexpr std::uint16_t bitsPerSample = 16;
  constexpr std::uint16_t blockAlign = kChannelCount * bitsPerSample / 8U;
  constexpr std::uint32_t byteRate = kSampleRate * blockAlign;
  const std::uint32_t dataBytes = frameCount * blockAlign;
  stream.write("RIFF", 4);
  WriteU32(stream, 36U + dataBytes);
  stream.write("WAVE", 4);
  stream.write("fmt ", 4);
  WriteU32(stream, 16U);
  WriteU16(stream, 1U);
  WriteU16(stream, static_cast<std::uint16_t>(kChannelCount));
  WriteU32(stream, kSampleRate);
  WriteU32(stream, byteRate);
  WriteU16(stream, blockAlign);
  WriteU16(stream, bitsPerSample);
  stream.write("data", 4);
  WriteU32(stream, dataBytes);
}

std::int16_t ToPcm16(float sample) {
  sample = std::max(-1.0F, std::min(1.0F, sample));
  return static_cast<std::int16_t>(std::lround(sample * 32767.0F));
}

Parameters ScenarioAt(double seconds) {
  Parameters parameters;
  parameters.masterVolume = 0.8F;
  parameters.musicVolume = 0.55F;
  parameters.effectsVolume = 0.9F;
  if (seconds < 5.0) {
    parameters.speed = static_cast<float>(3.0 + seconds * 2.6);
    parameters.cadence = static_cast<float>(78.0 + seconds * 3.0);
  } else if (seconds < 10.0) {
    parameters.speed = 18.0F;
    parameters.cadence = 112.0F;
    parameters.pedaling = seconds < 7.0 || seconds >= 9.2;
  } else if (seconds < 15.0) {
    parameters.speed = 11.0F;
    parameters.cadence = 96.0F;
    parameters.night = 0.82F;  // Exercises the night > 0.6 drum gate.
  } else {
    parameters.speed = 20.0F - static_cast<float>((seconds - 15.0) * 2.2);
    parameters.cadence = 126.0F;
    parameters.night = 0.25F;
    parameters.airborne = seconds >= 16.0 && seconds < 16.8;
  }
  return parameters;
}

struct TimedEvent {
  double seconds;
  Event event;
};

constexpr TimedEvent kEvents[] = {
    {0.70, Event::Bell},       {2.25, Event::Honk},       {4.00, Event::Gulp},
    {5.40, Event::GulpGolden}, {7.15, Event::Splash},     {8.60, Event::Thump},
    {10.30, Event::Whoosh},    {12.25, Event::Seagull},   {15.10, Event::Bell},
    {17.30, Event::Splash},    {18.40, Event::Seagull},
};

}  // namespace

int main(int argc, char** argv) {
  const std::string path = argc > 1 ? argv[1] : "pelican_audio_20s.wav";
  const double duration = argc > 2 ? std::strtod(argv[2], nullptr) : 20.0;
  if (!(duration > 0.0 && duration <= 600.0)) {
    std::cerr << "duration must be in (0, 600] seconds\n";
    return 2;
  }
  const auto totalFrames = static_cast<std::uint32_t>(std::llround(duration * kSampleRate));
  std::ofstream wav(path, std::ios::binary | std::ios::trunc);
  if (!wav) {
    std::cerr << "cannot open output: " << path << '\n';
    return 2;
  }
  WriteWavHeader(wav, totalFrames);

  Synthesizer synthesizer;
  constexpr std::size_t blockFrames = 256;
  std::vector<float> floating(blockFrames * kChannelCount);
  std::vector<std::int16_t> pcm(blockFrames * kChannelCount);
  std::size_t nextEvent = 0;
  double sumSquares = 0.0;
  double stereoDifference = 0.0;
  float peak = 0.0F;
  bool finite = true;

  for (std::uint32_t firstFrame = 0; firstFrame < totalFrames;) {
    const std::size_t frames = std::min<std::size_t>(blockFrames, totalFrames - firstFrame);
    const double seconds = static_cast<double>(firstFrame) / kSampleRate;
    if (!synthesizer.update(ScenarioAt(seconds))) {
      std::cerr << "command queue unexpectedly full during scenario update\n";
      return 3;
    }
    while (nextEvent < std::size(kEvents) && kEvents[nextEvent].seconds <= seconds) {
      if (!synthesizer.trigger(kEvents[nextEvent].event)) {
        std::cerr << "command queue unexpectedly full during event trigger\n";
        return 3;
      }
      ++nextEvent;
    }
    synthesizer.render(floating.data(), frames);
    const std::size_t samples = frames * kChannelCount;
    for (std::size_t sample = 0; sample < samples; ++sample) {
      const float value = floating[sample];
      finite = finite && std::isfinite(value);
      peak = std::max(peak, std::fabs(value));
      sumSquares += static_cast<double>(value) * value;
      pcm[sample] = ToPcm16(value);
    }
    for (std::size_t frame = 0; frame < frames; ++frame) {
      stereoDifference += std::fabs(static_cast<double>(floating[frame * 2U]) -
                                    floating[frame * 2U + 1U]);
    }
    wav.write(reinterpret_cast<const char*>(pcm.data()),
              static_cast<std::streamsize>(samples * sizeof(std::int16_t)));
    firstFrame += static_cast<std::uint32_t>(frames);
  }
  wav.close();
  if (!wav) {
    std::cerr << "failed while writing output: " << path << '\n';
    return 2;
  }

  const double rms = std::sqrt(sumSquares /
                               (static_cast<double>(totalFrames) * kChannelCount));
  const double meanStereoDifference = stereoDifference / totalFrames;
  std::cout << std::fixed << std::setprecision(6)
            << "wav=" << path << " duration=" << duration << "s frames=" << totalFrames
            << " finite=" << (finite ? "yes" : "no") << " peak=" << peak
            << " rms=" << rms << " stereoDiff=" << meanStereoDifference << '\n';

  const bool healthy = finite && peak >= 0.05F && peak <= 1.0001F && rms >= 0.005 &&
                       rms <= 0.60 && meanStereoDifference >= 0.0001;
  if (!healthy) {
    std::cerr << "audio validation failed\n";
    return 4;
  }
  return 0;
}
