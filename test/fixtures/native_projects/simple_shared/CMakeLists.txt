cmake_minimum_required(VERSION 3.16)

project(native_prebuilt_fixture LANGUAGES C)

# Shared library fixture
add_library(native_prebuilt_fixture SHARED
  src/fixture.c
)

target_include_directories(native_prebuilt_fixture
  PUBLIC include
)

# Static library fixture
add_library(native_prebuilt_fixture_static STATIC
  src/fixture.c
)

target_include_directories(native_prebuilt_fixture_static
  PUBLIC include
)
