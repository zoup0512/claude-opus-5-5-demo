# Pelican Bike audio integration notes

The implementation is staged in `native-staging/audio` and intentionally does not change the target application's root configuration or entry module.

## Files to consume

- Public API: `include/pelican_audio/audio_engine.h`, `include/pelican_audio/synthesizer.h`
- DSP: `src/synthesizer.cpp`
- Harmony OHAudio adapter: `src/audio_engine.cpp`
- Standalone build: `CMakeLists.txt`

For the final app integration, add the staged directory with `add_subdirectory` from the app's native CMake file and link the existing native target to `pelican_audio`. No ArkTS/N-API wrapper is included because this task is constrained to the staging and documentation directories; the app can map its own lifecycle and game state to the C++ API.

## Source behavior mapping

The DSP retains the original web implementation's important constants and sequencing:

| Web behavior | Native behavior |
| --- | --- |
| Wind gain | `min(0.5, speed² * 0.0022)` |
| Wind center | `250 + speed * 70` Hz, Q 0.6 |
| Rolling gain | airborne ? 0 : `min(0.35, speed * 0.028)` |
| Rolling cutoff | `160 + speed * 22` Hz |
| Surf | brown noise, 700 Hz lowpass, 0.11 Hz LFO, pan -0.6 |
| Freewheel | 3.5 kHz high-passed click, period `max(0.012, 0.35/speed)` |
| Bell | base 2350 Hz, ratios 1/2.63/4.17/5.43, strikes at 0 and 0.16 s |
| Honk | 190→240→120 Hz with 28 Hz vibrato and 720/1250 Hz nasal components |
| Harmony | Dmaj9, Bm9, Gmaj9, A13 |
| Tempo | cadence clamped to 72–126 BPM |
| Groove | sixteenth-note duration alternates 1.08/0.92 |
| Night | `night > 0.6` keeps atmosphere/arpeggio and suppresses drums |

All event and music voices use fixed pools. If every slot is busy, active voices may be stolen or an excessive deferred voice may be dropped rather than allocating memory in the callback.

## Thread contract

- Game thread: `start`, `stop`, `setPaused`, `update`, `trigger`.
- RT audio thread: internal OHAudio callback and `Synthesizer::render` only.
- `update`/`trigger` are SPSC operations. There must be one producer.
- Continuous state can be coalesced by the game: submit the latest state each tick; if the queue is full, retry the newest state later rather than replaying stale states.

## OHAudio API 24 details

The adapter is compiled only when `__OHOS__` is defined and `__has_include(<ohaudio/native_audiostreambuilder.h>)` succeeds. It configures 48 kHz stereo PCM, fast latency, and game usage.

It first creates an `AUDIOSTREAM_SAMPLE_F32LE` renderer. If any builder/generation step fails, it destroys partial resources and retries with `AUDIOSTREAM_SAMPLE_S16LE`. Both paths run exactly the same float DSP. The S16 path converts from a preallocated fixed buffer after soft limiting.

The write callback signature is `OH_AudioData_Callback_Result` and returns `AUDIO_DATA_CALLBACK_RESULT_VALID` after filling the buffer. It has no locks, heap allocation, or logging.

## Validation artifact

The host test target renders a deterministic 20-second scenario containing every requested event plus daytime/nighttime music, coasting clicks, airborne rolling-noise suppression, and changing speed/cadence. It writes `native-staging/audio/tests/output/pelican_audio_20s.wav` and validates finite samples, peak, RMS, and stereo difference. An identical review copy is at `docs/audio/pelican-audio-test.wav`.

The validated render contains 960,000 frames at 48 kHz stereo; float-DSP metrics were `finite=yes`, peak `0.376652`, RMS `0.055731`, and mean left/right difference `0.008469`.
