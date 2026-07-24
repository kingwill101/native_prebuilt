cmake_minimum_required(VERSION 3.16)

project(native_prebuilt_patchable LANGUAGES C)

add_library(native_prebuilt_patchable SHARED
  src/fixture.c
)

target_include_directories(native_prebuilt_patchable
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/../simple_shared/include
)
