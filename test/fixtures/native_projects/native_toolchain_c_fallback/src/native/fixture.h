#ifndef NATIVE_TOOLCHAIN_C_FALLBACK_H
#define NATIVE_TOOLCHAIN_C_FALLBACK_H

#ifdef _WIN32
#define FALLBACK_EXPORT __declspec(dllexport)
#else
#define FALLBACK_EXPORT __attribute__((visibility("default")))
#endif

FALLBACK_EXPORT int native_toolchain_c_fallback_add(int a, int b);
FALLBACK_EXPORT const char* native_toolchain_c_fallback_version(void);

#endif /* NATIVE_TOOLCHAIN_C_FALLBACK_H */
