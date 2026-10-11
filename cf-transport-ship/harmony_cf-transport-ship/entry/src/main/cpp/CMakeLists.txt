cmake_minimum_required(VERSION 3.5.0)
project(harmony_cf_transport_ship)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH})

add_library(gameRenderer SHARED
    napi_init.cpp
    renderer.cpp)

target_link_libraries(gameRenderer PUBLIC
    libace_napi.z.so
    libEGL.so
    libGLESv3.so
    libnativewindow.so
    libhilog_ndk.z.so)
