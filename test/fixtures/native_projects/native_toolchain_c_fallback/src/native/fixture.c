#include <stdio.h>

#ifdef _WIN32
#define FALLBACK_EXPORT __declspec(dllexport)
#else
#define FALLBACK_EXPORT __attribute__((visibility("default")))
#endif

FALLBACK_EXPORT int native_toolchain_c_fallback_add(int a, int b) {
  return a + b;
}

FALLBACK_EXPORT const char* native_toolchain_c_fallback_version(void) {
  return "1.0.0";
}
