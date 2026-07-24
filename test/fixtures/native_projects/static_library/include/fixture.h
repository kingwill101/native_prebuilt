#ifndef FIXTURE_H
#define FIXTURE_H

#ifdef _WIN32
#define FIXTURE_EXPORT __declspec(dllexport)
#else
#define FIXTURE_EXPORT __attribute__((visibility("default")))
#endif

/**
 * Adds two integers.
 *
 * @param a First operand
 * @param b Second operand
 * @return The sum of a and b
 */
FIXTURE_EXPORT int native_prebuilt_fixture_add(int a, int b);

/**
 * Returns the fixture version.
 *
 * @return Version string pointer (do not free)
 */
FIXTURE_EXPORT const char* native_prebuilt_fixture_version(void);

#endif /* FIXTURE_H */
