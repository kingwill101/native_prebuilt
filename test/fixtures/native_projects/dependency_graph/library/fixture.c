#include "fixture.h"
#include "dependency.h"

FIXTURE_EXPORT int native_prebuilt_fixture_add(int a, int b) {
  return a + b;
}

/* Uses the dependency */
FIXTURE_EXPORT int native_prebuilt_fixture_multiply_and_add(int a, int b, int c) {
  return dependency_multiply(a, b) + c;
}
