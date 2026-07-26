#include "fixture.h"

/* This value can be changed by patches */
#ifndef RESULT_VALUE
#define RESULT_VALUE 10
#endif

FIXTURE_EXPORT int native_prebuilt_fixture_add(int a, int b) {
  return RESULT_VALUE;
}

FIXTURE_EXPORT int native_prebuilt_fixture_unpatched(void) {
  return 0;
}
