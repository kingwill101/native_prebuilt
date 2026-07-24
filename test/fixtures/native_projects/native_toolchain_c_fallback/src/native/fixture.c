#include "fixture.h"

FALLBACK_EXPORT int native_toolchain_c_fallback_add(int a, int b) {
  return a + b;
}

FALLBACK_EXPORT const char* native_toolchain_c_fallback_version(void) {
  return "1.0.0";
}
