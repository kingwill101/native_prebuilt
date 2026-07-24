#ifndef DEPENDENCY_H
#define DEPENDENCY_H

#ifdef _WIN32
#define DEPENDENCY_EXPORT __declspec(dllexport)
#else
#define DEPENDENCY_EXPORT __attribute__((visibility("default")))
#endif

/**
 * Multiplies two integers.
 */
DEPENDENCY_EXPORT int dependency_multiply(int a, int b);

#endif /* DEPENDENCY_H */
