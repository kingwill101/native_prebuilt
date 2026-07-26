#include "fixture.h"

/* Static library can have internal functions that are not exported */
static int helper_function(int x) {
  return x * 2;
}

FIXTURE_EXPORT int native_prebuilt_fixture_add(int a, int b) {
  return a + b + helper_function(0); /* Ensures helper is linked */
}
