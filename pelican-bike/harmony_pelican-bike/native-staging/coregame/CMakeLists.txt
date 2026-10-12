cmake_minimum_required(VERSION 3.16)

project(pelican_coregame VERSION 1.0.0 LANGUAGES CXX)

option(PELICAN_COREGAME_BUILD_TESTS "Build the host-side coregame test executable" ON)

add_library(pelican_coregame STATIC
  src/environment.cpp
  src/math.cpp
  src/random.cpp
  src/simulation.cpp
)
add_library(pelican::coregame ALIAS pelican_coregame)

target_compile_features(pelican_coregame PUBLIC cxx_std_17)
target_include_directories(pelican_coregame
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
set_target_properties(pelican_coregame PROPERTIES
  CXX_EXTENSIONS OFF
  POSITION_INDEPENDENT_CODE ON
)

if(MSVC)
  target_compile_options(pelican_coregame PRIVATE /W4 /permissive- /EHsc)
else()
  target_compile_options(pelican_coregame PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(PELICAN_COREGAME_BUILD_TESTS)
  enable_testing()
  add_executable(pelican_coregame_tests tests/coregame_tests.cpp)
  target_link_libraries(pelican_coregame_tests PRIVATE pelican::coregame)
  target_compile_features(pelican_coregame_tests PRIVATE cxx_std_17)
  set_target_properties(pelican_coregame_tests PROPERTIES CXX_EXTENSIONS OFF)
  if(MSVC)
    target_compile_options(pelican_coregame_tests PRIVATE /W4 /permissive- /EHsc)
  else()
    target_compile_options(pelican_coregame_tests PRIVATE -Wall -Wextra -Wpedantic)
  endif()
  set(PELICAN_REFERENCE_VECTORS
      "${CMAKE_CURRENT_SOURCE_DIR}/../../docs/reference-vectors/pelican-bike-golden.json")
  if(NOT EXISTS "${PELICAN_REFERENCE_VECTORS}")
    set(PELICAN_REFERENCE_VECTORS
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/reference-vectors.json")
  endif()
  add_test(
    NAME pelican_coregame_tests
    COMMAND pelican_coregame_tests "${PELICAN_REFERENCE_VECTORS}"
  )
endif()
