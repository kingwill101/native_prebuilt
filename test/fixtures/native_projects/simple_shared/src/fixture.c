#include "fixture.h"

FIXTURE_EXPORT int native_prebuilt_fixture_add(int a, int b) {
  return a + b;
}

FIXTURE_EXPORT const char* native_prebuilt_fixture_version(void) {
  return "1.0.0";
}
