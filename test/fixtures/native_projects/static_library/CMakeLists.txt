cmake_minimum_required(VERSION 3.16)

project(native_prebuilt_static LANGUAGES C)

add_library(native_prebuilt_fixture_static STATIC
  src/fixture.c
)

target_include_directories(native_prebuilt_fixture_static
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
)
