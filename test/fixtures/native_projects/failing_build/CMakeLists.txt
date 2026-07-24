cmake_minimum_required(VERSION 3.16)

project(native_prebuilt_failing LANGUAGES C)

add_library(native_prebuilt_failing SHARED
  src/broken.c
)
