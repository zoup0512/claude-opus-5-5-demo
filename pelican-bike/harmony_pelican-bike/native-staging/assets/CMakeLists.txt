cmake_minimum_required(VERSION 3.16)
project(pelican_assets LANGUAGES CXX)

option(PELICAN_ASSETS_BUILD_HOST_TESTS "Build AssetBundle host validation tests" ON)
option(PELICAN_ASSETS_BUILD_GLES "Build SceneAssetGpu OpenGL ES adapter" ON)
option(PELICAN_ASSETS_BUILD_RAWFILE "Build Harmony rawfile loader when targeting OHOS" ON)

set(PELICAN_ASSETS_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/include")

add_library(pelican_asset_bundle STATIC
    src/AssetBundle.cpp
)
add_library(pelican::asset_bundle ALIAS pelican_asset_bundle)
target_compile_features(pelican_asset_bundle PUBLIC cxx_std_17)
target_include_directories(pelican_asset_bundle PUBLIC "${PELICAN_ASSETS_INCLUDE_DIR}")
set_target_properties(pelican_asset_bundle PROPERTIES
    CXX_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON
)

if(MSVC)
    target_compile_options(pelican_asset_bundle PRIVATE /W4 /permissive- /EHsc)
else()
    target_compile_options(pelican_asset_bundle PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(PELICAN_ASSETS_BUILD_GLES)
    add_library(pelican_scene_asset_gpu STATIC
        src/SceneAssetGpu.cpp
    )
    add_library(pelican::scene_asset_gpu ALIAS pelican_scene_asset_gpu)
    target_compile_features(pelican_scene_asset_gpu PUBLIC cxx_std_17)
    target_include_directories(pelican_scene_asset_gpu PUBLIC "${PELICAN_ASSETS_INCLUDE_DIR}")
    target_link_libraries(pelican_scene_asset_gpu PUBLIC pelican::asset_bundle)
    set_target_properties(pelican_scene_asset_gpu PROPERTIES
        CXX_EXTENSIONS OFF
        POSITION_INDEPENDENT_CODE ON
    )
    if(CMAKE_SYSTEM_NAME STREQUAL "OHOS")
        target_link_libraries(pelican_scene_asset_gpu PUBLIC GLESv3)
    elseif(WIN32)
        message(STATUS "Host GLES target is disabled on Windows; use the OHOS cross build for SceneAssetGpu")
        set_target_properties(pelican_scene_asset_gpu PROPERTIES EXCLUDE_FROM_ALL TRUE)
    else()
        find_library(PELICAN_GLES_LIBRARY GLESv3)
        if(PELICAN_GLES_LIBRARY)
            target_link_libraries(pelican_scene_asset_gpu PUBLIC "${PELICAN_GLES_LIBRARY}")
        endif()
    endif()
endif()

if(PELICAN_ASSETS_BUILD_RAWFILE AND CMAKE_SYSTEM_NAME STREQUAL "OHOS")
    add_library(pelican_asset_rawfile STATIC
        src/RawFileLoader.cpp
    )
    add_library(pelican::asset_rawfile ALIAS pelican_asset_rawfile)
    target_compile_features(pelican_asset_rawfile PUBLIC cxx_std_17)
    target_include_directories(pelican_asset_rawfile PUBLIC "${PELICAN_ASSETS_INCLUDE_DIR}")
    target_link_libraries(pelican_asset_rawfile PUBLIC pelican::asset_bundle rawfile.z)
    set_target_properties(pelican_asset_rawfile PROPERTIES
        CXX_EXTENSIONS OFF
        POSITION_INDEPENDENT_CODE ON
    )
endif()

if(PELICAN_ASSETS_BUILD_HOST_TESTS AND NOT CMAKE_CROSSCOMPILING)
    enable_testing()
    add_executable(pelican_asset_bundle_tests tests/AssetBundleTests.cpp)
    target_compile_features(pelican_asset_bundle_tests PRIVATE cxx_std_17)
    target_link_libraries(pelican_asset_bundle_tests PRIVATE pelican::asset_bundle)
    set_target_properties(pelican_asset_bundle_tests PROPERTIES CXX_EXTENSIONS OFF)
    if(MSVC)
        target_compile_options(pelican_asset_bundle_tests PRIVATE /W4 /permissive- /EHsc)
    else()
        target_compile_options(pelican_asset_bundle_tests PRIVATE -Wall -Wextra -Wpedantic)
    endif()
    set(PELICAN_DEFAULT_PAK "${CMAKE_CURRENT_SOURCE_DIR}/../../packed-assets/pelican_assets.pak")
    add_test(NAME pelican_asset_bundle_tests COMMAND pelican_asset_bundle_tests "${PELICAN_DEFAULT_PAK}")
endif()
