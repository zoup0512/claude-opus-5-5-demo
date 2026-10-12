# Source list intended to be included from the Harmony native library's existing CMakeLists.txt.
# This file does not create or modify the outer application/entry target.
# It also supports standalone host-test configuration when this directory is the CMake root.

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    cmake_minimum_required(VERSION 3.16)
    project(pelican_scene_host_tests LANGUAGES CXX)
endif()

set(PELICAN_SCENE_DIR "${CMAKE_CURRENT_LIST_DIR}")
set(PELICAN_SCENE_SOURCES
    "${PELICAN_SCENE_DIR}/Geometry.cpp"
    "${PELICAN_SCENE_DIR}/Simulation.cpp"
    "${PELICAN_SCENE_DIR}/GlResources.cpp"
    "${PELICAN_SCENE_DIR}/Shaders.cpp"
    "${PELICAN_SCENE_DIR}/RenderScene.cpp"
)
set(PELICAN_SCENE_HEADERS
    "${PELICAN_SCENE_DIR}/SceneMath.h"
    "${PELICAN_SCENE_DIR}/SceneGles.h"
    "${PELICAN_SCENE_DIR}/Geometry.h"
    "${PELICAN_SCENE_DIR}/Simulation.h"
    "${PELICAN_SCENE_DIR}/GlResources.h"
    "${PELICAN_SCENE_DIR}/Shaders.h"
    "${PELICAN_SCENE_DIR}/RenderScene.h"
)

# Integration example for the outer project:
# target_sources(your_native_target PRIVATE ${PELICAN_SCENE_SOURCES} ${PELICAN_SCENE_HEADERS})
# target_include_directories(your_native_target PRIVATE "${PELICAN_SCENE_DIR}")
# target_compile_features(your_native_target PRIVATE cxx_std_17)
# target_link_libraries(your_native_target PRIVATE GLESv3 EGL)

option(PELICAN_SCENE_BUILD_HOST_TESTS "Build scene core tests with mock GLES" OFF)
if(PELICAN_SCENE_BUILD_HOST_TESTS)
    add_executable(pelican_scene_core_tests
        ${PELICAN_SCENE_SOURCES}
        "${PELICAN_SCENE_DIR}/host/CoreTests.cpp"
    )
    target_include_directories(pelican_scene_core_tests PRIVATE "${PELICAN_SCENE_DIR}")
    target_compile_features(pelican_scene_core_tests PRIVATE cxx_std_17)
    target_compile_definitions(pelican_scene_core_tests PRIVATE PELICAN_SCENE_MOCK_GLES=1)
    if(MSVC)
        target_compile_options(pelican_scene_core_tests PRIVATE /W4 /permissive-)
    else()
        target_compile_options(pelican_scene_core_tests PRIVATE -Wall -Wextra -Wpedantic)
    endif()
endif()
