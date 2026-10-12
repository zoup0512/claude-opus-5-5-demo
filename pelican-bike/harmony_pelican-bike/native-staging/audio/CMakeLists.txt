cmake_minimum_required(VERSION 3.16)
project(pelican_audio LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(PELICAN_AUDIO_BUILD_TESTS "Build host DSP tests" ON)
option(PELICAN_AUDIO_BUILD_WAV_RENDERER "Build host WAV renderer" ON)

add_library(pelican_audio STATIC
    src/synthesizer.cpp
    src/audio_engine.cpp)
add_library(pelican::audio ALIAS pelican_audio)

target_include_directories(pelican_audio
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>)

target_compile_features(pelican_audio PUBLIC cxx_std_17)

if(MSVC)
  target_compile_options(pelican_audio PRIVATE /W4 /permissive- /EHsc)
else()
  target_compile_options(pelican_audio PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "OHOS")
  # The SDK exports OHAudio as libohaudio.so. The implementation itself also
  # uses __has_include so host builds remain dependency-free.
  target_link_libraries(pelican_audio PUBLIC libohaudio.so)
  set(PELICAN_AUDIO_BUILD_TESTS OFF CACHE BOOL "Host-only tests" FORCE)
  set(PELICAN_AUDIO_BUILD_WAV_RENDERER OFF CACHE BOOL "Host-only renderer" FORCE)
endif()

if(PELICAN_AUDIO_BUILD_WAV_RENDERER)
  add_executable(pelican_audio_wav tools/host_wav_renderer.cpp)
  target_link_libraries(pelican_audio_wav PRIVATE pelican_audio)
endif()

if(PELICAN_AUDIO_BUILD_TESTS)
  enable_testing()
  add_executable(pelican_audio_tests tests/synth_tests.cpp)
  target_link_libraries(pelican_audio_tests PRIVATE pelican_audio)
  add_test(NAME pelican_audio_tests COMMAND pelican_audio_tests)
  if(PELICAN_AUDIO_BUILD_WAV_RENDERER)
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/tests/output")
    add_test(
      NAME pelican_audio_render_20s
      COMMAND pelican_audio_wav
              "${CMAKE_CURRENT_SOURCE_DIR}/tests/output/pelican_audio_20s.wav"
              20)
  endif()
endif()
