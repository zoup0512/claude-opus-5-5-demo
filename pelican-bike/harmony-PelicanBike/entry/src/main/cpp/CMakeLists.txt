cmake_minimum_required(VERSION 3.16)
project(pelican_native_integration LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Works both in integration-staging/native and after this directory's contents
# directly replace entry/src/main/cpp.
set(PELICAN_REPO_ROOT "")
foreach(PELICAN_ROOT_CANDIDATE
        "${CMAKE_CURRENT_LIST_DIR}/../.."
        "${CMAKE_CURRENT_LIST_DIR}/../../../..")
    get_filename_component(PELICAN_ROOT_CANDIDATE_ABS "${PELICAN_ROOT_CANDIDATE}" ABSOLUTE)
    if(EXISTS "${PELICAN_ROOT_CANDIDATE_ABS}/native-staging/coregame/CMakeLists.txt" AND
       EXISTS "${PELICAN_ROOT_CANDIDATE_ABS}/native-staging/audio/CMakeLists.txt" AND
       EXISTS "${PELICAN_ROOT_CANDIDATE_ABS}/native-staging/scene/CMakeLists.txt")
        set(PELICAN_REPO_ROOT "${PELICAN_ROOT_CANDIDATE_ABS}")
        break()
    endif()
endforeach()
if(PELICAN_REPO_ROOT STREQUAL "")
    message(FATAL_ERROR "Cannot locate native-staging from ${CMAKE_CURRENT_LIST_DIR}")
endif()
set(PELICAN_STAGING_ROOT "${PELICAN_REPO_ROOT}/native-staging")
set(PELICAN_COREGAME_DIR "${PELICAN_STAGING_ROOT}/coregame")
set(PELICAN_AUDIO_DIR "${PELICAN_STAGING_ROOT}/audio")
set(PELICAN_SCENE_DIR "${PELICAN_STAGING_ROOT}/scene")

option(PELICAN_INTEGRATION_BUILD_HOST_TESTS "Build host-only engine/route/touch tests" OFF)
option(PELICAN_INTEGRATION_BUILD_HARMONY_LIBRARY "Build libpelican.so on Harmony" ON)

# Consume staging sources in place so gameplay/DSP/scene algorithms remain single-source.
# Disable staging-owned host executables when included from this integration project.
set(PELICAN_COREGAME_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(PELICAN_AUDIO_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(PELICAN_AUDIO_BUILD_WAV_RENDERER OFF CACHE BOOL "" FORCE)
add_subdirectory("${PELICAN_COREGAME_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/staging/coregame")
add_subdirectory("${PELICAN_AUDIO_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/staging/audio")
include("${PELICAN_SCENE_DIR}/CMakeLists.txt")

add_library(pelican_engine STATIC
    engine_types.cpp
    engine.cpp
    touch_tracker.cpp
    ${PELICAN_SCENE_SOURCES}
    ${PELICAN_SCENE_HEADERS})

target_include_directories(pelican_engine
    PUBLIC
        "${CMAKE_CURRENT_LIST_DIR}"
        "${PELICAN_SCENE_DIR}")
target_link_libraries(pelican_engine
    PUBLIC
        pelican::coregame
        pelican::audio)
target_compile_features(pelican_engine PUBLIC cxx_std_17)
set_target_properties(pelican_engine PROPERTIES POSITION_INDEPENDENT_CODE ON)

if(MSVC)
    target_compile_options(pelican_engine PRIVATE /W4 /permissive- /EHsc)
else()
    target_compile_options(pelican_engine PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "OHOS" AND PELICAN_INTEGRATION_BUILD_HARMONY_LIBRARY)
    add_library(pelican SHARED
        napi_init.cpp
        pelican_renderer.cpp)
    target_include_directories(pelican PRIVATE "${CMAKE_CURRENT_LIST_DIR}")
    target_link_libraries(pelican PRIVATE
        pelican_engine
        libace_napi.z.so
        libace_ndk.z.so
        libnative_window.so
        libnative_vsync.so
        libEGL.so
        libGLESv3.so
        libhilog_ndk.z.so
        librawfile.z.so
        libohaudio.so)
    target_compile_features(pelican PRIVATE cxx_std_17)
    target_compile_options(pelican PRIVATE -Wall -Wextra -Wpedantic)
elseif(NOT CMAKE_SYSTEM_NAME STREQUAL "OHOS")
    target_compile_definitions(pelican_engine PUBLIC PELICAN_SCENE_MOCK_GLES=1)
endif()

if(PELICAN_INTEGRATION_BUILD_HOST_TESTS)
    enable_testing()
    add_executable(pelican_engine_tests tests/engine_tests.cpp)
    target_link_libraries(pelican_engine_tests PRIVATE pelican_engine)
    target_compile_features(pelican_engine_tests PRIVATE cxx_std_17)
    if(MSVC)
        target_compile_options(pelican_engine_tests PRIVATE /W4 /permissive- /EHsc)
    else()
        target_compile_options(pelican_engine_tests PRIVATE -Wall -Wextra -Wpedantic)
    endif()
    add_test(NAME pelican_engine_tests COMMAND pelican_engine_tests)
endif()
