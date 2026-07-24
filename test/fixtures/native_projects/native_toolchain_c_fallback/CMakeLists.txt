cmake_minimum_required(VERSION 3.16)

project(native_toolchain_c_fallback LANGUAGES C)

add_library(native_toolchain_c_fallback SHARED
  src/native/fixture.c
)

target_include_directories(native_toolchain_c_fallback
  PUBLIC src/native
)
