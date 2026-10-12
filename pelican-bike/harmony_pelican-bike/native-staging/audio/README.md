# Pelican Bike native audio

C++17, dependency-free real-time synthesis module adapted from the web project's `src/audio.js`. The same `Synthesizer::render(float*, frames)` path feeds Harmony OHAudio and the host WAV renderer.

## Features

- 48 kHz, stereo, interleaved callback rendering.
- RT callback performs no locks, allocations, logging, or file I/O.
- Bounded SPSC command queue for game-thread parameter updates and events.
- Wind white-noise bandpass, rolling brown-noise lowpass, left-panned 0.11 Hz surf, freewheel clicks.
- Bell, honk, normal/golden gulp, splash, thump, whoosh, and seagull events.
- Dmaj9–Bm9–Gmaj9–A13 generative music with bass, arpeggio, kick, snare, hat, swing, cadence-clamped BPM, and night drum suppression.
- Fixed-memory delay/reverb and final soft limiter.
- OHAudio API 24-compatible backend: F32LE first, S16LE fallback.

## Public API

```cpp
#include "pelican_audio/audio_engine.h"

pelican::audio::AudioEngine audio;
if (audio.start()) {
  pelican::audio::Parameters p;
  p.speed = speed;
  p.cadence = cadence;
  p.night = night;
  p.pedaling = pedaling;
  p.airborne = airborne;
  audio.update(p);                         // one producer/game thread
  audio.trigger(pelican::audio::Event::Bell);
}
// Ability lifecycle:
audio.setPaused(true);
audio.setPaused(false);
audio.stop();
```

`update`, `trigger`, and `setPaused` return `false` if their bounded queue cannot accept another command. Keep a single producer thread, retry/coalesce continuous updates on the next game tick, and do not call these producer methods from multiple threads concurrently.

`AudioEngine` owns the renderer and can be started/stopped repeatedly. Destruction calls `stop()`. The lifecycle mutex is only used on the game/control side; the OHAudio write callback never touches it.

## Integrating in a Harmony CMake target

Either include this directory with `add_subdirectory(...)` and link `pelican_audio`, or compile `src/synthesizer.cpp` and `src/audio_engine.cpp` into the existing native target. The module's CMake links `libohaudio.so` only when `CMAKE_SYSTEM_NAME` is `OHOS`.

The native backend uses:

- `OH_AudioStreamBuilder_SetSamplingRate(..., 48000)`
- `SetChannelCount(..., 2)`
- `AUDIOSTREAM_SAMPLE_F32LE`, falling back to `AUDIOSTREAM_SAMPLE_S16LE`
- `AUDIOSTREAM_ENCODING_TYPE_RAW`
- `AUDIOSTREAM_LATENCY_MODE_FAST`
- `AUDIOSTREAM_USAGE_GAME`
- `OH_AudioStreamBuilder_SetRendererWriteDataCallback`

The callback returns `AUDIO_DATA_CALLBACK_RESULT_VALID` after filling the requested buffer. The S16 fallback renders float DSP into a fixed member buffer and performs only final sample conversion.

## Host build and 20-second validation

From a Visual Studio developer shell:

```powershell
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
ctest --test-dir build --output-on-failure
```

Or use a Visual Studio generator. The test suite checks finite output, bounded peak, non-zero RMS, stereo surf, exact pause silence, bounded SPSC behavior, and zero callback allocations. `pelican_audio_render_20s` writes:

`tests/output/pelican_audio_20s.wav`

A validated 20-second WAV is checked into this staging output directory. The reference run produced 960,000 stereo frames with `finite=yes`, peak `0.376652`, RMS `0.055731`, and mean stereo difference `0.008469`.

The renderer exits non-zero unless samples are finite and peak/RMS/stereo metrics are healthy. A custom run is:

```powershell
build\pelican_audio_wav.exe tests\output\pelican_audio_20s.wav 20
```

## Real-time and lifecycle assumptions

- Construct/reset only while the callback is stopped.
- One game-thread producer and one audio-thread consumer.
- Do not log from `Synthesizer::render` or the OHAudio write callback.
- OHAudio stop/release happens before the synthesizer can be destroyed.
- When paused, the native stream is paused and any direct DSP render produces exact silence.
