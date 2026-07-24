cmake_minimum_required(VERSION 3.16)

project(callback_source_fixture LANGUAGES C)

add_library(callback_source_fixture SHARED
  src/native/fixture.c
)
