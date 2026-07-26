cmake_minimum_required(VERSION 3.16)

project(native_prebuilt_generated LANGUAGES C)

# Generate C source from input value.txt
set(GENERATED_SOURCE ${CMAKE_CURRENT_BINARY_DIR}/generated/value.c)

add_custom_command(
  OUTPUT ${GENERATED_SOURCE}
  COMMAND dart tool/generate.dart
          ${CMAKE_CURRENT_SOURCE_DIR}/input
          ${GENERATED_SOURCE}
  DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/input/value.txt
          ${CMAKE_CURRENT_SOURCE_DIR}/tool/generate.dart
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  COMMENT "Generating value.c from value.txt"
)

# Generated source fixture
add_library(native_prebuilt_generated SHARED
  ${GENERATED_SOURCE}
  src/wrapper.c
)

target_include_directories(native_prebuilt_generated
  PUBLIC ${CMAKE_CURRENT_BINARY_DIR}/generated
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
)
