cmake_minimum_required(VERSION 3.16)

project(native_prebuilt_dependency LANGUAGES C)

# Dependency library (static)
add_library(fixture_dependency STATIC
  dependency/dependency.c
)

target_include_directories(fixture_dependency
  PUBLIC dependency
)

# Main library (shared)
add_library(native_prebuilt_dependency SHARED
  library/fixture.c
)

target_include_directories(native_prebuilt_dependency
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(native_prebuilt_dependency
  PRIVATE fixture_dependency
)
