#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

EXPORT int callback_source_fixture_add(int a, int b) {
  return a + b;
}
