cmake_minimum_required(VERSION 3.16)

project(native_prebuilt_generated LANGUAGES C)

# Generated source fixture
set(GENERATED_SOURCE ${CMAKE_CURRENT_BINARY_DIR}/generated/value.c)

add_library(native_prebuilt_generated SHARED
  ${GENERATED_SOURCE}
  src/wrapper.c
)

target_include_directories(native_prebuilt_generated
  PUBLIC ${CMAKE_CURRENT_BINARY_DIR}/generated
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/../simple_shared/include
)
